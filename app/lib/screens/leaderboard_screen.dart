import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../storage/app_store.dart';
import '../widgets/platform_logo.dart';

const kLeaderboardPlatforms = ['codeforces', 'leetcode', 'codechef', 'atcoder', 'gfg'];

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _api = ApiClient();
  final _store = AppStore();

  String _platform = 'codeforces';
  Map<String, String> _handles = {};
  List<String> _friends = [];
  List<Map<String, dynamic>> _rows = [];
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _handles = await _store.loadHandles();
    _friends = await _store.loadFriends(_platform);
    if (mounted) setState(() {});
    await _refresh();
  }

  String? get _ownHandle => _handles[_platform];

  List<String> get _allHandles => {
        if (_ownHandle != null) _ownHandle!,
        ..._friends,
      }.toList();

  Future<void> _selectPlatform(String platform) async {
    if (platform == _platform) return;
    _platform = platform;
    _rows = [];
    _error = null;
    _friends = await _store.loadFriends(platform);
    if (mounted) setState(() {});
    await _refresh();
  }

  Future<void> _refresh() async {
    final handles = _allHandles;
    if (handles.isEmpty) {
      if (mounted) setState(() => _rows = []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rows = await _api.fetchLeaderboard(_platform, handles);
    } catch (err) {
      _error = 'Failed to load leaderboard: $err';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addFriend() async {
    final controller = TextEditingController();
    final handle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add friend (${platformDisplayName(_platform)} handle)'),
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (handle == null || handle.isEmpty || _friends.contains(handle)) return;
    setState(() => _friends.add(handle));
    await _store.saveFriends(_friends, _platform);
    await _refresh();
  }

  Future<void> _removeFriend(String handle) async {
    setState(() => _friends.remove(handle));
    await _store.saveFriends(_friends, _platform);
    await _refresh();
  }

  String _medal(int index) {
    switch (index) {
      case 0:
        return '\u{1F947}'; // gold
      case 1:
        return '\u{1F948}'; // silver
      case 2:
        return '\u{1F949}'; // bronze
      default:
        return '${index + 1}.';
    }
  }

  String _rowSubtitle(Map<String, dynamic> row) {
    if (row['error'] != null) return 'Error: ${row['error']}';
    final rating = row['rating'];
    final solved = row['solvedCount'] ?? '-';
    // GFG has no contest rating - only show solved there.
    if (_platform == 'gfg' || rating == null) return 'Solved: $solved';
    return 'Rating: $rating  |  Solved: $solved';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addFriend,
        child: const Icon(Icons.person_add_alt),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              children: [
                for (final p in kLeaderboardPlatforms) ...[
                  ChoiceChip(
                    avatar: PlatformLogo(p, size: 18),
                    label: Text(platformDisplayName(p)),
                    selected: _platform == p,
                    onSelected: (_) => _selectPlatform(p),
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          Expanded(
            child: _allHandles.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Add your ${platformDisplayName(_platform)} handle in the Dashboard tab,\n'
                        'then add friends with the + button to compare.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        if (_loading) const LinearProgressIndicator(),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        for (var i = 0; i < _rows.length; i++)
                          ListTile(
                            leading: Text(
                              _medal(i),
                              style: const TextStyle(fontSize: 20),
                            ),
                            title: Text(
                              '${_rows[i]['handle']}'
                              '${_rows[i]['handle'] == _ownHandle ? '  (you)' : ''}',
                            ),
                            subtitle: Text(_rowSubtitle(_rows[i])),
                            onLongPress: _rows[i]['handle'] == _ownHandle
                                ? null
                                : () => _removeFriend('${_rows[i]['handle']}'),
                          ),
                        if (_rows.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Long-press a friend to remove them.',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
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
