import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/contest.dart';
import '../models/profile.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../storage/app_store.dart';

const kPlatforms = ['codeforces', 'leetcode', 'codechef', 'atcoder', 'gfg'];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Favicon CDN: returns each platform's real logo as a small PNG.
  static const _faviconBase =
      'https://www.google.com/s2/favicons?sz=64&domain=';

  final _api = ApiClient();
  final _store = AppStore();

  Map<String, String> _handles = {};
  final Map<String, PlatformProfile> _profiles = {};
  final Map<String, String> _errors = {};
  List<Contest> _contests = [];
  String? _userName;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _handles = await _store.loadHandles();
    _userName = await AuthService.instance.name();
    if (mounted) setState(() {});
    await _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    _userName = await AuthService.instance.name();
    await Future.wait([
      ..._handles.entries.map((entry) async {
        try {
          _profiles[entry.key] =
              await _api.fetchProfile(entry.key, entry.value);
          _errors.remove(entry.key);
        } catch (err) {
          _errors[entry.key] = 'Failed to load: $err';
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
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _editHandle(String platform) async {
    final controller = TextEditingController(text: _handles[platform] ?? '');
    final handle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_displayName(platform)} handle'),
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
      } else {
        _handles[platform] = handle;
      }
    });
    await _store.saveHandles(_handles);
    await _refresh();
  }

  // --- platform helpers --------------------------------------------------

  String _displayName(String platform) {
    switch (platform) {
      case 'gfg':
        return 'GeeksforGeeks';
      case 'atcoder':
        return 'AtCoder';
      case 'leetcode':
        return 'LeetCode';
      case 'codechef':
        return 'CodeChef';
      case 'codeforces':
        return 'Codeforces';
      default:
        return platform;
    }
  }

  String _domain(String platform) {
    switch (platform) {
      case 'codeforces':
        return 'codeforces.com';
      case 'leetcode':
        return 'leetcode.com';
      case 'codechef':
        return 'codechef.com';
      case 'atcoder':
        return 'atcoder.jp';
      case 'gfg':
        return 'geeksforgeeks.org';
      default:
        return '$platform.com';
    }
  }

  Color _color(String platform) {
    switch (platform) {
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

  Widget _logo(String platform, {double size = 24}) {
    final color = _color(platform);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        _faviconBase + _domain(platform),
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => CircleAvatar(
          radius: size / 2,
          backgroundColor: color.withOpacity(0.18),
          foregroundColor: color,
          child: Text(
            _displayName(platform)[0],
            style: TextStyle(
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  String _metricLabel(String platform) =>
      platform == 'gfg' ? 'Coding Score' : 'Rating';

  String _metricValue(String platform, PlatformProfile profile) {
    if (platform == 'gfg') {
      return profile.raw['codingScore']?.toString() ?? '-';
    }
    return profile.rating?.toString() ?? '-';
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
          MapEntry(
            'Global Rank',
            raw['globalRanking'] != null ? '#${raw['globalRanking']}' : '-',
          ),
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

  // --- UI -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
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
                for (final platform in kPlatforms) _platformCard(platform),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _contestsPreview(),
          const SizedBox(height: 12),
          Text(
            'Tap a platform card to add or edit its handle.\n'
            'Pull down to refresh - stats are cached for 6 hours.',
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

  Widget _overviewCard() {
    final theme = Theme.of(context);
    final totalSolved =
        _profiles.values.fold<int>(0, (sum, p) => sum + (p.solvedCount ?? 0));
    var contests = 0;
    for (final p in _profiles.values) {
      final c = p.raw['contestsAttended'];
      if (c is num) contests += c.toInt();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 10),
                Icon(Icons.bar_chart_rounded,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text(
                  'Overview',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _overviewTile(
                  Icons.task_alt,
                  const Color(0xFF9C7BFF),
                  '$totalSolved',
                  'Problems Solved',
                ),
                _overviewTile(
                  Icons.calendar_month_outlined,
                  const Color(0xFF4CAF50),
                  '$contests',
                  'Contests Participated',
                ),
                _overviewTile(
                  Icons.link,
                  const Color(0xFF5C9DFF),
                  '${_handles.length}',
                  'Platforms Linked',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _overviewTile(
      IconData icon, Color color, String value, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withOpacity(0.15),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _platformCard(String platform) {
    final theme = Theme.of(context);
    final color = _color(platform);
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
                    _logo(platform),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _displayName(platform),
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
        Text(
          'Upcoming Contests',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Card(
          child: Column(
            children: [
              for (final c in next)
                ListTile(
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
