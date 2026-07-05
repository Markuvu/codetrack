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

  /// Friend count per platform, shown in the segmented bar tiles.
  final Map<String, int> _friendCounts = {};

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
    for (final p in kLeaderboardPlatforms) {
      _friendCounts[p] = (await _store.loadFriends(p)).length;
    }
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
    if (handle == null ||
        handle.isEmpty ||
        handle == _ownHandle ||
        _friends.contains(handle)) {
      return;
    }
    setState(() {
      _friends.add(handle);
      _friendCounts[_platform] = _friends.length;
    });
    await _store.saveFriends(_friends, _platform);
    await _refresh();
  }

  /// Removes locally (no refetch needed) and offers an Undo snackbar.
  Future<void> _removeFriend(String handle) async {
    setState(() {
      _friends.remove(handle);
      _friendCounts[_platform] = _friends.length;
      _rows.removeWhere((r) => '${r['handle']}' == handle);
    });
    await _store.saveFriends(_friends, _platform);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Removed $handle'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            if (_friends.contains(handle)) return;
            setState(() {
              _friends.add(handle);
              _friendCounts[_platform] = _friends.length;
            });
            await _store.saveFriends(_friends, _platform);
            await _refresh();
          },
        ),
      ),
    );
  }

  // --- platform bar (same segmented pattern as the Contests filter) -------

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
                  '${_friendCounts[p] ?? 0}',
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

  Widget _platformBar() {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            for (var i = 0; i < kLeaderboardPlatforms.length; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              _platformTile(kLeaderboardPlatforms[i]),
            ],
          ],
        ),
      ),
    );
  }

  // --- leaderboard rows ----------------------------------------------------

  Widget _rankBadge(int index) {
    final theme = Theme.of(context);
    const medalTints = [Color(0xFFFFC107), Color(0xFFB0BEC5), Color(0xFFBF8970)];
    const medals = ['\u{1F947}', '\u{1F948}', '\u{1F949}'];
    if (index < 3) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: medalTints[index].withOpacity(0.18),
        child: Text(medals[index], style: const TextStyle(fontSize: 15)),
      );
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        '${index + 1}',
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _row(int index, Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final color = platformColor(_platform);
    final handle = '${row['handle']}';
    final isYou = handle == _ownHandle;
    final error = row['error'];
    final rating = row['rating'];
    final solved = row['solvedCount'];
    final showRating = _platform != 'gfg' && rating != null;

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: isYou ? color.withOpacity(0.10) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isYou
            ? BorderSide(color: color.withOpacity(0.5))
            : BorderSide.none,
      ),
      child: ListTile(
        leading: _rankBadge(index),
        title: Row(
          children: [
            Flexible(
              child: Text(
                handle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (isYou) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'You',
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: error != null
            ? Text(
                'Couldn\'t load: $error',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 11),
              )
            : null,
        trailing: error != null
            ? const Icon(Icons.error_outline, color: Colors.redAccent)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    showRating ? '$rating' : '${solved ?? '-'}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    showRating ? 'Solved ${solved ?? '-'}' : 'solved',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontSize: 11),
                  ),
                ],
              ),
        onLongPress: isYou ? null : () => _removeFriend(handle),
      ),
    );

    if (isYou) return card;
    // Swipe left to remove - discoverable, standard mobile pattern.
    return Dismissible(
      key: ValueKey('$_platform:$handle'),
      direction: DismissDirection.endToStart,
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: Colors.redAccent.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.person_remove_alt_1, color: Colors.white),
      ),
      onDismissed: (_) => _removeFriend(handle),
      child: card,
    );
  }

  Widget _emptyState() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_add_outlined,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              _ownHandle == null
                  ? 'Link your ${platformDisplayName(_platform)} handle on the '
                      'Dashboard to appear on the board, or just add friends '
                      'to compare.'
                  : 'No friends on ${platformDisplayName(_platform)} yet - '
                      'add handles to compare.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _addFriend,
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add friend'),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addFriend,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add friend'),
      ),
      body: Column(
        children: [
          _platformBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${platformDisplayName(_platform)} \u00B7 '
                '${_friends.length} friend${_friends.length == 1 ? '' : 's'} \u00B7 '
                'ranked by ${_platform == 'gfg' ? 'problems solved' : 'rating'}',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
            ),
          ),
          Expanded(
            child: _allHandles.isEmpty
                ? _emptyState()
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(top: 4, bottom: 88),
                      children: [
                        if (_loading) const LinearProgressIndicator(),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _error!,
                              style:
                                  const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        for (var i = 0; i < _rows.length; i++)
                          _row(i, _rows[i]),
                        if (_rows.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Swipe a friend left (or long-press) to remove them.',
                              style: theme.textTheme.bodySmall,
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
