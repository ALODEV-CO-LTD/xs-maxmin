import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// "Ẩn số liệu": a screen-only mask (not encryption), port of frontend/src/stores/mask.js. While [enabled] every figure
/// shows as "••••" until the user retypes the account password (`POST /me/verify-password`), which reveals them for
/// [revealSeconds] of IDLE time (any touch calls [touch] and restarts it). They are covered at once when the app goes
/// to the background.
class MaskStore extends ChangeNotifier with WidgetsBindingObserver {
  MaskStore() {
    WidgetsBinding.instance.addObserver(this);
  }

  static const revealChoices = [10, 20, 30, 60, 300];
  static const _enabledKey = 'xoso_mask_enabled';
  static const _secondsKey = 'xoso_mask_reveal_seconds';

  /// "Ẩn số liệu" was removed from the app: figures are always shown. (The class stays so the screens that read [masked] keep working.)
  bool enabled = false;
  bool revealed = false;
  int revealSeconds = 30;
  Timer? _timer;
  DateTime _until = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while the figures must NOT be shown. Widgets show "••••" and never touch the real value.
  bool get masked => false;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    // an old "on" saved by an earlier version must not hide anything any more
    if (p.containsKey(_enabledKey)) await p.remove(_enabledKey);
    enabled = false;
    final s = p.getInt(_secondsKey);
    if (s != null && revealChoices.contains(s)) revealSeconds = s;
    notifyListeners();
  }

  Future<void> setEnabled(bool on) async {
    enabled = on;
    if (!on) cover(notify: false);
    notifyListeners();
    (await SharedPreferences.getInstance()).setBool(_enabledKey, on);
  }

  Future<void> setRevealSeconds(int s) async {
    if (!revealChoices.contains(s)) return;
    revealSeconds = s;
    if (revealed) touch();
    notifyListeners();
    (await SharedPreferences.getInstance()).setInt(_secondsKey, s);
  }

  /// Asks the server to check the password; on success the figures are shown. Throws [ApiError] when it is wrong.
  Future<void> revealWithPassword(ApiClient api, String password) async {
    await api.post('/me/verify-password', {'password': password});
    revealed = true;
    touch();
    notifyListeners();
  }

  /// User activity: restarts the idle timer.
  void touch() {
    if (!revealed) return;
    _until = DateTime.now().add(Duration(seconds: revealSeconds));
    _timer?.cancel();
    _timer = Timer(Duration(seconds: revealSeconds), _check);
  }

  void _check() {
    if (!revealed) return;
    if (DateTime.now().isBefore(_until)) {
      _timer = Timer(_until.difference(DateTime.now()), _check);
    } else {
      cover();
    }
  }

  void cover({bool notify = true}) {
    _timer?.cancel();
    if (!revealed) return;
    revealed = false;
    if (notify) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) cover();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
