import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local device account.
///
/// Credentials never leave the phone: the password is stored as a salted
/// SHA-256 hash in SharedPreferences and simply gates the app UI. When the
/// backend gains real user accounts (cloud sync), this can be swapped for
/// server-side auth without changing the screens.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _nameKey = 'auth_name';
  static const _emailKey = 'auth_email';
  static const _saltKey = 'auth_salt';
  static const _hashKey = 'auth_hash';
  static const _loggedInKey = 'auth_logged_in';

  String _hash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  String _newSalt() {
    final rng = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => rng.nextInt(256)));
  }

  Future<bool> hasAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_hashKey) != null;
  }

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_loggedInKey) ?? false;
  }

  Future<String?> name() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey);
  }

  Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }

  Future<String?> email() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _newSalt();
    await prefs.setString(_nameKey, name);
    await prefs.setString(_emailKey, email.toLowerCase());
    await prefs.setString(_saltKey, salt);
    await prefs.setString(_hashKey, _hash(password, salt));
    await prefs.setBool(_loggedInKey, true);
  }

  Future<bool> logIn({required String email, required String password}) async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString(_emailKey);
    final salt = prefs.getString(_saltKey);
    final hash = prefs.getString(_hashKey);
    if (savedEmail == null || salt == null || hash == null) return false;
    if (email.toLowerCase() != savedEmail) return false;
    if (_hash(password, salt) != hash) return false;
    await prefs.setBool(_loggedInKey, true);
    return true;
  }

  Future<bool> changePassword({
    required String current,
    required String newPassword,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = prefs.getString(_saltKey);
    final hash = prefs.getString(_hashKey);
    if (salt == null || hash == null) return false;
    if (_hash(current, salt) != hash) return false;
    final newSalt = _newSalt();
    await prefs.setString(_saltKey, newSalt);
    await prefs.setString(_hashKey, _hash(newPassword, newSalt));
    return true;
  }

  Future<void> logOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
  }
}
