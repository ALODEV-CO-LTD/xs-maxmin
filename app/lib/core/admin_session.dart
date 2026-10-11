import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// The signed-in admin's profile and rights from `GET /me` (`permissions` = every right for the root Admin,
/// `isRoot` = the root Admin who can manage staff). Same rule as frontend/src/stores/auth.js `can()`.
class AdminSession extends ChangeNotifier {
  Map<String, dynamic>? me;
  Set<String> permissions = {};
  bool isRoot = false;
  bool loading = false;
  String? error;

  String get name => (me?['name'] as String?) ?? '';
  String get username => (me?['username'] as String?) ?? '';

  /// True when the account holds [perm]; a list means "any of them". The root Admin holds everything.
  bool can(Object perm) {
    if (isRoot) return true;
    final list = perm is List ? perm.cast<String>() : [perm as String];
    return list.any(permissions.contains);
  }

  Future<void> load(ApiClient api) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final res = await api.get('/me') as Map<String, dynamic>;
      me = res;
      isRoot = res['isRoot'] == true;
      permissions = {for (final p in (res['permissions'] as List? ?? const [])) '$p'};
    } on ApiError catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void reset() {
    me = null;
    permissions = {};
    isRoot = false;
    notifyListeners();
  }
}
