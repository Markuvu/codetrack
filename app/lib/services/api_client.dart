import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contest.dart';
import '../models/profile.dart';
import 'auth_service.dart';

/// A single accepted solve from `/api/activity` - powers the weekly-progress
/// chart and the Recent Solves feed.
class Solve {
  Solve({required this.id, this.name, this.url, required this.at});

  final String id;

  /// Problem title when the platform provides one (AtCoder only has ids).
  final String? name;

  /// Link to the problem page, when available.
  final String? url;

  /// Accepted time (UTC instant).
  final DateTime at;
}

/// One topic tag with its solved count, from `/api/topics`.
class TopicCount {
  TopicCount({required this.tag, required this.solved});

  final String tag;
  final int solved;
}

/// Topic categorization of solved problems (like leetcode.com/progress).
class TopicStats {
  TopicStats({required this.topics, this.difficulty});

  /// Tags sorted by solved count (descending) by the backend. Codeforces
  /// counts a problem once per tag, so topic totals intentionally overlap.
  final List<TopicCount> topics;

  /// Easy/Medium/Hard solved split - LeetCode only (keys: easy, medium,
  /// hard, all). Null for platforms without difficulty tiers.
  final Map<String, int>? difficulty;
}

class ApiClient {
  static const _urlKey = 'backend_url';

  /// Android emulator loopback to the host machine.
  static const defaultBaseUrl = 'http://10.0.2.2:3000';

  Future<String> baseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_urlKey) ?? defaultBaseUrl;
  }

  Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, url);
  }

  Future<Map<String, dynamic>> _getJson(String path,
      {Duration timeout = const Duration(seconds: 30)}) async {
    final base = await baseUrl();
    final res = await http.get(Uri.parse('$base$path')).timeout(timeout);
    if (res.statusCode != 200) {
      throw Exception('Request failed (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Authenticated request against the signed-in user's `/api/me` routes.
  /// The access token is refreshed transparently by [AuthService].
  Future<Map<String, dynamic>> _authedJson(String method, String path,
      {Map<String, dynamic>? body,
      Duration timeout = const Duration(seconds: 30)}) async {
    final base = await baseUrl();
    final token = await AuthService.instance.accessToken();
    final request = http.Request(method, Uri.parse('$base$path'))
      ..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final client = http.Client();
    late http.Response res;
    try {
      res = await http.Response.fromStream(
          await client.send(request).timeout(timeout));
    } finally {
      client.close();
    }
    final decoded = res.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
          (decoded['error'] as String?) ?? 'Request failed (${res.statusCode})');
    }
    return decoded;
  }

  /// Handles linked to the account on the server.
  Future<Map<String, String>> fetchServerHandles() async {
    final data = await _authedJson('GET', '/api/me/handles');
    return ((data['handles'] as Map?) ?? {})
        .map((k, v) => MapEntry('$k', '$v'));
  }

  /// Upserts non-empty handles and removes null values server-side.
  /// Platforms not present in [changes] are left untouched.
  Future<void> syncHandles(Map<String, String?> changes) =>
      _authedJson('PUT', '/api/me/handles', body: {'handles': changes});

  /// Queues a CodeChef solution import for the signed-in user's saved
  /// handle. Returns the queued job; throws when no handle is linked.
  Future<Map<String, dynamic>> triggerCodeChefImport() async {
    final data = await _authedJson('POST', '/api/me/import/codechef');
    return (data['job'] as Map).cast<String, dynamic>();
  }

  /// Latest CodeChef import job for this account, or null if none ran yet.
  Future<Map<String, dynamic>?> fetchCodeChefImportStatus() async {
    final data = await _authedJson('GET', '/api/me/import/codechef');
    return (data['job'] as Map?)?.cast<String, dynamic>();
  }

  /// Imported CodeChef submissions (metadata; use [fetchMySubmission] for
  /// the source code). Returns {'total': int, 'submissions': [...]}.
  Future<Map<String, dynamic>> fetchMySubmissions(
      {int limit = 50, int offset = 0}) {
    return _authedJson('GET', '/api/me/submissions?limit=$limit&offset=$offset');
  }

  /// One imported submission including its source code (when available).
  Future<Map<String, dynamic>> fetchMySubmission(String id) async {
    final data = await _authedJson('GET', '/api/me/submissions/$id');
    return (data['submission'] as Map).cast<String, dynamic>();
  }

  /// Set [fresh] when the user explicitly refreshes: the backend bypasses its
  /// 6h cache (subject to a 5-minute cooldown) and records a new snapshot.
  Future<PlatformProfile> fetchProfile(String platform, String handle,
      {bool fresh = false}) async {
    final suffix = fresh ? '?fresh=1' : '';
    return PlatformProfile.fromJson(
        await _getJson('/api/profile/$platform/$handle$suffix',
            timeout: const Duration(seconds: 60)));
  }

  /// Recently accepted solves (with problem names/links where available), for
  /// the weekly-progress chart and the Recent Solves feed.
  /// Returns null when the platform exposes no public submission history
  /// (GFG) - callers fall back to snapshot deltas.
  /// Asks for 8 days so local-timezone bucketing never misses the week edges.
  Future<List<Solve>?> fetchActivity(String platform, String handle,
      {bool fresh = false}) async {
    final suffix = fresh ? '&fresh=1' : '';
    final data = await _getJson('/api/activity/$platform/$handle?days=8$suffix',
        timeout: const Duration(seconds: 60));
    if (data['supported'] != true) return null;
    return ((data['solves'] as List?) ?? []).map((s) {
      final m = s as Map;
      return Solve(
        id: '${m['id']}',
        name: m['name'] as String?,
        url: m['url'] as String?,
        at: DateTime.fromMillisecondsSinceEpoch((m['at'] as num).toInt(),
            isUtc: true),
      );
    }).toList();
  }

  /// Per-day submission counts for the unified activity heatmap:
  /// 'yyyy-MM-dd' (UTC date) -> submissions that day, covering ~1 year.
  /// Returns null when the platform has no public per-day history (GFG).
  Future<Map<String, int>?> fetchHeatmap(String platform, String handle,
      {bool fresh = false}) async {
    final suffix = fresh ? '&fresh=1' : '';
    final data = await _getJson(
        '/api/heatmap/$platform/$handle?days=365$suffix',
        timeout: const Duration(seconds: 60));
    if (data['supported'] != true) return null;
    return ((data['days'] as Map?) ?? {})
        .map((k, v) => MapEntry('$k', ((v as num?) ?? 0).toInt()));
  }

  /// Topic-wise categorization of solved problems for the Progress tab
  /// (LeetCode: skill tags + difficulty split; Codeforces: problem tags).
  /// Returns null when the platform exposes no public tag data (CodeChef,
  /// AtCoder, GFG).
  Future<TopicStats?> fetchTopics(String platform, String handle,
      {bool fresh = false}) async {
    final suffix = fresh ? '?fresh=1' : '';
    final data = await _getJson('/api/topics/$platform/$handle$suffix',
        timeout: const Duration(seconds: 60));
    if (data['supported'] != true) return null;
    final difficulty = (data['difficulty'] as Map?)
        ?.map((k, v) => MapEntry('$k', ((v as num?) ?? 0).toInt()));
    final topics = ((data['topics'] as List?) ?? []).map((t) {
      final m = t as Map;
      return TopicCount(
        tag: '${m['tag']}',
        solved: ((m['solved'] as num?) ?? 0).toInt(),
      );
    }).toList();
    return TopicStats(topics: topics, difficulty: difficulty);
  }

  Future<List<Contest>> fetchContests() async {
    final data = await _getJson('/api/contests');
    return (data['contests'] as List)
        .map((c) => Contest.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<List<Map<String, dynamic>>> fetchSnapshots(
      String platform, String handle) async {
    final data = await _getJson('/api/snapshots/$platform/$handle');
    return ((data['snapshots'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchRecentSolved(String handle,
      {int limit = 20}) async {
    final data = await _getJson('/api/solved/codeforces/$handle?limit=$limit',
        timeout: const Duration(seconds: 60));
    return ((data['problems'] as List?) ?? []).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchLeaderboard(
      String platform, List<String> handles) async {
    final joined = handles.join(',');
    final data = await _getJson(
        '/api/leaderboard?platform=$platform&handles=$joined',
        timeout: const Duration(seconds: 120));
    return ((data['leaderboard'] as List?) ?? []).cast<Map<String, dynamic>>();
  }
}
