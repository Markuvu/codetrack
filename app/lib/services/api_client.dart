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

  Future<PlatformProfile> fetchProfile(String platform, String handle) async {
    final base = await baseUrl();
    final res = await http
        .get(Uri.parse('$base/api/profile/$platform/$handle'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Profile fetch failed (${res.statusCode})');
    }
    return PlatformProfile.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<Contest>> fetchContests() async {
    final base = await baseUrl();
    final res = await http
        .get(Uri.parse('$base/api/contests'))
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw Exception('Contest fetch failed (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['contests'] as List)
        .map((c) => Contest.fromJson(c as Map<String, dynamic>))
        .toList();
  }
}
