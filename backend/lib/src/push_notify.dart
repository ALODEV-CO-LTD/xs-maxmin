import 'dart:async';

import 'package:server/src/apns.dart';

/// At most one push per (sender, recipient, kind) per [window], in memory.
class PushThrottle {
  PushThrottle({this.window = const Duration(seconds: 60), DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final Duration window;
  final DateTime Function() _clock;
  final Map<String, DateTime> _last = {};

  /// True (and records it) if a push may go out now.
  bool allow(String from, String to, PushKind kind) {
    final now = _clock();
    _last.removeWhere((_, t) => now.difference(t) >= window);
    final key = '$from|$to|${kind.name}';
    if (_last.containsKey(key)) return false;
    _last[key] = now;
    return true;
  }
}

PushThrottle pushThrottle = PushThrottle();

/// Wakes an OFFLINE recipient. Fire-and-forget: never throws, never delays or
/// changes the reply the sender gets. Only the sender's display name and the
/// kind are used - never any message content.
void notifyOfflineRecipient({
  required PushKind kind,
  required String fromUserId,
  required String fromName,
  required String toUserId,
}) {
  if (!pushThrottle.allow(fromUserId, toUserId, kind)) return;
  final message = kind == PushKind.call
      ? PushMessage(kind: kind, title: 'Cuộc gọi đến', body: '$fromName đang gọi bạn', friendId: fromUserId)
      : PushMessage(kind: kind, title: fromName, body: 'Đang nhắn tin cho bạn. Mở MAMBA để nhận.', friendId: fromUserId);
  try {
    unawaited(pushSender.send(toUserId, message).catchError((Object _) {}));
  } catch (_) {}
}
