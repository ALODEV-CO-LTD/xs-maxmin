import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notifications.dart';

/// The optional "keep the connection when the app is closed" switch (default OFF), stored on this device.
class KeepAliveSettings {
  static const prefsKey = 'mamba_keep_alive';

  static Future<bool> load() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(prefsKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> save(bool on) async {
    try {
      await (await SharedPreferences.getInstance()).setBool(prefsKey, on);
    } catch (_) {/* the switch simply resets next start */}
  }
}

/// What the Android foreground service should be doing right now.
///  - [off]: nothing running;
///  - [keepAlive]: the user turned the switch on - a persistent notification keeps the process (and the WebSocket)
///    alive in the background;
///  - [call]: a voice call is running - Android 11+ silences a microphone used by a background app unless a
///    foreground service of type `microphone` runs, so the call needs one even when the switch is off.
enum ServiceMode { off, keepAlive, call }

ServiceMode desiredServiceMode({required bool keepAlive, required bool inCall}) => inCall ? ServiceMode.call : (keepAlive ? ServiceMode.keepAlive : ServiceMode.off);

/// Runs / stops the Android foreground service; faked in tests.
abstract class BackgroundService {
  /// Moves the service to [mode] (starts, restarts with other types, or stops it). Never throws.
  Future<void> apply(ServiceMode mode);
}

class NoopBackgroundService implements BackgroundService {
  const NoopBackgroundService();
  @override
  Future<void> apply(ServiceMode mode) async {}
}

/// flutter_foreground_task: only a persistent notification + wake lock, no Dart task. The service types are declared
/// in AndroidManifest.xml (remoteMessaging, microphone).
class ForegroundTaskService implements BackgroundService {
  ServiceMode _current = ServiceMode.off;
  bool _inited = false;
  Future<void> _queue = Future.value();

  void _init() {
    if (_inited) return;
    _inited = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'mamba_keep_alive',
        channelName: 'Giữ kết nối',
        channelDescription: 'Hiện khi ứng dụng giữ kết nối để nhận tin nhắn và cuộc gọi',
        onlyAlertOnce: true,
        visibility: NotificationVisibility.VISIBILITY_SECRET,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false),
      foregroundTaskOptions: ForegroundTaskOptions(eventAction: ForegroundTaskEventAction.nothing(), allowWakeLock: true, allowAutoRestart: false, stopWithTask: false),
    );
  }

  @override
  Future<void> apply(ServiceMode mode) {
    // Changes are applied one after the other so a quick start/stop never overlaps.
    _queue = _queue.then((_) => _apply(mode)).catchError((Object e) {
      debugPrint('foreground service: $e');
    });
    return _queue;
  }

  Future<void> _apply(ServiceMode mode) async {
    if (mode == _current) return;
    _init();
    if (mode == ServiceMode.off) {
      if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
      _current = ServiceMode.off;
      return;
    }
    if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
    final call = mode == ServiceMode.call;
    final res = await FlutterForegroundTask.startService(
      serviceTypes: call ? [ForegroundServiceTypes.microphone, ForegroundServiceTypes.remoteMessaging] : [ForegroundServiceTypes.remoteMessaging],
      notificationTitle: 'MAMBA',
      notificationText: call ? 'Đang trong cuộc gọi thoại' : keepAliveNoticeText,
    );
    _current = res is ServiceRequestSuccess ? mode : ServiceMode.off;
  }
}
