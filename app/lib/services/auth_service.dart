import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Thrown for auth failures with a message safe to show the user.
class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Server-backed account (backend `/api/auth/*` + `/api/me`).
///
/// Tokens live in platform secure storage (Android Keystore / iOS Keychain
/// via flutter_secure_storage) - never in SharedPreferences. Only the name
/// and email are cached in SharedPreferences, purely for instant display.
/// Access tokens are short-lived JWTs; the refresh token rotates on every
/// refresh and is revoked server-side on logout / password change.
class AuthService {
  AuthService._();

  static final AuthService instance = AuthService._();

  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';
  static const _nameKey = 'auth_name'; // display cache only
  static const _emailKey = 'auth_email'; // display cache only

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<String>? _refreshing;

  Future<String> _baseUrl() => ApiClient().baseUrl();

  Future<Map<String, dynamic>> _postJson(
      String path, Map<String, dynamic> body) async {
    final base = await _baseUrl();
    late http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$base$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw AuthException('Could not reach the server. Check the backend '
          'URL in Settings and your connection.');
    }
    Map<String, dynamic> decoded;
    try {
      decoded = res.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      decoded = <String, dynamic>{};
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AuthException(
          (decoded['error'] as String?) ?? 'Request failed (${res.statusCode})');
    }
    return decoded;
  }

  Future<void> _storeSession(Map<String, dynamic> data) async {
    await _secureStorage.write(
        key: _accessTokenKey, value: data['accessToken'] as String);
    await _secureStorage.write(
        key: _refreshTokenKey, value: data['refreshToken'] as String);
    final user = data['user'] as Map<String, dynamic>?;
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_nameKey, user['name'] as String);
      await prefs.setString(_emailKey, user['email'] as String);
    }
  }

  Future<bool> isLoggedIn() async =>
      await _secureStorage.read(key: _refreshTokenKey) != null;

  /// Whether this device signed in before (used to default the auth screen
  /// to the login form). Based on the cached email, not on credentials.
  Future<bool> hasAccount() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey) != null;
  }

  Future<String?> name() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey);
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
    final data = await _postJson('/api/auth/signup', {
      'name': name,
      'email': email.toLowerCase(),
      'password': password,
    });
    await _storeSession(data);
  }

  Future<void> logIn({required String email, required String password}) async {
    final data = await _postJson('/api/auth/login', {
      'email': email.toLowerCase(),
      'password': password,
    });
    await _storeSession(data);
  }

  static bool _isExpired(String jwt) {
    try {
      final payload = jwt.split('.')[1];
      final decoded = jsonDecode(utf8.decode(
          base64Url.decode(base64Url.normalize(payload)))) as Map;
      final exp = (decoded['exp'] as num).toInt();
      // 30s leeway so a token doesn't expire mid-request.
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= exp - 30;
    } catch (_) {
      return true;
    }
  }

  /// A valid access token, transparently refreshed (with rotation) when the
  /// current one is missing or about to expire. Throws [AuthException] when
  /// the session is gone and the user must log in again.
  Future<String> accessToken() async {
    final current = await _secureStorage.read(key: _accessTokenKey);
    if (current != null && !_isExpired(current)) return current;
    return _refreshing ??= _refreshSession().whenComplete(() {
      _refreshing = null;
    });
  }

  Future<String> _refreshSession() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken == null) {
      throw AuthException('You are signed out. Please log in again.');
    }
    late Map<String, dynamic> data;
    try {
      data =
          await _postJson('/api/auth/refresh', {'refreshToken': refreshToken});
    } on AuthException {
      // Refresh token expired or revoked: drop the dead session.
      await _clearTokens();
      throw AuthException('Your session expired. Please log in again.');
    }
    await _storeSession(data);
    return data['accessToken'] as String;
  }

  /// Update the display name on the server (and the local cache).
  Future<void> setName(String name) async {
    final base = await _baseUrl();
    final token = await accessToken();
    final res = await http
        .patch(
          Uri.parse('$base/api/me'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'name': name}),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw AuthException('Could not update your name (${res.statusCode}).');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }

  /// Changes the password server-side. All refresh tokens are revoked by the
  /// backend, so this device re-authenticates with the new session returned
  /// by an immediate login.
  Future<bool> changePassword({
    required String current,
    required String newPassword,
  }) async {
    final savedEmail = await email();
    if (savedEmail == null) throw AuthException('Not signed in.');
    final token = await accessToken();
    final base = await _baseUrl();
    final res = await http
        .post(
          Uri.parse('$base/api/me/password'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'currentPassword': current,
            'newPassword': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode == 403) return false;
    if (res.statusCode != 204) {
      final body = res.body.isEmpty ? {} : jsonDecode(res.body) as Map;
      throw AuthException(
          (body['error'] as String?) ?? 'Password change failed.');
    }
    // Keep this device signed in with a fresh session.
    await logIn(email: savedEmail, password: newPassword);
    return true;
  }

  Future<void> logOut() async {
    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken != null) {
      try {
        await _postJson('/api/auth/logout', {'refreshToken': refreshToken});
      } catch (_) {
        // Offline logout still clears the device; the token expires
        // server-side on its own.
      }
    }
    await _clearTokens();
  }

  Future<void> _clearTokens() async {
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
  }
}
