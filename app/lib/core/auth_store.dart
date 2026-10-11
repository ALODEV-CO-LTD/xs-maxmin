import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The signed-in session (token + role), kept in the Android keystore-backed secure storage.
/// [ready] turns true once the saved session was read; the router waits for it.
class AuthStore extends ChangeNotifier {
  AuthStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _tokenKey = 'xoso_token';
  static const _roleKey = 'xoso_role';

  String? token;
  String? role;
  bool ready = false;

  bool get signedIn => token != null && token!.isNotEmpty;
  bool get isAdmin => role == 'admin';

  Future<void> init() async {
    try {
      token = await _storage.read(key: _tokenKey);
      role = await _storage.read(key: _roleKey);
    } catch (_) {
      token = null;
      role = null;
    }
    ready = true;
    notifyListeners();
  }

  Future<void> login(String newToken, String? newRole) async {
    token = newToken;
    role = newRole ?? 'user';
    try {
      await _storage.write(key: _tokenKey, value: token);
      await _storage.write(key: _roleKey, value: role);
    } catch (_) {/* works for this run only */}
    notifyListeners();
  }

  /// Drops the session (explicit logout, or the server answered 401).
  void clear() {
    if (token == null && role == null) return;
    token = null;
    role = null;
    _storage.delete(key: _tokenKey).catchError((_) {});
    _storage.delete(key: _roleKey).catchError((_) {});
    notifyListeners();
  }
}
