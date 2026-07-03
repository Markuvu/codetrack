import 'package:flutter/material.dart';

import '../logic/fsrs.dart';
import '../models/flashcard.dart';
import '../services/api_client.dart';
import '../storage/app_store.dart';

class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  final _store = AppStore();
  final _api = ApiClient();
  List<Flashcard> _cards = [];
  bool _showAnswer = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _cards = await _store.loadCards();
    if (mounted) setState(() {});
  }

  List<Flashcard> get _due => _cards.where((c) => c.isDue).toList();

  Future<void> _grade(Flashcard card, int rating) async {
    reviewCard(card, rating);
    _showAnswer = false;
    await _store.saveCards(_cards);
    if (mounted) setState(() {});
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Auto-generate "re-solve" cards from recent Codeforces AC submissions.
  Future<void> _importSolved() async {
    if (_importing) return;
    final handles = await _store.loadHandles();
    final handle = handles['codeforces'];
    if (handle == null) {
      _snack('Add your Codeforces handle in the Profiles tab first.');
      return;
    }
    setState(() => _importing = true);
    try {
      final problems = await _api.fetchRecentSolved(handle);
      final existing =
          _cards.map((c) => c.sourceUrl).whereType<String>().toSet();
      var added = 0;
      for (final problem in problems) {
        final url = problem['url'] as String? ?? '';
        if (url.isEmpty || existing.contains(url)) continue;
        final rating =
            problem['rating'] != null ? ' (rated ${problem['rating']})' : '';
        final tags = (problem['tags'] as List?)?.join(', ') ?? '';
        _cards.add(Flashcard(
          id: 'cf-${problem['id']}',
          front: 'Re-solve: ${problem['name']}$rating\n\n'
              'Can you recall the key idea?',
          back: (tags.isEmpty ? '' : 'Tags: $tags\n') + url,
          sourceUrl: url,
        ));
        added++;
      }
      await _store.saveCards(_cards);
      if (mounted) setState(() {});
      _snack(added > 0
          ? 'Imported $added problem card(s) from Codeforces.'
          : 'No new solved problems to import.');
    } catch (err) {
      _snack('Import failed: $err');
    }
    if (mounted) setState(() => _importing = false);
  }

  Future<void> _addCard() async {
    final frontController = TextEditingController();
    final backController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New flashcard'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: frontController,
              decoration: const InputDecoration(labelText: 'Front (question)'),
            ),
            TextField(
              controller: backController,
              decoration: const InputDecoration(labelText: 'Back (answer)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (saved != true || frontController.text.trim().isEmpty) return;

    _cards.add(Flashcard(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      front: frontController.text.trim(),
      back: backController.text.trim(),
    ));
    await _store.saveCards(_cards);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final due = _due;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addCard,
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${due.length} due  |  ${_cards.length} total',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                TextButton.icon(
                  icon: _importing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: const Text('Import CF solves'),
                  onPressed: _importSolved,
                ),
              ],
            ),
          ),
          Expanded(
            child: due.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _cards.isEmpty
                            ? 'No flashcards yet.\n'
                                'Add concepts manually or import your recent '
                                'Codeforces solves!'
                            : 'All caught up!\n'
                                '${_cards.length} card(s), none due right now.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  )
                : _reviewView(due.first),
          ),
        ],
      ),
    );
  }

  Widget _reviewView(Flashcard card) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Card(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(
                    child: Text(
                      _showAnswer ? card.back : card.front,
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!_showAnswer)
            FilledButton(
              onPressed: () => setState(() => _showAnswer = true),
              child: const Text('Show answer'),
            )
          else
            Row(
              children: [
                _gradeButton('Again', 1, Colors.redAccent, card),
                _gradeButton('Hard', 2, Colors.orangeAccent, card),
                _gradeButton('Good', 3, Colors.lightGreen, card),
                _gradeButton('Easy', 4, Colors.greenAccent, card),
              ],
            ),
        ],
      ),
    );
  }

  Widget _gradeButton(String label, int rating, Color color, Flashcard card) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: color),
          onPressed: () => _grade(card, rating),
          child: Text(label),
        ),
      ),
    );
  }
}
