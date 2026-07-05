import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/contest.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';

class ContestsScreen extends StatefulWidget {
  const ContestsScreen({super.key});

  @override
  State<ContestsScreen> createState() => _ContestsScreenState();
}

class _ContestsScreenState extends State<ContestsScreen> {
  static const _reminderBefore = Duration(minutes: 30);

  final _api = ApiClient();
  late Future<List<Contest>> _future;
  String? _filter; // normalized platform key; null = show all

  @override
  void initState() {
    super.initState();
    _future = _api.fetchContests();
  }

  Future<void> _reload() async {
    setState(() => _future = _api.fetchContests());
    await _future;
  }

  // --- platform helpers -----------------------------------------------

  String _key(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('codeforces')) return 'codeforces';
    if (p.contains('leetcode')) return 'leetcode';
    if (p.contains('codechef')) return 'codechef';
    if (p.contains('atcoder')) return 'atcoder';
    if (p.contains('geeksforgeeks') || p.contains('gfg')) return 'gfg';
    return p.replaceAll(RegExp(r'\.(com|org|jp|in)$'), '');
  }

  String _label(String key) {
    switch (key) {
      case 'codeforces':
        return 'Codeforces';
      case 'leetcode':
        return 'LeetCode';
      case 'codechef':
        return 'CodeChef';
      case 'atcoder':
        return 'AtCoder';
      case 'gfg':
        return 'GeeksforGeeks';
      default:
        return key.isEmpty ? 'Other' : key[0].toUpperCase() + key.substring(1);
    }
  }

  Color _color(String key) {
    switch (key) {
      case 'codeforces':
        return const Color(0xFF5C9DFF);
      case 'leetcode':
        return const Color(0xFFFFA116);
      case 'codechef':
        return const Color(0xFFC5854A);
      case 'atcoder':
        return const Color(0xFFB0BEC5);
      case 'gfg':
        return const Color(0xFF4CAF50);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  String _countdown(DateTime start) {
    final diff = start.difference(DateTime.now());
    if (diff.isNegative) return 'started';
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    final minutes = diff.inMinutes % 60;
    if (days > 0) return 'in ${days}d ${hours}h';
    if (diff.inHours > 0) return 'in ${diff.inHours}h ${minutes}m';
    return 'in ${minutes}m';
  }

  // --- reminder ---------------------------------------------------------

  Future<void> _setReminder(Contest contest, DateFormat dateFormat) async {
    final scheduled = await NotificationService.instance
        .scheduleContestReminder(contest, before: _reminderBefore);
    if (!mounted) return;
    final notifyAt =
        dateFormat.format(contest.start.subtract(_reminderBefore).toLocal());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          scheduled
              ? 'Reminder set - notification on $notifyAt '
                  '(${_reminderBefore.inMinutes} min before start).'
              : kIsWeb
                  ? 'Reminders are not supported in the browser - use the Android app.'
                  : 'Contest starts in less than ${_reminderBefore.inMinutes} minutes - too late to set this reminder.',
        ),
      ),
    );
  }

  // --- UI ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('EEE, d MMM  HH:mm');
    return FutureBuilder<List<Contest>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Could not load contests.\n${snapshot.error}',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }

        final contests = snapshot.data ?? [];
        if (contests.isEmpty) {
          return RefreshIndicator(
            onRefresh: _reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 200),
                Center(child: Text('No upcoming contests found.')),
              ],
            ),
          );
        }

        // Build the filter chip list from the platforms actually present.
        final keys = <String>[];
        for (final c in contests) {
          final k = _key(c.platform);
          if (!keys.contains(k)) keys.add(k);
        }
        final visible = _filter == null
            ? contests
            : contests.where((c) => _key(c.platform) == _filter).toList();

        return Column(
          children: [
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                children: [
                  FilterChip(
                    label: Text('All (${contests.length})'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  for (final k in keys) ...[
                    const SizedBox(width: 8),
                    FilterChip(
                      avatar: CircleAvatar(
                        backgroundColor: _color(k),
                        radius: 6,
                      ),
                      label: Text(
                        '${_label(k)} '
                        '(${contests.where((c) => _key(c.platform) == k).length})',
                      ),
                      selected: _filter == k,
                      onSelected: (selected) =>
                          setState(() => _filter = selected ? k : null),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _reload,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: visible.length,
                  itemBuilder: (context, i) =>
                      _contestCard(visible[i], dateFormat),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _contestCard(Contest contest, DateFormat dateFormat) {
    final key = _key(contest.platform);
    final color = _color(key);
    final hours = contest.duration.inHours;
    final minutes = contest.duration.inMinutes % 60;
    final countdown = _countdown(contest.start);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.18),
              foregroundColor: color,
              child: Text(
                _label(key)[0],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contest.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${dateFormat.format(contest.start.toLocal())}'
                    '  |  ${hours}h ${minutes}m',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _label(key),
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          countdown,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.notifications_active_outlined),
              tooltip: 'Remind me ${_reminderBefore.inMinutes} min before',
              onPressed: () => _setReminder(contest, dateFormat),
            ),
          ],
        ),
      ),
    );
  }
}
