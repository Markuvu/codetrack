import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../storage/app_store.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _api = ApiClient();
  final _store = AppStore();

  String? _ownHandle;
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
    final handles = await _store.loadHandles();
    _ownHandle = handles['codeforces'];
    _friends = await _store.loadFriends();
    if (mounted) setState(() {});
    await _refresh();
  }

  List<String> get _allHandles => {
        if (_ownHandle != null) _ownHandle!,
        ..._friends,
      }.toList();

  Future<void> _refresh() async {
    final handles = _allHandles;
    if (handles.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rows = await _api.fetchLeaderboard('codeforces', handles);
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
        title: const Text('Add friend (Codeforces handle)'),
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
    await _store.saveFriends(_friends);
    await _refresh();
  }

  Future<void> _removeFriend(String handle) async {
    setState(() => _friends.remove(handle));
    await _store.saveFriends(_friends);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addFriend,
        child: const Icon(Icons.person_add_alt),
      ),
      body: _allHandles.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Add your Codeforces handle in the Profiles tab,\n'
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
                      subtitle: Text(
                        _rows[i]['error'] != null
                            ? 'Error: ${_rows[i]['error']}'
                            : 'Rating: ${_rows[i]['rating'] ?? '-'}'
                                '  |  Solved: ${_rows[i]['solvedCount'] ?? '-'}',
                      ),
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
    );
  }
}
