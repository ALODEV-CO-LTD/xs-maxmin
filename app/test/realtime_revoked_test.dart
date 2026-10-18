import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Ch implements WebSocketChannel {
  _Ch(this.code);
  final int? code;
  final ctl = StreamController<dynamic>();
  @override
  int? get closeCode => code;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
  @override
  Stream<dynamic> get stream => ctl.stream;
  @override
  WebSocketSink get sink => _Sink();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? st]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async {}
  @override
  Future get done => Future.value();
}

void main() {
  test('close code 4401 signs out and does not reconnect', () async {
    var dials = 0;
    var revoked = 0;
    late _Ch ch;
    final s = RealtimeSocket(
      tokenProvider: () => 't',
      delay: (_) => const Duration(milliseconds: 5),
      factory: (_) {
        dials++;
        return ch = _Ch(4401);
      },
    )..onSessionRevoked = () => revoked++;
    s.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await ch.ctl.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(revoked, 1);
    expect(dials, 1);
    expect(s.wanted, false);
    s.dispose();
  });

  test('other close codes still reconnect', () async {
    var dials = 0;
    final chans = <_Ch>[];
    final s = RealtimeSocket(
      tokenProvider: () => 't',
      delay: (_) => const Duration(milliseconds: 5),
      factory: (_) {
        dials++;
        final c = _Ch(1006);
        chans.add(c);
        return c;
      },
    );
    s.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await chans.first.ctl.close();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(dials, greaterThan(1));
    s.dispose();
  });
}
