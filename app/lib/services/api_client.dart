import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contest.dart';
import '../models/profile.dart';

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

  /// Set [fresh] when the user explicitly refreshes: the backend bypasses its
  /// 6h cache (subject to a 5-minute cooldown) and records a new snapshot.
  Future<PlatformProfile> fetchProfile(String platform, String handle,
      {bool fresh = false}) async {
    final suffix = fresh ? '?fresh=1' : '';
    return PlatformProfile.fromJson(
        await _getJson('/api/profile/$platform/$handle$suffix',
            timeout: const Duration(seconds: 60)));
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
