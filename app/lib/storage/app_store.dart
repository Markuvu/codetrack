import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/flashcard.dart';

/// Simple local persistence via SharedPreferences.
/// Swap for sqlite/drift when data outgrows key-value storage.
class AppStore {
  static const _handlesKey = 'handles';
  static const _cardsKey = 'flashcards';

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
}
