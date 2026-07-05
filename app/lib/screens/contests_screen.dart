import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/contest.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../storage/app_store.dart';
import '../widgets/platform_logo.dart';

class ContestsScreen extends StatefulWidget {
  const ContestsScreen({super.key});

  @override
  State<ContestsScreen> createState() => _ContestsScreenState();
}

class _ContestsScreenState extends State<ContestsScreen> {
  static const _leadOptions = [
    Duration(minutes: 10),
    Duration(minutes: 30),
    Duration(hours: 1),
    Duration(days: 1),
  ];

  final _api = ApiClient();
  final _store = AppStore();
  late Future<List<Contest>> _future;
  String? _filter; // normalized platform key; null = show all

  final _dateFormat = DateFormat('EEE, d MMM  HH:mm');

  @override
  void initState() {
    super.initState();
    _future = _api.fetchContests();
  }

  Future<void> _reload() async {
    setState(() => _future = _api.fetchContests());
    await _future;
  }

  // --- platform helpers -------------------------------------------------

  String _key(String platform) {
    final p = platform.toLowerCase();
    if (p.contains('codeforces')) return 'codeforces';
    if (p.contains('leetcode')) return 'leetcode';
    if (p.contains('codechef')) return 'codechef';
    if (p.contains('atcoder')) return 'atcoder';
    if (p.contains('geeksforgeeks') || p.contains('gfg')) return 'gfg';
    return p.replaceAll(RegExp(r'\.(com|org|jp|in)$'), '');
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

  // --- reminders ---------------------------------------------------------

  String _leadLabel(Duration d) {
    if (d.inDays >= 1) return '${d.inDays} day before';
    if (d.inHours >= 1) return '${d.inHours} hour before';
    return '${d.inMinutes} min before';
  }

  Future<void> _pickReminder(Contest contest) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Reminders are not supported in the browser - use the Android app.'),
        ),
      );
      return;
    }
    final before = await showModalBottomSheet<Duration>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'Remind me about "${contest.name}"',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final d in _leadOptions)
              ListTile(
                leading: const Icon(Icons.alarm),
                title: Text(_leadLabel(d)),
                enabled: contest.start.subtract(d).isAfter(DateTime.now()),
                onTap: () => Navigator.pop(context, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (before == null) return;
    await _setReminder(contest, before);
  }

  Future<void> _setReminder(Contest contest, Duration before) async {
    final id = await NotificationService.instance
        .scheduleContestReminder(contest, before: before);
    if (!mounted) return;
    if (id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'That reminder time has already passed - pick a shorter lead time.'),
        ),
      );
      return;
    }

    final reminders = await _store.loadReminders();
    reminders.removeWhere((r) => r['notifId'] == id);
    reminders.add({
      'notifId': id,
      'contestName': contest.name,
      'platform': platformDisplayName(_key(contest.platform)),
      'startMs': contest.start.millisecondsSinceEpoch,
      'notifyAtMs': contest.start.subtract(before).millisecondsSinceEpoch,
    });
    await _store.saveReminders(reminders);

    if (!mounted) return;
    final notifyAt =
        _dateFormat.format(contest.start.subtract(before).toLocal());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Text(
          'Reminder set - notification on $notifyAt (${_leadLabel(before)} start).',
        ),
      ),
    );
  }

  Future<void> _showReminders() async {
    final all = await _store.loadReminders();
    final now = DateTime.now().millisecondsSinceEpoch;
    final upcoming = all.where((r) => (r['notifyAtMs'] as num) > now).toList()
      ..sort((a, b) => (a['notifyAtMs'] as num).compareTo(b['notifyAtMs'] as num));
    if (upcoming.length != all.length) await _store.saveReminders(upcoming);
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: upcoming.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No scheduled reminders.\nTap the bell on a contest to add one.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    const ListTile(
                      title: Text(
                        'Scheduled reminders',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    for (final r in List.of(upcoming))
                      ListTile(
                        leading: const Icon(Icons.alarm),
                        title: Text('${r['contestName']}'),
                        subtitle: Text(
                          '${r['platform']}  |  notifies '
                          '${_dateFormat.format(DateTime.fromMillisecondsSinceEpoch((r['notifyAtMs'] as num).toInt()))}',
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Cancel reminder',
                          onPressed: () async {
                            await NotificationService.instance
                                .cancel((r['notifId'] as num).toInt());
                            upcoming.remove(r);
                            await _store.saveReminders(upcoming);
                            setSheetState(() {});
                          },
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }

  // --- UI ---------------------------------------------------------------

  /// Compact filter chip; chips are laid out in a [Wrap] so every platform
  /// is visible at once (no horizontal scrolling).
  Widget _filterChip({
    Widget? avatar,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      avatar: avatar,
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  @override
  Widget build(BuildContext context) {
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _filterChip(
                          label: 'All (${contests.length})',
                          selected: _filter == null,
                          onTap: () => setState(() => _filter = null),
                        ),
                        for (final k in keys)
                          _filterChip(
                            avatar: PlatformLogo(k, size: 18),
                            label:
                                '${platformDisplayName(k)} '
                                '(${contests.where((c) => _key(c.platform) == k).length})',
                            selected: _filter == k,
                            onTap: () => setState(
                                () => _filter = _filter == k ? null : k),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_notifications_outlined),
                    tooltip: 'Manage reminders',
                    onPressed: _showReminders,
                  ),
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
                  itemBuilder: (context, i) => _contestCard(visible[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _contestCard(Contest contest) {
    final key = _key(contest.platform);
    final color = platformColor(key);
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
            PlatformLogo(key, size: 40),
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
                    '${_dateFormat.format(contest.start.toLocal())}'
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
                          platformDisplayName(key),
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
              tooltip: 'Set reminder',
              onPressed: () => _pickReminder(contest),
            ),
          ],
        ),
      ),
    );
  }
}
