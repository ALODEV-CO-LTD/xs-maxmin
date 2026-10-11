import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:server/src/apns.dart';
import 'package:server/src/push_tokens.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

// Test-only P-256 key pair (generated for this file; not a real Apple key).
const _priv = '''-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgMa63r5HmM/R2Tkyk
r+qn7kwQ/hG88iAnactjsneAQLShRANCAAQOL1yXywSuat3rkkPH2ZV7BNQKpZ/C
y9TAlkKbATPhqf70VC1JC4mN/ifmUGQ2Lp31Jbcw9vv5slOZa0Q5tKG/
-----END PRIVATE KEY-----''';
const _pub = '''-----BEGIN PUBLIC KEY-----
MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEDi9cl8sErmrd65JDx9mVewTUCqWf
wsvUwJZCmwEz4an+9FQtSQuJjf4n5lBkNi6d9SW3MPb7+bJTmWtEObShvw==
-----END PUBLIC KEY-----''';

final _tok = 'ab' * 32;
final _tok2 = 'cd' * 32;

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON');
  db.execute(File('schema.sql').readAsStringSync());
  db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('u1','u1','U1','x','user',0,'2026-01-01')");
  upsertPushToken(db, 'u1', 'ios', _tok);
  upsertPushToken(db, 'u1', 'ios', _tok2);
  return db;
}

const _cfg = ApnsConfig(keyPem: _priv, keyId: 'KEY1234567', teamId: 'MKG3V4B3M7', topic: 'vn.mamba.mambaApp', sandbox: true);

void main() {
  test('JWT is ES256 with kid, iss/iat, verifies against the public key, cached 50 min', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final s = ApnsSender(config: _cfg, db: _db, transport: (_) async => const ApnsResponse(200), clock: () => now);
    final t = s.providerToken();
    final parts = t.split('.');
    Map<String, dynamic> j(String p) => jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(p)))) as Map<String, dynamic>;
    expect(j(parts[0])['alg'], 'ES256');
    expect(j(parts[0])['kid'], 'KEY1234567');
    expect(j(parts[1])['iss'], 'MKG3V4B3M7');
    expect(j(parts[1])['iat'], now.millisecondsSinceEpoch ~/ 1000);
    final verified = JWT.verify(t, ECPublicKey(_pub));
    expect((verified.payload as Map)['iss'], 'MKG3V4B3M7');
    expect(() => JWT.verify(t, ECPublicKey(_pub.replaceFirst('MFkw', 'MFkx'))), throwsA(anything));

    now = now.add(const Duration(minutes: 49));
    expect(s.providerToken(), t);
    now = now.add(const Duration(minutes: 2));
    expect(s.providerToken(), isNot(t));
  });

  test('payload and headers: privacy, priority, expiration, topic; sandbox flag', () async {
    final sent = <ApnsRequest>[];
    final now = DateTime.utc(2026, 1, 1);
    final db = _db();
    final s2 = ApnsSender(config: _cfg, db: () => db, transport: (r) async { sent.add(r); return const ApnsResponse(200); }, clock: () => now);
    await s2.send('u1', const PushMessage(kind: PushKind.call, title: 'Cuộc gọi đến', body: 'An đang gọi bạn', friendId: 'f1'));
    await s2.send('u1', const PushMessage(kind: PushKind.message, title: 'An', body: 'Đang nhắn tin cho bạn. Mở MAMBA để nhận.', friendId: 'f1'));
    expect(sent, hasLength(4));
    final call = sent.first;
    expect(call.sandbox, true);
    expect(call.headers['apns-priority'], '10');
    expect(call.headers['apns-push-type'], 'alert');
    expect(call.headers['apns-topic'], 'vn.mamba.mambaApp');
    expect(call.headers['apns-expiration'], '${now.millisecondsSinceEpoch ~/ 1000 + 30}');
    expect(sent[2].headers['apns-expiration'], '${now.millisecondsSinceEpoch ~/ 1000 + 3600}');
    final body = jsonDecode(utf8.decode(call.body)) as Map<String, dynamic>;
    expect(body['kind'], 'call');
    expect(body['friendId'], 'f1');
    expect((body['aps'] as Map)['thread-id'], 'f1');
    expect((body['aps'] as Map)['sound'], 'default');
    expect(body.keys.toSet(), {'aps', 'friendId', 'kind'});
    expect((body['aps'] as Map).keys.toSet(), {'alert', 'sound', 'thread-id'});
  });

  test('410 / BadDeviceToken / Unregistered delete the token; other errors keep it', () async {
    final db = _db();
    final replies = {_tok: const ApnsResponse(410), _tok2: const ApnsResponse(400, 'BadDeviceToken')};
    final s = ApnsSender(config: _cfg, db: () => db, transport: (r) async => replies[r.token]!);
    const m = PushMessage(kind: PushKind.message, title: 'A', body: 'b', friendId: 'f');
    await s.send('u1', m);
    expect(pushTokensOf(db, 'u1'), isEmpty);

    upsertPushToken(db, 'u1', 'ios', _tok);
    await ApnsSender(config: _cfg, db: () => db, transport: (_) async => const ApnsResponse(400, 'Unregistered')).send('u1', m);
    expect(pushTokensOf(db, 'u1'), isEmpty);

    upsertPushToken(db, 'u1', 'ios', _tok);
    await ApnsSender(config: _cfg, db: () => db, transport: (_) async => const ApnsResponse(503, 'ServiceUnavailable')).send('u1', m);
    await ApnsSender(config: _cfg, db: () => db, transport: (_) async => throw const SocketException('x')).send('u1', m);
    expect(pushTokensOf(db, 'u1'), [_tok]);
  });

  test('no config => no-op sender; config from env', () {
    expect(ApnsConfig.fromEnv({}), isNull);
    expect(ApnsConfig.fromEnv({'XOSO_APNS_KEY_PATH': '/nonexistent', 'XOSO_APNS_KEY_ID': 'k', 'XOSO_APNS_TEAM_ID': 't'}), isNull);
    expect(buildPushSender({}, () => _db()), isA<NoopPushSender>());
    final f = File('${Directory.systemTemp.path}/apns_test_${DateTime.now().microsecondsSinceEpoch}.p8')..writeAsStringSync(_priv);
    addTearDown(f.deleteSync);
    final c = ApnsConfig.fromEnv({'XOSO_APNS_KEY_PATH': f.path, 'XOSO_APNS_KEY_ID': 'k', 'XOSO_APNS_TEAM_ID': 't', 'XOSO_APNS_SANDBOX': 'true'})!;
    expect(c.topic, 'vn.mamba.mambaApp');
    expect(c.sandbox, true);
    expect(buildPushSender({'XOSO_APNS_KEY_PATH': f.path, 'XOSO_APNS_KEY_ID': 'k', 'XOSO_APNS_TEAM_ID': 't'}, () => _db()), isA<ApnsSender>());
  });
}
