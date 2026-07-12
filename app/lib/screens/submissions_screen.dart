import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';

/// The signed-in user's imported CodeChef submissions, straight from the
/// backend (`/api/me/submissions`). Tapping a row with source code opens a
/// viewer with a copy button.
class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({super.key});

  @override
  State<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<SubmissionsScreen> {
  final _api = ApiClient();
  final _submissions = <Map<String, dynamic>>[];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.fetchMySubmissions(limit: 50);
      _submissions
        ..clear()
        ..addAll(((data['submissions'] as List?) ?? [])
            .map((s) => (s as Map).cast<String, dynamic>()));
      _total = ((data['total'] as num?) ?? 0).toInt();
    } catch (err) {
      _error = '$err';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _submissions.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final data =
          await _api.fetchMySubmissions(limit: 50, offset: _submissions.length);
      _submissions.addAll(((data['submissions'] as List?) ?? [])
          .map((s) => (s as Map).cast<String, dynamic>()));
      _total = ((data['total'] as num?) ?? 0).toInt();
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _openSource(Map<String, dynamic> submission) async {
    try {
      final full = await _api.fetchMySubmission(submission['id'] as String);
      final source = full['sourceCode'] as String?;
      if (!mounted) return;
      if (source == null || source.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No source code stored for this submission.')));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${submission['problemCode']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                source,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: source));
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('Copy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load: $err')));
      }
    }
  }

  bool _isAccepted(Map<String, dynamic> s) =>
      (s['result'] as String? ?? '').toLowerCase().contains('accepted');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('CodeChef solutions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _submissions.isEmpty
                  ? Center(
                      child: Text(
                        'No submissions imported yet.\n'
                        'Run an import from Settings.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels >
                              n.metrics.maxScrollExtent - 200) {
                            _loadMore();
                          }
                          return false;
                        },
                        child: ListView.builder(
                          itemCount:
                              _submissions.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (context, i) {
                            if (i >= _submissions.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                    child: CircularProgressIndicator()),
                              );
                            }
                            final s = _submissions[i];
                            final at = s['submittedAt'] != null
                                ? DateTime.tryParse('${s['submittedAt']}')
                                    ?.toLocal()
                                : null;
                            final hasSource = s['hasSource'] == true;
                            return ListTile(
                              leading: Icon(
                                _isAccepted(s)
                                    ? Icons.check_circle_outline
                                    : Icons.cancel_outlined,
                                color: _isAccepted(s)
                                    ? Colors.greenAccent
                                    : Colors.redAccent,
                              ),
                              title: Text('${s['problemCode']}'),
                              subtitle: Text([
                                if (s['result'] != null) '${s['result']}',
                                if (s['language'] != null) '${s['language']}',
                                if (at != null)
                                  DateFormat('d MMM y, HH:mm').format(at),
                              ].join(' · ')),
                              trailing: hasSource
                                  ? const Icon(Icons.code, size: 18)
                                  : null,
                              onTap: hasSource ? () => _openSource(s) : null,
                            );
                          },
                        ),
                      ),
                    ),
    );
  }
}
