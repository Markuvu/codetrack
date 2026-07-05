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
        title: Text('$platform handle'),
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          if (_loading) const LinearProgressIndicator(),
          for (final platform in kPlatforms) _platformCard(platform),
          const SizedBox(height: 8),
          Text(
            'Pull down to refresh. Stats are cached on the backend for 6 hours.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _platformCard(String platform) {
    final handle = _handles[platform];
    final profile = _profiles[platform];
    final error = _errors[platform];

    final String subtitle;
    if (handle == null) {
      subtitle = 'Tap to add your handle';
    } else if (error != null) {
      subtitle = error;
    } else if (profile == null) {
      subtitle = '@$handle - loading...';
    } else {
      final metric = _metricValue(platform, profile);
      final solved = profile.solvedCount?.toString() ?? '-';
      subtitle = '@$handle  |  ${_metricLabel(platform)} $metric  |  solved $solved';
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(_displayName(platform)),
        subtitle: Text(
          subtitle,
          style: error != null ? const TextStyle(color: Colors.redAccent) : null,
        ),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () => _editHandle(platform),
      ),
    );
  }
}
