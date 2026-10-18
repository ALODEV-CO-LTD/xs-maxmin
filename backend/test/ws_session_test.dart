import 'dart:io';

import 'package:server/src/call_signaling.dart';
import 'package:server/src/push_tokens.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Sink implements WebSocketSink {
  final sent = <String>[];
  int? closeCode;
  @override
  void add(Object? data) => sent.add(data as String);
  @override
  Future<void> close([int? closeCode, String? closeReason]) {
    this.closeCode = closeCode;
    return Future.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Chan extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  @override
  final _Sink sink = _Sink();
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON');
  db.execute(File('schema.sql').readAsStringSync());
  db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('u1','n1','U','x','user',0,'2026-01-01')");
  for (final s in ['s1', 's2']) {
    db.execute("INSERT INTO device_sessions (id, user_id, device_label, created_at, last_seen) VALUES ('$s','u1','d','2026-01-01','2026-01-01')");
  }
  return db;
}

void main() {
  group('parseSignalFrame', () {
    test('non-string fields never throw', () {
      for (final raw in ['{"to":5}', '{"type":[]}', '{"to":null,"type":{"a":1},"reason":7}', '[]', '"x"', 'nope', 12, null]) {
        expect(() => parseSignalFrame(raw, maxChars: 1000), returnsNormally, reason: '$raw');
      }
      final f = parseSignalFrame('{"to":5,"type":"offer","reason":3}', maxChars: 1000)!;
      expect(f.to, isNull);
      expect(f.type, 'offer');
      expect(f.reason, isNull);
      expect(parseSignalFrame('[1]', maxChars: 1000), isNull);
      expect(parseSignalFrame('{"to":"a"}', maxChars: 5), isNull);
      expect(parseSignalFrame('{"to":"a","type":"ice"}', maxChars: 1000)!.to, 'a');
    });
  });

  group('revocation closes sockets and push tokens', () {
    test("revokeSession closes only that session's socket and drops its push token", () {
      final db = _db();
      final reg = CallSignalingRegistry.instance;
      final a = _Chan(), b = _Chan();
      reg.register('u1', a, sessionId: 's1');
      reg.register('u1', b, sessionId: 's2');
      upsertPushToken(db, 'u1', 'ios', 'ab' * 32, sessionId: 's1');
      upsertPushToken(db, 'u1', 'ios', 'cd' * 32, sessionId: 's2');
      expect(revokeSession(db, 'u1', 's1', by: 'u1'), isTrue);
      expect(a.sink.closeCode, 4401);
      expect(b.sink.closeCode, isNull);
      expect(pushTokensOf(db, 'u1'), ['cd' * 32]);
      reg.unregister('u1', b);
    });

    test('revokeAllSessions closes everything except the kept session', () {
      final db = _db();
      final reg = CallSignalingRegistry.instance;
      final a = _Chan(), b = _Chan();
      reg.register('u1', a, sessionId: 's1');
      reg.register('u1', b, sessionId: 's2');
      upsertPushToken(db, 'u1', 'ios', 'ab' * 32, sessionId: 's1');
      upsertPushToken(db, 'u1', 'ios', 'cd' * 32, sessionId: 's2');
      revokeAllSessions(db, 'u1', by: 'u1', exceptSessionId: 's2');
      expect(a.sink.closeCode, 4401);
      expect(b.sink.closeCode, isNull);
      expect(pushTokensOf(db, 'u1'), ['cd' * 32]);
      revokeAllSessions(db, 'u1', by: 'admin');
      expect(b.sink.closeCode, 4401);
      expect(reg.isOnline('u1'), isFalse);
      expect(pushTokensOf(db, 'u1'), isEmpty);
    });
  });
}
