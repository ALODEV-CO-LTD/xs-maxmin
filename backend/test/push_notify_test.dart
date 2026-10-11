import 'dart:convert';

import 'package:server/src/apns.dart';
import 'package:server/src/push_notify.dart';
import 'package:test/test.dart';

class _Fake implements PushSender {
  final sent = <(String, PushMessage)>[];
  @override
  Future<void> send(String userId, PushMessage message) async => sent.add((userId, message));
}

void main() {
  late _Fake fake;
  var now = DateTime.utc(2026, 1, 1);
  setUp(() {
    fake = _Fake();
    pushSender = fake;
    now = DateTime.utc(2026, 1, 1);
    pushThrottle = PushThrottle(clock: () => now);
  });
  tearDown(() => pushSender = null);

  test('message and call texts, only sender name + kind', () async {
    notifyOfflineRecipient(kind: PushKind.message, fromUserId: 'a', fromName: 'An', toUserId: 'b');
    notifyOfflineRecipient(kind: PushKind.call, fromUserId: 'a', fromName: 'An', toUserId: 'b');
    await Future<void>.delayed(Duration.zero);
    expect(fake.sent, hasLength(2));
    final m = fake.sent[0].$2;
    expect(fake.sent[0].$1, 'b');
    expect((m.toPayload()['aps'] as Map)['alert'], {'title': 'An', 'body': 'Đang nhắn tin cho bạn. Mở MAMBA để nhận.'});
    final c = fake.sent[1].$2;
    expect((c.toPayload()['aps'] as Map)['alert'], {'title': 'Cuộc gọi đến', 'body': 'An đang gọi bạn'});
    expect(jsonEncode(m.toPayload()).contains('ct'), false);
  });

  test('throttle: 1 per (sender, recipient, kind) per 60s', () async {
    void msg(String from, String to) => notifyOfflineRecipient(kind: PushKind.message, fromUserId: from, fromName: 'X', toUserId: to);
    msg('a', 'b');
    msg('a', 'b');
    msg('a', 'c');
    msg('d', 'b');
    notifyOfflineRecipient(kind: PushKind.call, fromUserId: 'a', fromName: 'X', toUserId: 'b');
    await Future<void>.delayed(Duration.zero);
    expect(fake.sent, hasLength(4));
    now = now.add(const Duration(seconds: 59));
    msg('a', 'b');
    await Future<void>.delayed(Duration.zero);
    expect(fake.sent, hasLength(4));
    now = now.add(const Duration(seconds: 2));
    msg('a', 'b');
    await Future<void>.delayed(Duration.zero);
    expect(fake.sent, hasLength(5));
  });

  test('a failing sender never throws into the caller', () async {
    pushSender = _Boom();
    notifyOfflineRecipient(kind: PushKind.call, fromUserId: 'a', fromName: 'X', toUserId: 'b');
    await Future<void>.delayed(Duration.zero);
  });
}

class _Boom implements PushSender {
  @override
  Future<void> send(String userId, PushMessage message) => throw StateError('boom');
}
