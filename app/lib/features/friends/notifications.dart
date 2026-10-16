import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NoticeKind { message, incomingCall, missedCall, support }

/// One Android notification, described without any plugin types so it can be tested.
///
/// Messages are end-to-end encrypted: a notification is shown by the OS (and readable on the lock screen), so it must
/// never carry the text of a message. [messageNotice] only takes the sender's name.
class NoticeContent {
  const NoticeContent({required this.kind, required this.id, required this.title, required this.body, required this.payload, this.inApp = false});
  final NoticeKind kind;
  final int id;
  final String title;
  final String body;
  final String payload;

  /// Incoming call while the app is on screen: rings like a call but does not pop up over the call screen.
  final bool inApp;

  @override
  String toString() => 'NoticeContent($kind, $title / $body, $payload)';
}

/// Stable positive 31-bit id for a friend (String.hashCode changes between runs).
int noticeIdFor(String text) {
  var h = 0x811c9dc5;
  for (final c in text.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0x7fffffff;
  }
  return 1000 + h % 1000000;
}

const incomingCallNoticeId = 7001;
const supportNoticeId = 7002;
const keepAliveNoticeText = 'Đang giữ kết nối để nhận tin nhắn và cuộc gọi';

String _shortName(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'bạn bè';
  return n.length > 40 ? '${n.substring(0, 40)}…' : n;
}

NoticeContent messageNotice(String friendId, String friendName) => NoticeContent(
      kind: NoticeKind.message,
      id: noticeIdFor('msg:$friendId'),
      title: 'MAMBA',
      body: 'Tin nhắn mới từ ${_shortName(friendName)}',
      payload: 'chat:$friendId',
    );

NoticeContent incomingCallNotice(String friendId, String friendName, {bool inApp = false}) => NoticeContent(
      kind: NoticeKind.incomingCall,
      id: incomingCallNoticeId,
      title: 'Cuộc gọi thoại đến',
      body: '${_shortName(friendName)} đang gọi cho bạn',
      payload: 'call:$friendId',
      inApp: inApp,
    );

NoticeContent missedCallNotice(String friendId, String friendName) => NoticeContent(
      kind: NoticeKind.missedCall,
      id: noticeIdFor('missed:$friendId'),
      title: 'Cuộc gọi nhỡ',
      body: 'Cuộc gọi nhỡ từ ${_shortName(friendName)}',
      payload: 'missed:$friendId',
    );

NoticeContent supportNotice() => const NoticeContent(
      kind: NoticeKind.support,
      id: supportNoticeId,
      title: 'MAMBA',
      body: 'Có phản hồi mới từ Admin',
      payload: 'support',
    );

/// What a tapped notification points at.
class NoticeTarget {
  const NoticeTarget(this.kind, [this.friendId]);
  final NoticeKind kind;
  final String? friendId;
}

NoticeTarget? parseNoticePayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  if (payload == 'support') return const NoticeTarget(NoticeKind.support);
  final i = payload.indexOf(':');
  if (i < 0) return null;
  final id = payload.substring(i + 1);
  if (id.isEmpty) return null;
  return switch (payload.substring(0, i)) {
    'chat' => NoticeTarget(NoticeKind.message, id),
    'missed' => NoticeTarget(NoticeKind.missedCall, id),
    'call' => NoticeTarget(NoticeKind.incomingCall, id),
    _ => null,
  };
}

/// Where a tap goes (go_router location), or null to just show the app (an incoming call is answered in the call
/// overlay that sits above every screen).
String? routeForTarget(NoticeTarget t) => switch (t.kind) {
      NoticeKind.message || NoticeKind.missedCall => '/friends/chat/${Uri.encodeComponent(t.friendId ?? '')}',
      NoticeKind.support => '/support',
      NoticeKind.incomingCall => null,
    };

/// What the app does when a message arrives: nothing while that chat is open on screen; the in-app banner while the
/// app is on screen showing something else; an OS notification when the app is in the background.
enum MessageAlert { none, banner, notification }

MessageAlert alertForMessage({required bool foreground, required String? openPeer, required String friendId}) {
  if (foreground) return openPeer == friendId ? MessageAlert.none : MessageAlert.banner;
  return MessageAlert.notification;
}

/// Port the app talks to; [LocalNotifier] is the Android implementation.
abstract class AppNotifier {
  Future<void> init({required void Function(String? payload) onTap});

  /// Asks for POST_NOTIFICATIONS (Android 13+). True when notifications are allowed.
  Future<bool> requestPermission();
  Future<bool> get allowed;
  Future<void> show(NoticeContent content);
  Future<void> cancel(int id);
  Future<void> cancelAll();

  /// Payload of the notification that started the app, if any.
  Future<String?> launchPayload();
}

class NoopNotifier implements AppNotifier {
  const NoopNotifier();
  @override
  Future<void> init({required void Function(String? payload) onTap}) async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<bool> get allowed async => false;
  @override
  Future<void> show(NoticeContent content) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> cancelAll() async {}
  @override
  Future<String?> launchPayload() async => null;
}

// `mamba_messages` and `mamba_calls` are also the channel ids the server names in its FCM messages (backend/lib/src/fcm.dart),
// so the OS-drawn push notifications use these channels. They must exist before the first push arrives: created at start-up.
const _msgChannel = 'mamba_messages';
const _pushCallChannel = 'mamba_calls';
const _callChannel = 'mamba_calls_incoming_v2';
const _callChannelInApp = 'mamba_calls_incoming_inapp';
const _missedChannel = 'mamba_calls_missed';

/// flutter_local_notifications on Android.
class LocalNotifier implements AppNotifier {
  LocalNotifier([FlutterLocalNotificationsPlugin? plugin]) : _p = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _p;
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init({required void Function(String? payload) onTap}) async {
    try {
      await _p.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
        onDidReceiveNotificationResponse: (r) => onTap(r.payload),
      );
      final a = _android;
      await a?.createNotificationChannel(const AndroidNotificationChannel(_msgChannel, 'Tin nhắn mới', description: 'Báo có tin nhắn mới (không hiện nội dung tin nhắn)', importance: Importance.high));
      // FCM "incoming call" push (app closed): rings with the phone's ringtone.
      await a?.createNotificationChannel(AndroidNotificationChannel(
        _pushCallChannel,
        'Cuộc gọi đến (khi đóng app)',
        description: 'Báo có cuộc gọi đến khi MAMBA đang đóng',
        importance: Importance.max,
        sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        vibrationPattern: Int64List.fromList([0, 800, 700, 800, 700, 800]),
      ));
      await a?.createNotificationChannel(const AndroidNotificationChannel(_missedChannel, 'Cuộc gọi nhỡ', description: 'Báo cuộc gọi nhỡ', importance: Importance.high));
      await a?.createNotificationChannel(AndroidNotificationChannel(
        _callChannelInApp,
        'Cuộc gọi đến (khi đang mở app)',
        description: 'Đổ chuông khi có cuộc gọi đến lúc bạn đang dùng MAMBA',
        importance: Importance.defaultImportance,
        sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        vibrationPattern: Int64List.fromList([0, 800, 700, 800, 700, 800]),
      ));
      await a?.createNotificationChannel(AndroidNotificationChannel(
        _callChannel,
        'Cuộc gọi đến',
        description: 'Đổ chuông khi có cuộc gọi thoại đến',
        importance: Importance.max,
        sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
        vibrationPattern: Int64List.fromList([0, 800, 700, 800, 700, 800]),
      ));
      _ready = true;
    } catch (e) {
      debugPrint('notifications init failed: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> get allowed async {
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  AndroidNotificationDetails _details(NoticeContent c) {
    switch (c.kind) {
      case NoticeKind.incomingCall:
        if (c.inApp) {
          return AndroidNotificationDetails(
            _callChannelInApp,
            'Cuộc gọi đến (khi đang mở app)',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            category: AndroidNotificationCategory.call,
            ongoing: true,
            autoCancel: false,
            timeoutAfter: 35000,
            visibility: NotificationVisibility.private,
            audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
            additionalFlags: Int32List.fromList([4]),
            vibrationPattern: Int64List.fromList([0, 800, 700, 800, 700, 800]),
          );
        }
        return AndroidNotificationDetails(
          _callChannel,
          'Cuộc gọi đến',
          channelDescription: 'Đổ chuông khi có cuộc gọi thoại đến',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          timeoutAfter: 35000,
          visibility: NotificationVisibility.private,
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          // FLAG_INSISTENT (4): repeat the ringtone until the notification is cancelled.
          additionalFlags: Int32List.fromList([4]),
          vibrationPattern: Int64List.fromList([0, 800, 700, 800, 700, 800]),
        );
      case NoticeKind.missedCall:
        return const AndroidNotificationDetails(_missedChannel, 'Cuộc gọi nhỡ', importance: Importance.high, priority: Priority.high, category: AndroidNotificationCategory.missedCall, visibility: NotificationVisibility.private);
      case NoticeKind.message:
      case NoticeKind.support:
        return const AndroidNotificationDetails(_msgChannel, 'Tin nhắn mới', importance: Importance.high, priority: Priority.high, category: AndroidNotificationCategory.message, visibility: NotificationVisibility.private);
    }
  }

  @override
  Future<void> show(NoticeContent content) async {
    if (!_ready) return;
    try {
      await _p.show(id: content.id, title: content.title, body: content.body, notificationDetails: NotificationDetails(android: _details(content)), payload: content.payload);
    } catch (e) {
      debugPrint('notification failed: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _p.cancel(id: id);
    } catch (_) {/* nothing to cancel */}
  }

  @override
  Future<void> cancelAll() async {
    try {
      await _p.cancelAll();
    } catch (_) {/* nothing to cancel */}
  }

  @override
  Future<String?> launchPayload() async {
    try {
      final d = await _p.getNotificationAppLaunchDetails();
      return d?.didNotificationLaunchApp == true ? d?.notificationResponse?.payload : null;
    } catch (_) {
      return null;
    }
  }
}
