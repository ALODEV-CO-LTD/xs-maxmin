import 'dart:convert';

import 'package:server/src/call_signaling.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Sink implements WebSocketSink {
  final sent = <String>[];
  bool broken = false;
  @override
  void add(Object? data) {
    if (broken) throw StateError('closed');
    sent.add(data as String);
  }

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
  test('chat frames reach every open connection of a user; calls keep using the newest one', () {
    final reg = CallSignalingRegistry.instance;
    final a = _Chan();
    final b = _Chan();
    reg.register('fan-u1', a);
    reg.register('fan-u1', b);
    expect(reg.connectionCount('fan-u1'), 2);

    expect(reg.sendToAll('fan-u1', {'type': 'e2ee-ack', 'id': 'x'}), isTrue);
    expect(a.sink.sent.length, 1);
    expect(b.sink.sent.length, 1);
    expect(jsonDecode(b.sink.sent.single)['type'], 'e2ee-ack');

    reg.sendTo('fan-u1', {'type': 'call-invite'}); // calls: only the newest connection
    expect(a.sink.sent.length, 1);
    expect(b.sink.sent.length, 2);
  });

  test('a closed connection is dropped; the user stays online while one is left, and is offline after the last', () {
    final reg = CallSignalingRegistry.instance;
    final a = _Chan();
    final b = _Chan();
    reg.register('fan-u2', a);
    reg.register('fan-u2', b);
    b.sink.broken = true;
    expect(reg.sendToAll('fan-u2', {'type': 'e2ee-msg', 'id': 'm1'}), isTrue); // a still takes it
    expect(reg.connectionCount('fan-u2'), 1);
    expect(reg.isOnline('fan-u2'), isTrue);

    reg.unregister('fan-u2', a);
    expect(reg.isOnline('fan-u2'), isFalse);
    expect(reg.sendToAll('fan-u2', {'type': 'e2ee-msg', 'id': 'm2'}), isFalse); // nobody: "offline"
  });

  test('closing the newest connection falls calls back to the previous one', () {
    final reg = CallSignalingRegistry.instance;
    final a = _Chan();
    final b = _Chan();
    reg.register('fan-u3', a);
    reg.register('fan-u3', b);
    reg.unregister('fan-u3', b);
    expect(reg.sendTo('fan-u3', {'type': 'call-invite'}), isTrue);
    expect(a.sink.sent.length, 1);
  });
}
