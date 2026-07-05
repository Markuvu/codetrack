import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/flashcard.dart';

/// Simple local persistence via SharedPreferences.
/// Swap for sqlite/drift when data outgrows key-value storage.
class AppStore {
  static const _handlesKey = 'handles';
  static const _cardsKey = 'flashcards';
  static const _remindersKey = 'scheduled_reminders';
  static const _weeklyGoalKey = 'weekly_goal';

  Future<Map<String, String>> loadHandles() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_handlesKey);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  Future<void> saveHandles(Map<String, String> handles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_handlesKey, jsonEncode(handles));
  }

  Future<List<Flashcard>> loadCards() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cardsKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((c) => Flashcard.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveCards(List<Flashcard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _cardsKey,
      jsonEncode(cards.map((c) => c.toJson()).toList()),
    );
  }

  // Friends are stored per platform ('friends_codeforces', 'friends_leetcode',
  // ...). The codeforces key predates multi-platform support, so existing
  // friend lists carry over unchanged.
  Future<List<String>> loadFriends([String platform = 'codeforces']) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('friends_$platform') ?? [];
  }

  Future<void> saveFriends(List<String> friends,
      [String platform = 'codeforces']) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('friends_$platform', friends);
  }

  /// Scheduled contest reminders, so the user can review and cancel them.
  /// Each entry: notifId, contestName, platform, startMs, notifyAtMs.
  Future<List<Map<String, dynamic>>> loadReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_remindersKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Future<void> saveReminders(List<Map<String, dynamic>> reminders) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_remindersKey, jsonEncode(reminders));
  }

  /// Weekly problems-solved goal for the dashboard progress ring.
  Future<int> loadWeeklyGoal() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_weeklyGoalKey) ?? 50;
  }

  Future<void> saveWeeklyGoal(int goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_weeklyGoalKey, goal);
  }
}
