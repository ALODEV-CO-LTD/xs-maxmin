import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_registrar.dart';

/// The few Firebase calls the Android push needs, so the logic can be tested without Firebase.
abstract class FcmClient {
  /// Initialises Firebase from google-services.json. Throws when the app was built without that file.
  Future<void> initialize();
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;

  /// `data` of the notification that cold-started the app, if any.
  Future<Map<String, dynamic>?> initialMessageData();

  /// `data` of a notification tapped while the app was in the background.
  Stream<Map<String, dynamic>> get onOpenedData;
  Future<bool> requestPermission();
  Future<bool> isPermitted();
}

class FirebaseFcmClient implements FcmClient {
  FirebaseMessaging get _m => FirebaseMessaging.instance;

  @override
  Future<void> initialize() async {
    await Firebase.initializeApp();
  }

  @override
  Future<String?> getToken() => _m.getToken();

  @override
  Stream<String> get onTokenRefresh => _m.onTokenRefresh;

  @override
  Future<Map<String, dynamic>?> initialMessageData() async => (await _m.getInitialMessage())?.data;

  @override
  Stream<Map<String, dynamic>> get onOpenedData => FirebaseMessaging.onMessageOpenedApp.map((m) => m.data);

  @override
  Future<bool> requestPermission() async {
    final s = await _m.requestPermission();
    return s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<bool> isPermitted() async {
    final s = await _m.getNotificationSettings();
    return s.authorizationStatus == AuthorizationStatus.authorized;
  }
}

/// Android push through FCM, behind the same [PushPort] the iOS bridge implements.
///
/// Silent no-op when Firebase is not configured (no google-services.json in the build): [available] is false and
/// nothing is registered or asked.
///
/// Foreground messages are deliberately ignored (`onMessage` is never listened to): the app has its own socket, banner
/// and ringer, and Android does not draw FCM notifications while the app is on screen anyway. In the background or when
/// killed the OS draws the notification block itself (channels `mamba_messages` / `mamba_calls`, see notifications.dart),
/// so no Dart background handler is needed.
class FcmPushPort implements PushPort {
  FcmPushPort([FcmClient? client]) : _client = client ?? FirebaseFcmClient();
  final FcmClient _client;
  bool _available = false;
  void Function(String token)? _onToken;
  void Function(PushOpened opened)? _onOpened;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<Map<String, dynamic>>? _openedSub;

  @override
  bool get available => _available;

  /// `{friendId, kind}` from a notification's data; null if it is not one of ours.
  static PushOpened? openedFromData(Map<String, dynamic>? data) {
    final id = data?['friendId'];
    if (id is! String || id.isEmpty) return null;
    return PushOpened(id, data?['kind'] == 'call' ? 'call' : 'message');
  }

  @override
  void listen({
    required void Function(String token) onToken,
    required void Function(String message) onError,
    required void Function(PushOpened opened) onOpened,
    required bool Function(PushOpened info) presentation,
  }) {
    _onToken = onToken;
    _onOpened = onOpened;
  }

  @override
  Future<PushInitial> initial() async {
    try {
      await _client.initialize();
    } catch (e) {
      debugPrint('fcm: not configured (${e.runtimeType}); Android push disabled');
      return const PushInitial();
    }
    _available = true;
    try {
      _refreshSub = _client.onTokenRefresh.listen((t) => _onToken?.call(t), onError: (_) {});
      _openedSub = _client.onOpenedData.listen((d) {
        final o = openedFromData(d);
        if (o != null) _onOpened?.call(o);
      }, onError: (_) {});
      // The token can take a while (or need the network): hand it over when it arrives instead of blocking start-up.
      unawaited(_client.getToken().then((t) {
        if (t != null && t.isNotEmpty) _onToken?.call(t);
      }).catchError((Object _) {}));
      return PushInitial(opened: openedFromData(await _client.initialMessageData()));
    } catch (_) {
      return const PushInitial();
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _client.requestPermission();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isPermitted() async {
    try {
      return await _client.isPermitted();
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    unawaited(_refreshSub?.cancel());
    unawaited(_openedSub?.cancel());
  }
}
