import 'package:flutter/material.dart';

import '../logic/sm2.dart';
import '../models/flashcard.dart';
import '../storage/app_store.dart';

class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({super.key});

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  final _store = AppStore();
  List<Flashcard> _cards = [];
  bool _showAnswer = false;

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

  Future<void> _grade(Flashcard card, int quality) async {
    reviewCard(card, quality);
    _showAnswer = false;
    await _store.saveCards(_cards);
    if (mounted) setState(() {});
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
      body: due.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _cards.isEmpty
                      ? 'No flashcards yet.\nAdd concepts to remember or problems to re-solve!'
                      : 'All caught up!\n${_cards.length} card(s), none due right now.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            )
          : _reviewView(due.first, due.length),
    );
  }

  Widget _reviewView(Flashcard card, int dueCount) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('$dueCount due', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
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
                _gradeButton('Hard', 3, Colors.orangeAccent, card),
                _gradeButton('Good', 4, Colors.lightGreen, card),
                _gradeButton('Easy', 5, Colors.greenAccent, card),
              ],
            ),
        ],
      ),
    );
  }

  Widget _gradeButton(String label, int quality, Color color, Flashcard card) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: color),
          onPressed: () => _grade(card, quality),
          child: Text(label),
        ),
      ),
    );
  }
}
