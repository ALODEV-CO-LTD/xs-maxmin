import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/api_client.dart';

/// Admin-set security policy (`GET /me/policy`). Safe defaults apply until the answer says otherwise.
class PrivacyPolicy {
  const PrivacyPolicy({this.autoLockMinutes = 0, this.hideLockSeconds = 0, this.watermarkEnabled = false, this.screenshotGuardEnabled = true, this.blurOnHideEnabled = false});
  final int autoLockMinutes;

  /// Admin default for "lock when the app was away for this long" (0 = off); a person's own choice wins.
  final int hideLockSeconds;
  final bool watermarkEnabled;
  final bool screenshotGuardEnabled;
  final bool blurOnHideEnabled;

  /// Same rules as frontend/src/stores/policy.js: the guard is ON unless the server says `false`; blur is OFF
  /// unless the server says `true`; the default idle lock is `Number(x) || 0`.
  factory PrivacyPolicy.fromJson(Object? json) {
    if (json is! Map) return const PrivacyPolicy();
    final raw = json['autoLockMinutes'];
    final minutes = raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
    final rawHide = json['hideLockSeconds'];
    final hide = rawHide is num ? rawHide.toInt() : int.tryParse('$rawHide') ?? 0;
    return PrivacyPolicy(
      autoLockMinutes: minutes < 0 ? 0 : minutes,
      hideLockSeconds: hide < 0 ? 0 : hide,
      watermarkEnabled: json['watermarkEnabled'] == true,
      screenshotGuardEnabled: json['screenshotGuardEnabled'] != false,
      blurOnHideEnabled: json['blurOnHideEnabled'] == true,
    );
  }
}

/// App-wide privacy state, port of frontend/src/stores/privacy.js + policy.js:
///  - auto-lock after [autoLockMinutes] of no touch (per-device choice, else the Admin default),
///  - lock when the app was in the background for >= [hideLockSeconds],
///  - blur the content while the app is away when the policy allows it and the user keeps it on,
///  - the lock survives an app restart (persisted) so killing the app does not bypass it.
/// All time comes from [clock] so the timing is unit-testable; the periodic check is driven by the PrivacyGate widget.
class PrivacyStore extends ChangeNotifier {
  PrivacyStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;

  static const idleChoices = [0, 1, 5, 15, 30];
  static const hideChoices = [0, 30, 60, 300];
  static const _settingsKey = 'xoso_privacy';
  static const _lockedKey = 'xoso_locked';
  static const _activeKey = 'xoso_last_active';

  PrivacyPolicy policy = const PrivacyPolicy();

  /// True once the saved settings/lock were read (the gate keeps the screen covered until then).
  bool ready = false;
  bool locked = false;

  /// App is in the background / app switcher: content is blurred when [blurActive].
  bool away = false;

  int? _ownAutoLockMinutes; // null = follow the Admin default
  int? _ownHideLockSeconds; // null = follow the Admin default
  bool blurOnHide = true;

  /// Set by features that must not be interrupted (e.g. a voice call): idle time then counts as activity.
  bool Function()? isBusy;

  DateTime _lastActive = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _hiddenAt;
  bool _started = false;
  DateTime? _policyAt;

  int get autoLockMinutes => _ownAutoLockMinutes ?? policy.autoLockMinutes;
  bool get hasOwnAutoLock => _ownAutoLockMinutes != null;
  int get hideLockSeconds => _ownHideLockSeconds ?? policy.hideLockSeconds;
  bool get hasOwnHideLock => _ownHideLockSeconds != null;
  bool get screenshotGuardOn => policy.screenshotGuardEnabled;

  /// Blur is allowed by the Admin AND chosen by the user.
  bool get blurActive => policy.blurOnHideEnabled && blurOnHide;
  bool get veiled => away && !locked && blurActive;

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Called when a user is signed in: loads the saved settings + lock, then the policy from the server.
  Future<void> start(ApiClient api) async {
    if (_started) return;
    _started = true;
    final p = await _prefs();
    if (p != null) {
      try {
        final raw = jsonDecode(p.getString(_settingsKey) ?? '{}');
        if (raw is Map) {
          final a = raw['autoLockMinutes'];
          _ownAutoLockMinutes = a is num && a >= 0 ? a.toInt() : null;
          final h = raw['hideLockSeconds'];
          _ownHideLockSeconds = h is num && h >= 0 ? h.toInt() : null;
          blurOnHide = raw['blurOnHide'] is bool ? raw['blurOnHide'] as bool : true;
        }
      } catch (_) {/* defaults */}
      final last = p.getInt(_activeKey);
      _lastActive = last != null ? DateTime.fromMillisecondsSinceEpoch(last) : _clock();
      if (p.getBool(_lockedKey) == true) locked = true;
    } else {
      _lastActive = _clock();
    }
    checkIdle();
    ready = true;
    notifyListeners();
    await refreshPolicy(api, force: true);
  }

  /// Signed out: forget the lock and the activity clock.
  Future<void> stop() async {
    if (!_started && !locked) return;
    _started = false;
    ready = false;
    locked = false;
    away = false;
    _hiddenAt = null;
    policy = const PrivacyPolicy();
    notifyListeners();
    final p = await _prefs();
    await p?.remove(_lockedKey);
    await p?.remove(_activeKey);
  }

  Future<void> refreshPolicy(ApiClient api, {bool force = false}) async {
    final now = _clock();
    if (!force && _policyAt != null && now.difference(_policyAt!) < const Duration(seconds: 60)) return;
    _policyAt = now;
    try {
      applyPolicy(await api.get('/me/policy'));
    } catch (_) {/* keep the safe defaults / last known policy */}
  }

  void applyPolicy(Object? json) {
    policy = PrivacyPolicy.fromJson(json);
    if (!policy.blurOnHideEnabled) away = false;
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final p = await _prefs();
    await p?.setString(_settingsKey, jsonEncode({if (_ownAutoLockMinutes != null) 'autoLockMinutes': _ownAutoLockMinutes, if (_ownHideLockSeconds != null) 'hideLockSeconds': _ownHideLockSeconds, 'blurOnHide': blurOnHide}));
  }

  Future<void> setAutoLockMinutes(int minutes) async {
    _ownAutoLockMinutes = minutes < 0 ? 0 : minutes;
    touch(force: true);
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setHideLockSeconds(int seconds) async {
    _ownHideLockSeconds = seconds < 0 ? 0 : seconds;
    notifyListeners();
    await _saveSettings();
  }

  Future<void> setBlurOnHide(bool on) async {
    blurOnHide = on;
    if (!on) away = false;
    notifyListeners();
    await _saveSettings();
  }

  /// User activity (touch). Ignored while locked. Storage writes are throttled to one per 5 s.
  void touch({bool force = false}) {
    if (locked && !force) return;
    final now = _clock();
    _lastActive = now;
    if (force || now.difference(_lastWrite) > const Duration(seconds: 5)) {
      _lastWrite = now;
      unawaited(_prefs().then((p) => p?.setInt(_activeKey, now.millisecondsSinceEpoch)));
    }
  }

  /// Locks if the idle limit has passed (also covers the phone sleeping). Returns true if it locked.
  bool checkIdle() {
    if (locked || autoLockMinutes <= 0) return false;
    if (isBusy?.call() == true) {
      touch(force: true);
      return false;
    }
    if (_clock().difference(_lastActive) >= Duration(minutes: autoLockMinutes)) {
      lock();
      return true;
    }
    return false;
  }

  void lock() {
    if (locked || isBusy?.call() == true) return;
    locked = true;
    notifyListeners();
    unawaited(_prefs().then((p) => p?.setBool(_lockedKey, true)));
  }

  /// Asks the server to check the login or layer-2 password (`POST /me/verify-password`); throws [ApiError].
  Future<void> unlock(ApiClient api, String password) async {
    await api.post('/me/verify-password', {'password': password});
    locked = false;
    away = false;
    notifyListeners();
    final p = await _prefs();
    await p?.remove(_lockedKey);
    touch(force: true);
  }

  /// Feed [AppLifecycleState] changes here.
  void onLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final hidden = _hiddenAt;
      _hiddenAt = null;
      if (hidden != null && hideLockSeconds > 0 && _clock().difference(hidden) >= Duration(seconds: hideLockSeconds)) lock();
      checkIdle();
      if (away) {
        away = false;
        notifyListeners();
      }
    } else {
      _hiddenAt ??= _clock();
      if (blurActive && isBusy?.call() != true && !away) {
        away = true;
        notifyListeners();
      }
    }
  }
}
