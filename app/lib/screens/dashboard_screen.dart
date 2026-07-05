import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/api_client.dart';
import '../storage/app_store.dart';

const kPlatforms = ['codeforces', 'leetcode', 'codechef', 'atcoder', 'gfg'];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _api = ApiClient();
  final _store = AppStore();

  Map<String, String> _handles = {};
  final Map<String, PlatformProfile> _profiles = {};
  final Map<String, String> _errors = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _handles = await _store.loadHandles();
    if (mounted) setState(() {});
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_handles.isEmpty) return;
    setState(() => _loading = true);
    await Future.wait(_handles.entries.map((entry) async {
      try {
        _profiles[entry.key] = await _api.fetchProfile(entry.key, entry.value);
        _errors.remove(entry.key);
      } catch (err) {
        _errors[entry.key] = 'Failed to load: $err';
      }
    }));
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

  // Some platforms have no contest rating; show their preferred metric name.
  String _metricLabel(String platform) {
    switch (platform) {
      case 'gfg':
        return 'coding score';
      default:
        return 'rating';
    }
  }

  String _metricValue(String platform, PlatformProfile profile) {
    switch (platform) {
      case 'gfg':
        return profile.raw['codingScore']?.toString() ?? '-';
      default:
        return profile.rating?.toString() ?? '-';
    }
  }

  /// Extra per-platform stats surfaced from the backend response.
  List<String> _extraStats(String platform, PlatformProfile profile) {
    final raw = profile.raw;
    final stats = <String>[];
    switch (platform) {
      case 'codeforces':
        if (raw['rank'] != null) stats.add('${raw['rank']}');
        if (raw['maxRating'] != null) stats.add('max ${raw['maxRating']}');
        if (raw['contestsAttended'] != null) {
          stats.add('${raw['contestsAttended']} contests');
        }
        break;
      case 'leetcode':
        final byDiff = raw['solvedByDifficulty'];
        if (byDiff is Map) {
          stats.add(
              'E ${byDiff['easy'] ?? 0} | M ${byDiff['medium'] ?? 0} | H ${byDiff['hard'] ?? 0}');
        }
        if (raw['globalRanking'] != null) {
          stats.add('global #${raw['globalRanking']}');
        }
        if (raw['topPercentage'] != null) {
          stats.add('top ${raw['topPercentage']}%');
        }
        break;
      case 'codechef':
        if (raw['stars'] != null) stats.add('${raw['stars']}');
        if (raw['maxRating'] != null) stats.add('max ${raw['maxRating']}');
        break;
      case 'atcoder':
        if (raw['maxRating'] != null) stats.add('max ${raw['maxRating']}');
        if (raw['contestsAttended'] != null) {
          stats.add('${raw['contestsAttended']} contests');
        }
        break;
      case 'gfg':
        if (raw['instituteRank'] != null) {
          stats.add('institute #${raw['instituteRank']}');
        }
        final streak = raw['longestStreak'];
        if (streak != null && streak != 0) stats.add('streak $streak');
        break;
    }
    return stats;
  }

  @override
  Widget build(BuildContext context) {
    final totalSolved = _profiles.values
        .fold<int>(0, (sum, p) => sum + (p.solvedCount ?? 0));
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (_loading) const LinearProgressIndicator(),
          if (_handles.isNotEmpty) _summaryCard(totalSolved),
          for (final platform in kPlatforms) _platformCard(platform),
          const SizedBox(height: 8),
          Text(
            'Tap a card to set its handle. Pull down to refresh.\n'
            'Stats are cached on the backend for 6 hours.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(int totalSolved) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: theme.colorScheme.primaryContainer.withOpacity(0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total problems solved',
                      style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    '$totalSolved',
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Text(
              '${_handles.length} platform${_handles.length == 1 ? '' : 's'} linked',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _platformCard(String platform) {
    final handle = _handles[platform];
    final profile = _profiles[platform];
    final error = _errors[platform];
    final color = _color(platform);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editHandle(platform),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withOpacity(0.18),
                foregroundColor: color,
                child: Text(
                  _displayName(platform)[0],
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _displayName(platform),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (handle != null)
                          Text('@$handle', style: theme.textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (handle == null)
                      Text('Tap to add your handle',
                          style: theme.textTheme.bodySmall)
                    else if (error != null)
                      Text(
                        error,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12),
                      )
                    else if (profile == null)
                      Text('Loading...', style: theme.textTheme.bodySmall)
                    else ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _metricValue(platform, profile),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              _metricLabel(platform),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'solved ${profile.solvedCount ?? '-'}',
                            style: theme.textTheme.titleSmall,
                          ),
                        ],
                      ),
                      if (_extraStats(platform, profile).isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final stat in _extraStats(platform, profile))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: theme
                                      .colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  stat,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
