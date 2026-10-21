import 'dart:convert';

import 'package:server/src/apns.dart';
import 'package:server/src/call_signaling.dart';
import 'package:server/src/payments.dart';
import 'package:server/src/push_notify.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Fake implements PushSender {
  final sent = <(String, PushMessage)>[];
  @override
  Future<void> send(String userId, PushMessage message) async => sent.add((userId, message));
}

class _Sink implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];
  @override
  void add(Object? data) => sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Chan extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  _Chan() : sink = _Sink();
  @override
  final _Sink sink;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  late _Fake fake;
  setUp(() {
    fake = _Fake();
    pushSender = fake;
  });
  tearDown(() => pushSender = null);

  test('the customer is online on two devices: both get the decision, nobody is pushed', () async {
    final reg = CallSignalingRegistry.instance;
    final a = _Chan(), b = _Chan();
    reg.register('pay-u1', a);
    reg.register('pay-u1', b);
    pushPaymentDecision('pay-u1', status: 'approved', reference: 'MB123');
    await Future<void>.delayed(Duration.zero);
    expect(a.sink.sent.single['type'], 'payment-decided');
    expect(b.sink.sent.single['status'], 'approved');
    expect(fake.sent, isEmpty);
    reg.unregister('pay-u1', a);
    reg.unregister('pay-u1', b);
  });

  test('the customer is offline: a push says the package was renewed (or not approved), nothing else', () async {
    pushPaymentDecision('pay-u2', status: 'approved', reference: 'MB124');
    pushPaymentDecision('pay-u3', status: 'rejected', reason: 'Sai nội dung', reference: 'MB125');
    await Future<void>.delayed(Duration.zero);
    expect(fake.sent, hasLength(2));
    final ok = fake.sent[0].$2;
    expect(fake.sent[0].$1, 'pay-u2');
    expect(ok.kind, PushKind.payment);
    expect(ok.body, 'Gói của bạn đã được gia hạn.');
    expect(ok.friendId, 'approved');
    final no = fake.sent[1].$2;
    expect(no.friendId, 'rejected');
    expect(jsonEncode(no.toPayload()), isNot(contains('Sai nội dung'))); // the reason stays in the app, never in a push
    expect(ok.toPayload()['kind'], 'payment');
  });
}
