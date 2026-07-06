import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/contest.dart';
import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/widget_sync.dart';
import '../storage/app_store.dart';
import '../widgets/activity_heatmap.dart';
import '../widgets/platform_logo.dart';

const kPlatforms = ['codeforces', 'leetcode', 'codechef', 'atcoder', 'gfg'];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.onOpenContests});

  /// Switches the app to the Contests tab (wired up by HomeShell).
  final VoidCallback? onOpenContests;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiClient();
  final _store = AppStore();

  Map<String, String> _handles = {};
  final Map<String, PlatformProfile> _profiles = {};
  final Map<String, String> _errors = {};
  final Map<String, List<Map<String, dynamic>>> _snapshots = {};

  /// Per-platform accepted solves (Codeforces, LeetCode, CodeChef, AtCoder)
  /// with problem names/links. Real history covers the whole week even for
  /// handles linked mid-week; platforms without it (GFG) fall back to
  /// snapshot deltas. Also powers the Recent Solves feed.
  final Map<String, List<Solve>> _activity = {};

  /// Per-platform heatmap data ('yyyy-MM-dd' -> submissions) for the unified
  /// activity calendar. GFG has no public per-day history, so it is absent.
  final Map<String, Map<String, int>> _heatmaps = {};

  List<Contest> _contests = [];
  String? _userName;
  int _weeklyGoal = 50;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _handles = await _store.loadHandles();
    _userName = await AuthService.instance.name();
    _weeklyGoal = await _store.loadWeeklyGoal();
    if (mounted) setState(() {});
    await _refresh();
  }

  /// [fresh] is set by pull-to-refresh: the backend then bypasses its caches
  /// (with short cooldowns), so a problem solved moments ago shows up in
  /// today's weekly-progress bar right away.
  Future<void> _refresh({bool fresh = false}) async {
    setState(() => _loading = true);
    _userName = await AuthService.instance.name();
    await Future.wait([
      ..._handles.entries.map((entry) async {
        try {
          _profiles[entry.key] = await _api.fetchProfile(
              entry.key, entry.value,
              fresh: fresh);
          _errors.remove(entry.key);
        } catch (err) {
          _errors[entry.key] = 'Failed to load: $err';
        }
      }),
      ..._handles.entries.map((entry) async {
        try {
          final solves = await _api.fetchActivity(entry.key, entry.value,
              fresh: fresh);
          if (solves != null) _activity[entry.key] = solves;
        } catch (_) {
          // Best-effort: keep previous data, or fall back to snapshot deltas.
        }
      }),
      ..._handles.entries.map((entry) async {
        try {
          final days = await _api.fetchHeatmap(entry.key, entry.value,
              fresh: fresh);
          if (days != null) _heatmaps[entry.key] = days;
        } catch (_) {
          // Best-effort: the heatmap simply misses this platform for now.
        }
      }),
      () async {
        try {
          _contests = await _api.fetchContests();
        } catch (_) {
          // The contests preview is best-effort; the Contests tab shows errors.
        }
      }(),
    ]);
    // Snapshots are loaded after profiles so a forced refresh picks up the
    // snapshot the backend just recorded for today.
    await Future.wait(_handles.entries.map((entry) async {
      try {
        _snapshots[entry.key] =
            await _api.fetchSnapshots(entry.key, entry.value);
      } catch (_) {
        // Best-effort; the weekly card simply shows fewer bars.
      }
    }));
    if (mounted) setState(() => _loading = false);
    _syncHomeWidget();
  }

  /// Mirrors the freshest streak / weekly progress / next reminder to the
  /// Android home-screen widget. Fire-and-forget; never blocks the UI.
  Future<void> _syncHomeWidget() async {
    final values = _weekValues();
    final total = values.fold<int>(0, (sum, v) => sum + v);
    final now = DateTime.now().toUtc();
    final todayKey = _dateKey(DateTime.utc(now.year, now.month, now.day));
    final activeToday = _activeDays().contains(todayKey);
    await WidgetSync.pushStats(
      streak: _currentStreak(),
      activeToday: activeToday,
      solvedThisWeek: total,
      weeklyGoal: _weeklyGoal,
    );
    await WidgetSync.pushNextReminder(await _store.loadReminders());
  }

  /// Union of days ('yyyy-MM-dd', UTC) with at least one submission on any
  /// platform - shared by the overview card, streak math, and widget sync.
  Set<String> _activeDays() {
    final active = <String>{};
    for (final map in _heatmaps.values) {
      map.forEach((day, count) {
        if (count > 0) active.add(day);
      });
    }
    return active;
  }

  /// Current streak: consecutive active days (submissions on any platform)
  /// ending today - or ending yesterday when today has no submissions yet,
  /// so the streak isn't shown as broken mid-day. UTC day buckets, matching
  /// the heatmap convention.
  int _currentStreak() {
    final active = _activeDays();
    if (active.isEmpty) return 0;
    final now = DateTime.now().toUtc();
    var day = DateTime.utc(now.year, now.month, now.day);
    if (!active.contains(_dateKey(day))) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (active.contains(_dateKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  Future<void> _editHandle(String platform) async {
    final controller = TextEditingController(text: _handles[platform] ?? '');
    final handle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${platformDisplayName(platform)} handle'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. tourist'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (handle == null) return;
    setState(() {
      if (handle.isEmpty) {
        _handles.remove(platform);
        _profiles.remove(platform);
        _errors.remove(platform);
        _snapshots.remove(platform);
        _activity.remove(platform);
        _heatmaps.remove(platform);
      } else {
        _handles[platform] = handle;
      }
    });
    await _store.saveHandles(_handles);
    await _refresh();
  }

  Future<void> _editGoal() async {
    final controller = TextEditingController(text: '$_weeklyGoal');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Weekly goal'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'Problems to solve per week'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result < 1) return;
    setState(() => _weeklyGoal = result);
    await _store.saveWeeklyGoal(result);
    _syncHomeWidget();
  }

  // --- platform helpers --------------------------------------------------

  /// Card order: rated platforms first, then GFG with a coding score (it has
  /// no contest rating), then connected-but-unrated (incl. loading/errored),
  /// then unconnected last. Ties keep the canonical kPlatforms order.
  List<String> _orderedPlatforms() {
    int rank(String platform) {
      if (!_handles.containsKey(platform)) return 3; // unconnected -> last
      final profile = _profiles[platform];
      if (profile == null) return 2; // still loading or errored
      if (platform == 'gfg') {
        return profile.raw['codingScore'] != null ? 1 : 2;
      }
      return profile.rating != null ? 0 : 2; // rated -> first
    }

    final base = {
      for (var i = 0; i < kPlatforms.length; i++) kPlatforms[i]: i,
    };
    final ordered = [...kPlatforms]..sort((a, b) {
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : base[a]!.compareTo(base[b]!);
      });
    return ordered;
  }

  String _metricLabel(String platform) =>
      platform == 'gfg' ? 'Coding Score' : 'Rating';

  String _metricValue(String platform, PlatformProfile profile) {
    if (platform == 'gfg') {
      return profile.raw['codingScore']?.toString() ?? '-';
    }
    return profile.rating?.toString() ?? '-';
  }

  /// Highest rating ever reached, from the contest history. Used for
  /// LeetCode, which exposes no maxRating field of its own.
  int? _peakFromHistory(PlatformProfile p) {
    final history = p.raw['ratingHistory'];
    if (history is! List) return null;
    int? peak;
    for (final point in history) {
      if (point is! Map) continue;
      final r = point['newRating'];
      if (r is num && (peak == null || r > peak)) peak = r.toInt();
    }
    return peak;
  }

  /// '#40707' -> '#40.7K' so long global ranks fit the narrow stat columns.
  String _compactRank(dynamic rank) {
    if (rank is! num) return '-';
    if (rank >= 10000) {
      final k = rank / 1000;
      return '#${k.toStringAsFixed(k >= 100 ? 0 : 1)}K';
    }
    return '#${rank.toInt()}';
  }

  List<MapEntry<String, String>> _subStats(
      String platform, PlatformProfile p) {
    final raw = p.raw;
    final solved = MapEntry('Solved', '${p.solvedCount ?? '-'}');
    switch (platform) {
      case 'codeforces':
        return [MapEntry('Max Rating', '${raw['maxRating'] ?? '-'}'), solved];
      case 'leetcode':
        return [
          MapEntry('Peak', '${_peakFromHistory(p) ?? '-'}'),
          MapEntry('Rank', _compactRank(raw['globalRanking'])),
          solved,
        ];
      case 'codechef':
        return [MapEntry('Max Rating', '${raw['maxRating'] ?? '-'}'), solved];
      case 'atcoder':
        return [
          MapEntry('Contests', '${raw['contestsAttended'] ?? '-'}'),
          solved,
        ];
      case 'gfg':
        return [
          MapEntry(
            'Institute Rank',
            raw['instituteRank'] != null ? '#${raw['instituteRank']}' : '-',
          ),
          solved,
        ];
      default:
        return [solved];
    }
  }

  String? _badge(String platform, PlatformProfile p) {
    final raw = p.raw;
    switch (platform) {
      case 'codeforces':
        final rank = raw['rank'];
        return rank != null ? '$rank' : 'Unrated';
      case 'leetcode':
        final top = raw['topPercentage'];
        return top != null ? 'Top $top%' : null;
      case 'codechef':
        final stars = raw['stars'];
        return stars != null ? '$stars' : null;
      case 'atcoder':
        return raw['maxRating'] != null
            ? 'Max ${raw['maxRating']}'
            : 'Unrated';
      case 'gfg':
        final streak = raw['longestStreak'];
        if (streak is num && streak > 0) return 'Streak $streak';
        return null;
    }
    return null;
  }

  Widget? _sparkline(PlatformProfile p, Color color) {
    final history = p.raw['ratingHistory'];
    if (history is! List || history.length < 2) return null;
    final points =
        history.length > 25 ? history.sublist(history.length - 25) : history;
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      if (point is! Map) continue;
      final rating = point['newRating'];
      if (rating is num) spots.add(FlSpot(i.toDouble(), rating.toDouble()));
    }
    if (spots.length < 2) return null;
    return SizedBox(
      height: 34,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: color,
              barWidth: 2,
              dotData: const FlDotData(show: false),
              belowBarData:
                  BarAreaData(show: true, color: color.withOpacity(0.12)),
            ),
          ],
        ),
      ),
    );
  }

  // --- weekly progress ----------------------------------------------------

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Per-date solved deltas from daily snapshots, for platforms without real
  /// submission history. A platform's first-ever snapshot contributes nothing
  /// (no baseline), so linking a new handle doesn't spike the chart.
  Map<String, int> _dailyDeltas({Set<String> excludePlatforms = const {}}) {
    final deltas = <String, int>{};
    for (final entry in _snapshots.entries) {
      if (excludePlatforms.contains(entry.key)) continue;
      final list = entry.value;
      for (var i = 1; i < list.length; i++) {
        final prev = list[i - 1]['solvedCount'];
        final cur = list[i]['solvedCount'];
        if (prev is! num || cur is! num) continue;
        final delta = (cur - prev).toInt();
        if (delta <= 0) continue;
        final date = '${list[i]['date']}';
        deltas[date] = (deltas[date] ?? 0) + delta;
      }
    }
    return deltas;
  }

  /// Problems solved per day for the current week, Monday..Sunday.
  /// Real per-solve history where available (bucketed in local time), plus
  /// snapshot deltas for the remaining platforms.
  List<int> _weekValues() {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final values = List<int>.filled(7, 0);

    for (final solves in _activity.values) {
      for (final solve in solves) {
        final local = solve.at.toLocal();
        final day = DateTime(local.year, local.month, local.day);
        final i = day.difference(monday).inDays;
        if (i >= 0 && i < 7) values[i] += 1;
      }
    }

    final deltas = _dailyDeltas(excludePlatforms: _activity.keys.toSet());
    for (var i = 0; i < 7; i++) {
      values[i] += deltas[_dateKey(monday.add(Duration(days: i)))] ?? 0;
    }
    return values;
  }

  // --- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () => _refresh(fresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) const LinearProgressIndicator(),
          _greeting(),
          const SizedBox(height: 16),
          _overviewCard(),
          const SizedBox(height: 20),
          Text(
            'Platforms',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 220,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final platform in _orderedPlatforms())
                  _platformCard(platform),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _weeklyProgress(),
          const SizedBox(height: 20),
          _activitySection(),
          _recentActivity(),
          _contestsPreview(),
          const SizedBox(height: 12),
          Text(
            'Tap a platform card to add or edit its handle.\n'
            'Pull down to refresh your latest stats.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _greeting() {
    final theme = Theme.of(context);
    final name = (_userName != null && _userName!.isNotEmpty)
        ? _userName!
        : (_handles.values.isNotEmpty ? _handles.values.first : 'Coder');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hey, $name \u{1F44B}',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          'All your coding progress at one place.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  /// Hero card: streak headline (flame in a tinted rounded square + day
  /// count + motivational subline, same logic as the home-screen widget)
  /// over a slim three-stat row (Solved / Contests / Platforms) separated by
  /// hairline dividers. Replaces the old icon-tile Overview card and the
  /// separate streak card.
  Widget _overviewCard() {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final streak = _currentStreak();
    final now = DateTime.now().toUtc();
    final activeToday = _activeDays()
        .contains(_dateKey(DateTime.utc(now.year, now.month, now.day)));
    final message = streak == 0
        ? 'Solve a problem to start a streak'
        : activeToday
            ? 'On fire - keep it up!'
            : 'Solve one today to keep it alive';
    final totalSolved =
        _profiles.values.fold<int>(0, (sum, p) => sum + (p.solvedCount ?? 0));
    var contests = 0;
    for (final p in _profiles.values) {
      final c = p.raw['contestsAttended'];
      if (c is num) contests += c.toInt();
    }
    final hairline = theme.colorScheme.onSurface.withOpacity(0.08);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '\u{1F525}',
                    style: TextStyle(fontSize: 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        streak == 1 ? '1 day streak' : '$streak day streak',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(message, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: hairline),
            const SizedBox(height: 12),
            Row(
              children: [
                _overviewStat('$totalSolved', 'Solved'),
                Container(width: 1, height: 28, color: hairline),
                _overviewStat('$contests', 'Contests'),
                Container(width: 1, height: 28, color: hairline),
                _overviewStat('${_handles.length}', 'Platforms'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewStat(String value, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _platformCard(String platform) {
    final theme = Theme.of(context);
    final color = platformColor(platform);
    final handle = _handles[platform];
    final profile = _profiles[platform];
    final error = _errors[platform];

    Widget body;
    if (handle == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline, color: color),
            const SizedBox(height: 8),
            Text('Add handle', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    } else if (error != null) {
      body = Text(
        error,
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.redAccent, fontSize: 11),
      );
    } else if (profile == null) {
      body = const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    } else {
      final stats = _subStats(platform, profile);
      final badge = _badge(platform, profile);
      final spark = _sparkline(profile, color);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _metricLabel(platform),
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
          Text(
            _metricValue(platform, profile),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final s in stats)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.key,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontSize: 10),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        s.value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const Spacer(),
          if (spark != null) spark,
          if (badge != null) ...[
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                badge,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      );
    }

    return SizedBox(
      width: 175,
      child: Card(
        margin: const EdgeInsets.only(right: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _editHandle(platform),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PlatformLogo(platform, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        platformDisplayName(platform),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Unified activity calendar merging every platform's submissions into one
  /// LeetCode-style heatmap. Hidden until at least one platform has data.
  Widget _activitySection() {
    final hasData = _heatmaps.values.any((days) => days.isNotEmpty);
    if (!hasData) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activity',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: ActivityHeatmap(byPlatform: _heatmaps),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  String _timeAgo(DateTime at) {
    final diff = DateTime.now().difference(at.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    return '${diff.inDays} days ago';
  }

  /// Latest accepted solves across every platform, newest first - a merged
  /// feed built from the same `/api/activity` data as Weekly Progress.
  Widget _recentActivity() {
    final theme = Theme.of(context);
    final entries = <MapEntry<String, Solve>>[];
    _activity.forEach((platform, solves) {
      for (final solve in solves) {
        entries.add(MapEntry(platform, solve));
      }
    });
    if (entries.isEmpty) return const SizedBox.shrink();
    entries.sort((a, b) => b.value.at.compareTo(a.value.at));
    final recent = entries.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Solves',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Card(
          child: Column(
            children: [
              for (final entry in recent)
                ListTile(
                  dense: true,
                  leading:
                      PlatformLogo(entry.key, size: 22, backdrop: true),
                  title: Text(
                    entry.value.name ?? entry.value.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '${platformDisplayName(entry.key)}'
                    ' \u00B7 ${_timeAgo(entry.value.at)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: const Icon(Icons.check_circle_outline,
                      size: 16, color: Color(0xFF4CAF50)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _weeklyProgress() {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    final values = _weekValues();
    final total = values.fold<int>(0, (sum, v) => sum + v);
    final progress = _weeklyGoal > 0 ? total / _weeklyGoal : 0.0;
    final pct = (progress * 100).round();
    final message = progress >= 1
        ? 'Goal smashed! \u{1F389}'
        : progress >= 0.7
            ? 'Great pace! \u{1F525}'
            : progress > 0
                ? 'Keep going! \u{1F4AA}'
                : 'Let\'s get solving!';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Weekly Progress',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Set weekly goal',
              onPressed: _editGoal,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 130,
                        child: _weeklyBars(values, color),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      children: [
                        SizedBox(
                          width: 62,
                          height: 62,
                          child: CircularProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            strokeWidth: 7,
                            strokeCap: StrokeCap.round,
                            backgroundColor: color.withOpacity(0.15),
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '$total',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextSpan(
                                text: ' / $_weeklyGoal',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text('This Week', style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          '$pct% of goal',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(message, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
                if (total == 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Codeforces, LeetCode, CodeChef and AtCoder count from '
                    'your real submission history. GFG uses daily snapshots, '
                    'so it starts counting a day after linking.',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _weeklyBars(List<int> values, Color color) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final maxValue = values.fold<int>(0, (m, v) => v > m ? v : m);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: (maxValue == 0 ? 1 : maxValue) * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  labels[value.toInt()],
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < 7; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].toDouble(),
                  width: 14,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(4)),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [color.withOpacity(0.55), color],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _contestsPreview() {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final upcoming = _contests.where((c) => c.start.isAfter(now)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    if (upcoming.isEmpty) return const SizedBox.shrink();
    final next = upcoming.take(3).toList();
    final monthFmt = DateFormat('MMM');
    final dayFmt = DateFormat('d');
    final timeFmt = DateFormat('EEE, h:mm a');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Upcoming Contests',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: widget.onOpenContests,
              child: const Text('View all'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Card(
          child: Column(
            children: [
              for (final c in next)
                ListTile(
                  onTap: widget.onOpenContests,
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  leading: Container(
                    width: 48,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              monthFmt
                                  .format(c.start.toLocal())
                                  .toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              dayFmt.format(c.start.toLocal()),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    '${_countdownText(c.start)}  |  '
                    '${timeFmt.format(c.start.toLocal())}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _countdownText(DateTime start) {
    final diff = start.difference(DateTime.now());
    if (diff.inDays >= 1) {
      return 'Starts in ${diff.inDays} day${diff.inDays == 1 ? '' : 's'}';
    }
    if (diff.inHours >= 1) {
      return 'Starts in ${diff.inHours}h ${diff.inMinutes % 60}m';
    }
    return 'Starts in ${diff.inMinutes}m';
  }
}
