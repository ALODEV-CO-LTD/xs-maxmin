import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'me_profile.dart';

/// Holds `GET /me` for the Account screen and its tabs.
class AccountController extends ChangeNotifier {
  AccountController(this.api);
  final ApiClient api;

  MeProfile? me;
  bool loading = true;
  String? error;

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      loading = true;
      error = null;
      notifyListeners();
    }
    try {
      final res = await api.get('/me');
      me = MeProfile.fromJson((res as Map).cast<String, dynamic>());
      error = null;
    } on ApiError catch (e) {
      if (!silent || me == null) error = e.message;
    } catch (_) {
      if (!silent || me == null) error = 'Không tải được thông tin tài khoản';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Applies the profile returned by `PATCH /me`.
  void setFromJson(dynamic json) {
    if (json is Map) {
      me = MeProfile.fromJson(json.cast<String, dynamic>());
      notifyListeners();
    }
  }
}
