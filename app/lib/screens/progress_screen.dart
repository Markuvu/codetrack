import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/profile.dart';
import '../services/api_client.dart';
import '../storage/app_store.dart';
import '../widgets/platform_logo.dart';

const _kPlatformOrder = ['codeforces', 'leetcode', 'codechef', 'atcoder', 'gfg'];

const _kShortNames = {
  'codeforces': 'CF',
  'leetcode': 'LC',
  'codechef': 'CC',
  'atcoder': 'AC',
  'gfg': 'GFG',
};

enum _ChartKind { rating, solved }

class _Series {
  _Series({required this.spots, required this.dates, this.names});

  final List<FlSpot> spots;
  final List<DateTime?> dates;
  final List<String?>? names;
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _api = ApiClient();
  final _store = AppStore();

  Map<String, String> _handles = {};
  String? _platform;
  PlatformProfile? _profile;
  List<Map<String, dynamic>> _snapshots = [];
  String? _error;
  bool _loading = false;
  _ChartKind? _kind; // null = auto (rating when available)

  @override
  void initState() {
    super.initState();
    _init();
  }

  /// Linked platforms in canonical order (plus any unknown extras).
  List<String> get _linked {
    final linked = [
      for (final p in _kPlatformOrder)
        if (_handles.containsKey(p)) p,
    ];
    for (final p in _handles.keys) {
      if (!linked.contains(p)) linked.add(p);
    }
    return linked;
  }

  Future<void> _init() async {
    _handles = await _store.loadHandles();
    _platform = _linked.isNotEmpty ? _linked.first : null;
    if (mounted) setState(() {});
    await _loadData();
  }

  Future<void> _selectPlatform(String platform) async {
    if (platform == _platform) return;
    setState(() {
      _platform = platform;
      _profile = null;
      _snapshots = [];
      _error = null;
      _kind = null;
    });
    await _loadData();
  }

  Future<void> _loadData({bool fresh = false}) async {
    final platform = _platform;
    if (platform == null) return;
    final handle = _handles[platform]!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _api.fetchProfile(platform, handle, fresh: fresh),
        _api.fetchSnapshots(platform, handle),
      ]);
      _profile = results[0] as PlatformProfile;
      _snapshots = results[1] as List<Map<String, dynamic>>;
    } catch (err) {
      _error = 'Failed to load progress: $err';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Consecutive trailing days where the solved count went up.
  int get _streak {
    var streak = 0;
    for (var i = _snapshots.length - 1; i > 0; i--) {
      final curr = (_snapshots[i]['solvedCount'] as num?)?.toInt();
      final prev = (_snapshots[i - 1]['solvedCount'] as num?)?.toInt();
      if (curr != null && prev != null && curr > prev) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  // --- chart data ----------------------------------------------------------

  _Series? _ratingSeries() {
    final history = (_profile?.raw['ratingHistory'] as List?) ?? [];
    if (history.length < 2) return null;
    final spots = <FlSpot>[];
    final dates = <DateTime?>[];
    final names = <String?>[];
    for (final e in history) {
      if (e is! Map) continue;
      final r = (e['newRating'] as num?)?.toDouble();
      if (r == null) continue;
      spots.add(FlSpot(spots.length.toDouble(), r));
      final at =
          ((e['at'] ?? e['ratingUpdateTimeSeconds']) as num?)?.toInt();
      dates.add(at == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(at * 1000));
      names.add((e['contest'] ?? e['contestName'])?.toString());
    }
    if (spots.length < 2) return null;
    return _Series(spots: spots, dates: dates, names: names);
  }

  _Series? _solvedSeries() {
    final withSolved = _snapshots
        .where((s) => s['solvedCount'] != null)
        .toList(growable: false);
    if (withSolved.length < 2) return null;
    final spots = <FlSpot>[];
    final dates = <DateTime?>[];
    for (var i = 0; i < withSolved.length; i++) {
      spots.add(FlSpot(
        i.toDouble(),
        ((withSolved[i]['solvedCount'] as num?) ?? 0).toDouble(),
      ));
      dates.add(DateTime.tryParse('${withSolved[i]['date']}'));
    }
    return _Series(spots: spots, dates: dates);
  }

  double _niceInterval(double range) {
    if (range <= 0) return 1;
    final raw = range / 4;
    final mag =
        math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final norm = raw / mag;
    final mult = norm >= 5 ? 5.0 : (norm >= 2 ? 2.0 : 1.0);
    return mult * mag;
  }

  // --- platform bar (same segmented pattern as Contests / Friends) ---------

  Widget _platformTile(String p) {
    final theme = Theme.of(context);
    final selected = _platform == p;
    final color = platformColor(p);
    return Expanded(
      child: Tooltip(
        message: platformDisplayName(p),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _selectPlatform(p),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 7),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? color : Colors.transparent,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 24,
                  child: Center(
                    child: PlatformLogo(p, size: 22, backdrop: true),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _kShortNames[p] ?? p.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? color
                        : theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- cards ----------------------------------------------------------------

  Widget _statsCard() {
    final theme = Theme.of(context);
    final color = platformColor(_platform ?? '');
    final isGfg = _platform == 'gfg';
    final headline = isGfg
        ? _profile?.raw['codingScore']?.toString()
        : _profile?.rating?.toString();

    Widget tile(IconData icon, String value, String label) => Expanded(
          child: Column(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Row(
          children: [
            tile(Icons.leaderboard_outlined, headline ?? '-',
                isGfg ? 'Coding score' : 'Rating'),
            tile(Icons.check_circle_outline,
                _profile?.solvedCount?.toString() ?? '-', 'Solved'),
            tile(Icons.local_fire_department_outlined, '$_streak',
                'Day streak'),
            tile(Icons.calendar_month_outlined, '${_snapshots.length}',
                'Days tracked'),
          ],
        ),
      ),
    );
  }

  Widget _chartCard(_Series? rating, _Series? solved) {
    final theme = Theme.of(context);
    final color = platformColor(_platform ?? '');

    final kinds = <_ChartKind>[
      if (rating != null) _ChartKind.rating,
      if (solved != null) _ChartKind.solved,
    ];

    if (kinds.isEmpty) {
      return Card(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.show_chart,
                  size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              const Text(
                'Not enough data to chart yet.\n'
                'Snapshots are recorded each time a profile is freshly '
                'fetched - check back after a few days!',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final kind =
        (_kind != null && kinds.contains(_kind)) ? _kind! : kinds.first;
    final series = kind == _ChartKind.rating ? rating! : solved!;

    // Fit the y-axis to the data (with padding) - no dead space below.
    final values = [for (final s in series.spots) s.y];
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    var pad = (maxV - minV) * 0.15;
    if (pad == 0) pad = math.max(10, maxV * 0.1);
    final minY = (minV - pad).floorToDouble();
    final maxY = (maxV + pad).ceilToDouble();
    final yInterval = math.max(1.0, _niceInterval(maxY - minY));

    final delta = (series.spots.last.y - series.spots.first.y).round();
    final deltaColor = delta >= 0 ? Colors.greenAccent : Colors.redAccent;

    DateTime? firstDate;
    DateTime? lastDate;
    for (final d in series.dates) {
      if (d == null) continue;
      firstDate ??= d;
      lastDate = d;
    }
    final xFormat = (firstDate != null &&
            lastDate != null &&
            firstDate.year != lastDate.year)
        ? DateFormat("MMM ''yy")
        : DateFormat('MMM d');
    final xInterval =
        math.max(1, ((series.spots.length - 1) / 3).ceil()).toDouble();

    String tooltipText(int i, double y) {
      final d =
          (i >= 0 && i < series.dates.length) ? series.dates[i] : null;
      final dateStr =
          d == null ? '' : DateFormat('MMM d, yyyy').format(d);
      if (kind == _ChartKind.rating) {
        var name = series.names != null && i < series.names!.length
            ? (series.names![i] ?? '')
            : '';
        if (name.length > 34) name = '${name.substring(0, 33)}\u2026';
        return [
          '${y.round()}${dateStr.isEmpty ? '' : ' \u00B7 $dateStr'}',
          if (name.isNotEmpty) name,
        ].join('\n');
      }
      return '${y.round()} solved${dateStr.isEmpty ? '' : '\n$dateStr'}';
    }

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        kind == _ChartKind.rating
                            ? 'Rating history'
                            : 'Problems solved',
                        style:
                            const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        kind == _ChartKind.rating
                            ? '${series.spots.length} contests'
                            : '${series.spots.length} days tracked',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: deltaColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    delta >= 0 ? '+$delta' : '$delta',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: deltaColor,
                    ),
                  ),
                ),
              ],
            ),
            if (kinds.length > 1) ...[
              const SizedBox(height: 8),
              SegmentedButton<_ChartKind>(
                segments: const [
                  ButtonSegment(
                    value: _ChartKind.rating,
                    label: Text('Rating', style: TextStyle(fontSize: 12)),
                  ),
                  ButtonSegment(
                    value: _ChartKind.solved,
                    label: Text('Solved', style: TextStyle(fontSize: 12)),
                  ),
                ],
                selected: {kind},
                onSelectionChanged: (s) =>
                    setState(() => _kind = s.first),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: theme.dividerColor.withOpacity(0.15),
                      strokeWidth: 1,
                      dashArray: const [4, 4],
                    ),
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: yInterval,
                        getTitlesWidget: (value, meta) => Text(
                          '${value.toInt()}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 9),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        interval: xInterval,
                        getTitlesWidget: (value, meta) {
                          final i = value.toInt();
                          if (i < 0 ||
                              i >= series.dates.length ||
                              value != i.toDouble()) {
                            return const SizedBox.shrink();
                          }
                          final d = series.dates[i];
                          if (d == null) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              xFormat.format(d),
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      maxContentWidth: 240,
                      getTooltipItems: (touchedSpots) => [
                        for (final s in touchedSpots)
                          LineTooltipItem(
                            tooltipText(s.x.toInt(), s.y),
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: series.spots,
                      isCurved: true,
                      curveSmoothness: 0.15,
                      preventCurveOverShooting: true,
                      barWidth: 2.5,
                      color: color,
                      dotData: FlDotData(
                        show: series.spots.length <= 30,
                        getDotPainter: (spot, pct, bar, i) =>
                            FlDotCirclePainter(
                          radius: 2.5,
                          color: color,
                          strokeWidth: 0,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withOpacity(0.25),
                            color.withOpacity(0.0),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_handles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.show_chart,
                  size: 44, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Link a platform handle on the Dashboard tab\n'
                'to see your progress charts.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    final linked = _linked;
    final rating = _ratingSeries();
    final solved = _solvedSeries();

    return RefreshIndicator(
      onRefresh: () => _loadData(fresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withOpacity(0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  for (var i = 0; i < linked.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    _platformTile(linked[i]),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${platformDisplayName(_platform ?? '')} \u00B7 '
                    '@${_handles[_platform] ?? ''} \u00B7 '
                    'pull down for fresh data',
                    style:
                        theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh (bypasses cache)',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _loadData(fresh: true),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          if (_profile != null) _statsCard(),
          if (_profile != null) _chartCard(rating, solved),
        ],
      ),
    );
  }
}
