import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/api_client.dart';
import '../storage/app_store.dart';

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

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _handles = await _store.loadHandles();
    _platform = _handles.keys.isNotEmpty ? _handles.keys.first : null;
    if (mounted) setState(() {});
    await _loadData();
  }

  Future<void> _loadData() async {
    final platform = _platform;
    if (platform == null) return;
    final handle = _handles[platform]!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait<dynamic>([
        _api.fetchProfile(platform, handle),
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

  @override
  Widget build(BuildContext context) {
    if (_handles.isEmpty) {
      return const Center(
        child: Text('Add a handle in the Profiles tab first.'),
      );
    }

    final ratingHistory = (_profile?.raw['ratingHistory'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              DropdownButton<String>(
                value: _platform,
                items: [
                  for (final p in _handles.keys)
                    DropdownMenuItem(value: p, child: Text(p)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _platform = value);
                  _loadData();
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadData,
              ),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
          ),
        if (_profile != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _statChip('Rating', _profile!.rating?.toString() ?? '-'),
                _statChip('Solved', _profile!.solvedCount?.toString() ?? '-'),
                _statChip('Streak', '$_streak day(s)'),
                _statChip('Days tracked', '${_snapshots.length}'),
              ],
            ),
          ),
        Expanded(child: _buildChart(ratingHistory)),
      ],
    );
  }

  Widget _statChip(String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildChart(List ratingHistory) {
    List<FlSpot> spots;
    String label;

    if (ratingHistory.length >= 2) {
      label = 'Rating history (${ratingHistory.length} contests)';
      spots = [
        for (var i = 0; i < ratingHistory.length; i++)
          FlSpot(
            i.toDouble(),
            ((ratingHistory[i]['newRating'] as num?) ?? 0).toDouble(),
          ),
      ];
    } else {
      final withSolved = _snapshots
          .where((s) => s['solvedCount'] != null)
          .toList(growable: false);
      label = 'Solved problems over time';
      spots = [
        for (var i = 0; i < withSolved.length; i++)
          FlSpot(
            i.toDouble(),
            ((withSolved[i]['solvedCount'] as num?) ?? 0).toDouble(),
          ),
      ];
    }

    if (spots.length < 2) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Not enough data to chart yet.\n'
            'Snapshots are recorded each time a profile is freshly fetched - '
            'check back after a few days!',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                titlesData: const FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: false,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
