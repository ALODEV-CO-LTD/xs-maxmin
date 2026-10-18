import 'dart:async';

enum PushKind { message, call, friendRequest }

class PushMessage {
  const PushMessage({required this.kind, required this.title, required this.body, required this.friendId});
  final PushKind kind;
  final String title;
  final String body;

  /// The id of the SENDER (the app opens /friends/chat/<friendId> on tap).
  final String friendId;

  /// The APNs JSON payload.
  Map<String, dynamic> toPayload() => {
        'aps': {
          'alert': {'title': title, 'body': body},
          'sound': 'default',
          'thread-id': friendId,
        },
        'friendId': friendId,
        'kind': kind.name,
      };
}

/// Sends a push to every iOS device registered for [userId].
abstract class PushSender {
  Future<void> send(String userId, PushMessage message);
}

class NoopPushSender implements PushSender {
  @override
  Future<void> send(String userId, PushMessage message) async {}
}

/// Sends to every device of the user through each platform's sender (each
/// sender only touches the tokens of its own platform). One failing sender
/// never prevents the others.
class CompositePushSender implements PushSender {
  CompositePushSender(this.senders);
  final List<PushSender> senders;

  @override
  Future<void> send(String userId, PushMessage message) async {
    await Future.wait([
      for (final s in senders) s.send(userId, message).catchError((Object _) {}),
    ]);
  }
}
