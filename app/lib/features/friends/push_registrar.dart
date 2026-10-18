import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import 'call_state.dart';
import 'fcm_push_port.dart';
import 'friends_controller.dart';
import 'messaging_host.dart';

/// What the native side told us at start-up (see ios/Runner/AppDelegate.swift).
class PushInitial {
  const PushInitial({this.token, this.opened});
  final String? token;
  final PushOpened? opened;
}

/// A tapped push notification. Only the sender's id and the kind ever travel in a push.
class PushOpened {
  const PushOpened(this.friendId, this.kind);
  final String friendId;
  final String kind; // 'message' | 'call' | 'friendRequest'
}

/// The kind a push carries; anything unknown is a plain message (the oldest, safest behaviour).
String pushKindOf(Object? raw) => raw == 'call' ? 'call' : (raw == 'friendRequest' ? 'friendRequest' : 'message');

/// The native bridge, so the logic can be tested without a platform channel.
abstract class PushPort {
  void listen({
    required void Function(String token) onToken,
    required void Function(String message) onError,
    required void Function(PushOpened opened) onOpened,
    required bool Function(PushOpened info) presentation,
  });
  Future<bool> requestPermission();
  Future<PushInitial> initial();

  /// False when the platform push is not usable (e.g. Firebase is not configured): the registrar then does nothing.
  /// Only meaningful after [initial].
  bool get available => true;

  /// True when notifications are already allowed (no explanation dialog needed).
  Future<bool> isPermitted() async => false;
}

/// MethodChannel `vn.mamba/push`: native -> Dart `token`, `error`, `opened`, `presentation`; Dart -> native
/// `requestPermission`, `initial`.
class ChannelPushPort implements PushPort {
  @override
  bool get available => true;

  @override
  Future<bool> isPermitted() async => false;

  ChannelPushPort([MethodChannel? channel]) : _ch = channel ?? const MethodChannel('vn.mamba/push');
  final MethodChannel _ch;

  static PushOpened? _opened(Object? args) {
    if (args is! Map) return null;
    final id = args['friendId'];
    if (id is! String || id.isEmpty) return null;
    return PushOpened(id, pushKindOf(args['kind']));
  }

  @override
  void listen({
    required void Function(String token) onToken,
    required void Function(String message) onError,
    required void Function(PushOpened opened) onOpened,
    required bool Function(PushOpened info) presentation,
  }) {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'token':
          if (call.arguments is String) onToken(call.arguments as String);
        case 'error':
          onError('${call.arguments}');
        case 'opened':
          final o = _opened(call.arguments);
          if (o != null) onOpened(o);
        case 'presentation':
          final o = _opened(call.arguments);
          return o == null ? true : presentation(o);
      }
      return null;
    });
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _ch.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PushInitial> initial() async {
    try {
      final m = await _ch.invokeMethod<Map<Object?, Object?>>('initial');
      final t = m?['token'];
      return PushInitial(token: t is String && t.isNotEmpty ? t : null, opened: _opened(m?['opened']));
    } catch (_) {
      return const PushInitial();
    }
  }
}

/// iOS (APNs) and Android (FCM, see [FcmPushPort]); a no-op elsewhere. Keeps this device's push token registered on the server for the signed-in CUSTOMER:
///  - registers `POST /me/push-token` after a customer signs in and whenever the token changes;
///  - removes it (`DELETE /me/push-token`) when they sign out - before the session is cleared when the sign-out goes
///    through [AuthStore.logout];
///  - asks for notification permission once (after an explanation) and routes a tapped notification to the chat.
/// The server only wakes this phone; the message itself is still delivered over the encrypted socket.
class PushRegistrar {
  PushRegistrar({
    required this.auth,
    required this.api,
    required this.openRoute,
    PushPort? port,
    bool? isIos,
    bool? isAndroid,
    this.explain,
    this.hub,
    this.retryDelay = const Duration(seconds: 30),
    this.openDelay = const Duration(milliseconds: 400),
  })  : _isIos = isIos ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS),
        // An explicit isIos (tests) switches the platform auto-detection off.
        _isAndroid = isAndroid ?? (isIos == null && !kIsWeb && defaultTargetPlatform == TargetPlatform.android),
        _port = port ?? ((isIos ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)) ? ChannelPushPort() : FcmPushPort());

  final AuthStore auth;
  final ApiClient api;

  /// Navigates to a go_router location (e.g. `/friends/chat/abc`).
  final void Function(String route) openRoute;

  /// Shows the explanation dialog; true = go on and ask the OS. Null: ask without explanation.
  final Future<bool> Function()? explain;

  /// The live messaging hub (for the foreground-banner decision); may be null.
  FriendsController? Function()? hub;
  final Duration retryDelay;

  /// Lets the router finish building after a cold start before navigating.
  final Duration openDelay;

  final PushPort _port;
  final bool _isIos;
  final bool _isAndroid;
  bool _unavailable = false;

  String get _platform => _isIos ? 'ios' : 'android';

  static const _askedKey = 'mamba_push_asked';

  String? _token; // latest token from the OS
  String? _registered; // token the server knows for the current user
  bool _signedInCustomer = false;
  bool _started = false;
  bool _asking = false;
  PushOpened? _pendingOpen;
  Timer? _retry;

  bool get active => (_isIos || _isAndroid) && _started && !_unavailable;

  Future<void> start() async {
    if (!(_isIos || _isAndroid) || _started) return;
    _started = true;
    _port.listen(onToken: _onToken, onError: (m) => debugPrint('push: $m'), onOpened: _onOpened, presentation: _present);
    final init = await _port.initial();
    if (!_started) return; // disposed meanwhile
    if (!_port.available) {
      _unavailable = true; // e.g. Android build without google-services.json: silent no-op
      return;
    }
    auth.beforeLogout.add(_unregister);
    auth.addListener(_sync);
    if (init.token != null) _token = init.token;
    if (init.opened != null) _pendingOpen = init.opened;
    _sync();
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    _retry?.cancel();
    final p = _port;
    if (p is FcmPushPort) p.dispose();
    auth.beforeLogout.remove(_unregister);
    auth.removeListener(_sync);
  }

  static bool _wants(AuthStore a) => a.ready && a.signedIn && a.role == 'user';

  void _sync() {
    final want = _wants(auth);
    if (want && !_signedInCustomer) {
      _signedInCustomer = true;
      _registered = null;
      unawaited(_register());
      unawaited(_askPermission());
    } else if (!want && _signedInCustomer) {
      _signedInCustomer = false;
      _retry?.cancel();
      // Sign-out that did not go through logout() (e.g. the session was revoked): the server call will fail with
      // 401; forget the token locally anyway.
      _registered = null;
    }
    _flushOpen();
  }

  void _onToken(String t) {
    _token = t;
    if (_signedInCustomer && t != _registered) unawaited(_register());
  }

  Future<void> _register() async {
    final t = _token;
    if (t == null || !_signedInCustomer || t == _registered) return;
    try {
      await api.post('/me/push-token', {'platform': _platform, 'token': t, 'deviceLabel': _isIos ? 'iPhone' : 'Android'});
      if (_token == t) _registered = t;
    } catch (_) {
      _retry?.cancel();
      _retry = Timer(retryDelay, () => unawaited(_register()));
    }
  }

  /// Runs before the session is cleared on an explicit logout.
  Future<void> _unregister() async {
    _retry?.cancel();
    final t = _registered ?? _token;
    _registered = null;
    if (t == null || !_signedInCustomer) return;
    try {
      await api.delete('/me/push-token', {'token': t});
    } catch (_) {/* offline: the server drops dead tokens by itself when APNs rejects them */}
  }

  Future<void> _askPermission() async {
    if (_asking) return;
    _asking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_askedKey) == true) return;
      if (await _port.isPermitted()) {
        await prefs.setBool(_askedKey, true);
        return;
      }
      final go = await (explain?.call() ?? Future.value(true));
      if (!go) return; // "Để sau": ask again next sign-in
      await prefs.setBool(_askedKey, true);
      await _port.requestPermission();
    } catch (_) {/* not fatal */} finally {
      _asking = false;
    }
  }

  void _onOpened(PushOpened o) {
    _pendingOpen = o;
    _flushOpen();
  }

  void _flushOpen() {
    final o = _pendingOpen;
    if (o == null || !_signedInCustomer) return; // wait until a customer is signed in
    _pendingOpen = null;
    // Calls open the chat too: a call that rang while the app was closed is long over. A friend request opens the
    // friends screen, where the requests block is at the top.
    final route = o.kind == 'friendRequest' ? '/friends' : '/friends/chat/${Uri.encodeComponent(o.friendId)}';
    Timer(openDelay, () => openRoute(route));
  }

  /// Foreground: show the OS banner only if the same information is not already on screen in the app.
  bool _present(PushOpened info) {
    final h = hub?.call();
    if (h == null) return true;
    if (info.kind == 'friendRequest') return !(h.socket.ready); // the live event already shows an in-app banner
    if (info.kind == 'call') return h.call == null || h.call!.status == CallStatus.idle;
    return h.chat?.openPeer != info.friendId;
  }
}

/// Hands the live messaging hub to the registrar. Place it below [MessagingHost].
class PushBinding extends StatelessWidget {
  const PushBinding({super.key, required this.registrar, required this.child});
  final PushRegistrar registrar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final h = MessagingScope.maybeOf(context);
    registrar.hub = () => h;
    return child;
  }
}
