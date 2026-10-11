import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:server/src/apns.dart';
import 'package:server/src/fcm.dart';
import 'package:server/src/push_notify.dart';
import 'package:server/src/push_tokens.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

// Test-only RSA-2048 key pair (generated for this file; NOT a real Google key).
const _priv = '''-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDiemZgGFP0A4EN
3LMG5Om2xPRC+4m5qXTN5l7G2nvxtB/oGdQeiuo+mp/k7RaBLHdjvQyeXokNRYRY
RKh5JbUfcydrDRztmcsJt+7tbEl5fvQNmsKnMb3tPkRCNXrRQXNrl748XGLMO2Tw
fflVEz+mb7gqQfSuI1W6XT2y3G6B0DIfhlq2XOcCICueQIZYmackxL9wd0dBbMBH
M3ur/faw/TpMnHTcU9ySSJcPqBcPLXzuxFjL473DOW+FlObRWvtfASDF3lK7eWS4
zjp5n0my5frk4gYljddiyteMr3UWThb+LDh1qrCKgMbzIAdFZGC5ResHNjWIEW3Y
LeZItJZRAgMBAAECggEBANyRnrEKIIFvBDpO7mDRgrkJGmc9+UVDv0lkinuaf8nH
xqdSuF7Cph4wk3buXNOTTfdqQCbhJRMy2BDrVTUfv0WQ7hv5WmohNTgS1fSPWQOl
2+SADAGvlSzATtQ4p5Oy7ckksRayV1pWohkCZ1ku9PeQqMknETijmzN06ckPm+R5
3XhaHNtzi4/SeuECTXl/yLivf0RrxsokYulJXd1dtRP+AUafhNt+UpX6fRwxdvXt
i7sJOF3XCXn2xo0+TidhFQ31Ti/QGHX5XfmQfyKbtbUAMMroY1p5SFHZU3KiWSZU
uIr01LDoHQ/YZM/w79mC7X5nk9Wy4ycRuW05F0Y/4t0CgYEA+W0/7nwblugVYPWj
pZzayf85Clbm0eOCQKJct1GtKOZ/M75I4oPHnglZmtaZUEcqK9QOM6B13hJBlJiT
J0eYvFxzctPqjqIoAtwRgFC0eLStecy1DB2nSs3mJcNb7QCG0zYBeqPu4wJ2ckl0
An/51UgApYNfZr7tzS1Y1OPS8VsCgYEA6HJT8UXfd+ZbuDb/OMWr3hyENhrbCQOo
ye0OmfBwbG7aLHKoDuDjPTbQtQDuhESXeH0MrXAQqyhC+u2hC5KqeN2/ni2ThVAa
SRl+3XufFh7+ZFs6bIp7pyxHrD9j55rEMWbJRoKDIkCpXbCZhHh2CB9FzM24TEHN
RKehK29imsMCgYAfNk2ewUcOjkJGnNZ6nfM+/cIcih1ePHMLNYYWppDdomJejjw+
pDDxlMfyuVH8GrurOmEAkt7NCEnOl30qmCoDwCnuP5iFesM5AGLsRK0gwbNHn5c0
Se2qTbO0HAs/0CYO/h4XQ7ZcD+3UhV6QBYW068qw64yfpdrKJxeLpGq8KwKBgQDB
193S3h8uwQcKB6stMANUtdk3uYuh59BRnIRJse4/Lu54lKE7zyURvm2sFHvUB9N9
YmM5G7R615eL5LEhkozhQKN0iLN2QEe7YCyhDV+steoVzNJbA918mvumVDK/SRyF
yh7d0ycCYIQdIpHTnBVqTpIJ6iDgTxucPmK0cy36uwKBgGbLk9l+UbKZ0Gf/Mwzq
UMg/NXz5MoFnjxXWxruuIAVAkQfm78p+G7D4lYLGuRDWRRjNQ+M4Q5lU714miu9M
PwlJXGy1F9kqPLmjU5gyqGiTX1QbqxSXMHu+5r+SWhtepp7SvT81jPTKaOKzIL74
5Rr/WegAShxbgmqMtvju6oZX
-----END PRIVATE KEY-----''';
const _pub = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA4npmYBhT9AOBDdyzBuTp
tsT0QvuJual0zeZextp78bQf6BnUHorqPpqf5O0WgSx3Y70Mnl6JDUWEWESoeSW1
H3Mnaw0c7ZnLCbfu7WxJeX70DZrCpzG97T5EQjV60UFza5e+PFxizDtk8H35VRM/
pm+4KkH0riNVul09stxugdAyH4ZatlznAiArnkCGWJmnJMS/cHdHQWzARzN7q/32
sP06TJx03FPckkiXD6gXDy187sRYy+O9wzlvhZTm0Vr7XwEgxd5Su3lkuM46eZ9J
suX65OIGJY3XYsrXjK91Fk4W/iw4daqwioDG8yAHRWRguUXrBzY1iBFt2C3mSLSW
UQIDAQAB
-----END PUBLIC KEY-----''';

// Test-only P-256 key (not a real Apple key), for the composite test.
const _ecKey = '''-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgMa63r5HmM/R2Tkyk
r+qn7kwQ/hG88iAnactjsneAQLShRANCAAQOL1yXywSuat3rkkPH2ZV7BNQKpZ/C
y9TAlkKbATPhqf70VC1JC4mN/ifmUGQ2Lp31Jbcw9vv5slOZa0Q5tKG/
-----END PRIVATE KEY-----''';

final _tok = 'A1_-:' * 30; // 150 chars, mixed case, URL-safe
final _tok2 = 'Zz9:' * 40; // 160 chars

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON');
  db.execute(File('schema.sql').readAsStringSync());
  db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('u1','u1','U1','x','user',0,'2026-01-01')");
  upsertPushToken(db, 'u1', 'android', _tok);
  upsertPushToken(db, 'u1', 'android', _tok2);
  return db;
}

final _cfg = FcmConfig(clientEmail: 'svc@proj.iam.gserviceaccount.com', privateKeyPem: _priv, tokenUri: 'https://oauth2.example.test/token', projectId: 'proj-1');
const _msgCall = PushMessage(kind: PushKind.call, title: 'Cuộc gọi đến', body: 'An đang gọi bạn', friendId: 'f1');
const _msgText = PushMessage(kind: PushKind.message, title: 'An', body: 'Đang nhắn tin cho bạn. Mở MAMBA để nhận.', friendId: 'f1');

FcmHttpResponse _tokenOk() => FcmHttpResponse(200, jsonEncode({'access_token': 'ya29.test', 'expires_in': 3600}));
bool _isSend(FcmHttpRequest r) => r.url.host == 'fcm.googleapis.com';

void main() {
  test('token validation per platform; case preserved for android', () {
    expect(isValidFcmToken(_tok), true);
    expect(isValidFcmToken('a' * 99), false);
    expect(isValidFcmToken('a' * 401), false);
    expect(isValidFcmToken('${'a' * 100}!'), false);
    expect(isValidPushTokenFor('android', _tok), true);
    expect(isValidPushTokenFor('ios', _tok), false);
    expect(isValidPushTokenFor('ios', 'ab' * 32), true);
    expect(isValidPushTokenFor('web', _tok), false);
    final db = _db();
    expect(pushTokensOf(db, 'u1', platform: 'android'), unorderedEquals([_tok, _tok2]));
    expect(pushTokensOf(db, 'u1', platform: 'ios'), isEmpty);
    expect(deletePushToken(db, _tok.toLowerCase()), false); // exact match only
    expect(deletePushToken(db, _tok, userId: 'u1'), true);
  });

  test('migration upgrades an iOS-only push_tokens table keeping rows; idempotent', () {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON');
    db.execute("CREATE TABLE users (id TEXT PRIMARY KEY)");
    db.execute("INSERT INTO users VALUES ('u1')");
    db.execute('''CREATE TABLE push_tokens (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      platform TEXT NOT NULL CHECK (platform IN ('ios')), token TEXT NOT NULL UNIQUE,
      device_label TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    db.execute('CREATE INDEX idx_push_tokens_user ON push_tokens(user_id)');
    upsertPushToken(db, 'u1', 'ios', 'ab' * 32, deviceLabel: 'iPhone');
    ensurePushTokensTable(db);
    ensurePushTokensTable(db);
    expect(pushTokensOf(db, 'u1'), ['ab' * 32]);
    upsertPushToken(db, 'u1', 'android', _tok);
    expect(pushTokensOf(db, 'u1', platform: 'android'), [_tok]);
    expect(() => db.execute("INSERT INTO push_tokens VALUES ('x','u1','web','t','l','a','b')"), throwsA(anything));
    db.execute("DELETE FROM users WHERE id = 'u1'");
    expect(pushTokensOf(db, 'u1'), isEmpty);
  });

  test('assertion is RS256 with the right claims and verifies', () {
    final now = DateTime.utc(2026, 1, 1, 12);
    final s = FcmSender(config: _cfg, db: _db, transport: (_) async => _tokenOk(), clock: () => now);
    final t = s.signedAssertion();
    final parts = t.split('.');
    Map<String, dynamic> j(String p) => jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(p)))) as Map<String, dynamic>;
    expect(j(parts[0])['alg'], 'RS256');
    final c = j(parts[1]);
    expect(c['iss'], _cfg.clientEmail);
    expect(c['scope'], 'https://www.googleapis.com/auth/firebase.messaging');
    expect(c['aud'], _cfg.tokenUri);
    expect(c['iat'], now.millisecondsSinceEpoch ~/ 1000);
    expect(c['exp'], now.millisecondsSinceEpoch ~/ 1000 + 3600);
    JWT.verify(t, RSAPublicKey(_pub), checkExpiresIn: false);
    final forged = '${parts[0]}.${parts[1]}.${parts[2].split('').reversed.join()}';
    expect(() => JWT.verify(forged, RSAPublicKey(_pub), checkExpiresIn: false), throwsA(anything));
  });

  test('token exchange request shape; access token cached until 5 min before expiry', () async {
    var now = DateTime.utc(2026, 1, 1, 12);
    final reqs = <FcmHttpRequest>[];
    final db = _db();
    final s = FcmSender(
      config: _cfg,
      db: () => db,
      clock: () => now,
      transport: (r) async {
        reqs.add(r);
        return _isSend(r) ? const FcmHttpResponse(200, '{}') : _tokenOk();
      },
    );
    await s.send('u1', _msgText);
    final ex = reqs.first;
    expect(ex.url.toString(), _cfg.tokenUri);
    expect(ex.headers['content-type'], 'application/x-www-form-urlencoded');
    final form = Uri.splitQueryString(ex.body);
    expect(form['grant_type'], 'urn:ietf:params:oauth:grant-type:jwt-bearer');
    JWT.verify(form['assertion']!, RSAPublicKey(_pub), checkExpiresIn: false);
    expect(reqs, hasLength(3)); // 1 exchange + 2 sends

    now = now.add(const Duration(minutes: 54));
    await s.send('u1', _msgText);
    expect(reqs.where((r) => !_isSend(r)), hasLength(1));
    now = now.add(const Duration(minutes: 2));
    await s.send('u1', _msgText);
    expect(reqs.where((r) => !_isSend(r)), hasLength(2));
  });

  test('message JSON: endpoint, bearer, channels, ttl, privacy', () async {
    final reqs = <FcmHttpRequest>[];
    final db = _db();
    final s = FcmSender(
      config: _cfg,
      db: () => db,
      transport: (r) async {
        reqs.add(r);
        return _isSend(r) ? const FcmHttpResponse(200, '{}') : _tokenOk();
      },
    );
    await s.send('u1', _msgCall);
    await s.send('u1', _msgText);
    final sends = reqs.where(_isSend).toList();
    expect(sends, hasLength(4));
    expect(sends.first.url.toString(), 'https://fcm.googleapis.com/v1/projects/proj-1/messages:send');
    expect(sends.first.headers['authorization'], 'Bearer ya29.test');
    final call = jsonDecode(sends.first.body) as Map<String, dynamic>;
    expect(call.keys.toSet(), {'message'});
    final m = call['message'] as Map<String, dynamic>;
    expect({_tok, _tok2}, contains(m['token']));
    expect(m['notification'], {'title': 'Cuộc gọi đến', 'body': 'An đang gọi bạn'});
    expect(m['data'], {'friendId': 'f1', 'kind': 'call'});
    expect(m['android'], {
      'priority': 'HIGH',
      'ttl': '30s',
      'notification': {'channel_id': 'mamba_calls', 'sound': 'default'},
    });
    expect(m.keys.toSet(), {'token', 'notification', 'data', 'android'});
    final text = (jsonDecode(sends[2].body) as Map)['message'] as Map<String, dynamic>;
    expect((text['android'] as Map)['ttl'], '3600s');
    expect(((text['android'] as Map)['notification'] as Map)['channel_id'], 'mamba_messages');
    expect(text['data'], {'friendId': 'f1', 'kind': 'message'});
  });

  test('UNREGISTERED / 404 / invalid token delete the token; other errors keep it', () async {
    final db = _db();
    FcmSender mk(FcmHttpResponse Function(FcmHttpRequest) f) =>
        FcmSender(config: _cfg, db: () => db, transport: (r) async => _isSend(r) ? f(r) : _tokenOk());
    await mk((r) {
      final token = (jsonDecode(r.body)['message'] as Map)['token'];
      return token == _tok
          ? FcmHttpResponse(404, jsonEncode({'error': {'code': 404, 'status': 'NOT_FOUND', 'details': [{'errorCode': 'UNREGISTERED'}]}}))
          : FcmHttpResponse(400, jsonEncode({'error': {'code': 400, 'status': 'INVALID_ARGUMENT', 'message': 'The registration token is not a valid FCM registration token'}}));
    }).send('u1', _msgText);
    expect(pushTokensOf(db, 'u1'), isEmpty);

    upsertPushToken(db, 'u1', 'android', _tok);
    await mk((_) => const FcmHttpResponse(400, '{"error":{"status":"INVALID_ARGUMENT","message":"Invalid JSON payload"}}')).send('u1', _msgText);
    await mk((_) => const FcmHttpResponse(503, 'x')).send('u1', _msgText);
    await FcmSender(config: _cfg, db: () => db, transport: (_) async => throw const SocketException('x')).send('u1', _msgText);
    expect(pushTokensOf(db, 'u1'), [_tok]);
  });

  test('config from env; no config => no-op; composite sends per platform', () async {
    expect(FcmConfig.fromEnv({}), isNull);
    expect(FcmConfig.fromEnv({'XOSO_FCM_CREDENTIALS_PATH': '/nonexistent'}), isNull);
    final dir = Directory.systemTemp.createTempSync('fcm_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bad = File('${dir.path}/bad.json')..writeAsStringSync('{"client_email":"a"}');
    expect(FcmConfig.fromEnv({'XOSO_FCM_CREDENTIALS_PATH': bad.path}), isNull);
    final f = File('${dir.path}/sa.json')..writeAsStringSync(jsonEncode({'client_email': 'svc@x', 'private_key': _priv, 'project_id': 'from-json'}));
    final c = FcmConfig.fromEnv({'XOSO_FCM_CREDENTIALS_PATH': f.path})!;
    expect(c.projectId, 'from-json');
    expect(c.tokenUri, 'https://oauth2.googleapis.com/token');
    expect(FcmConfig.fromEnv({'XOSO_FCM_CREDENTIALS_PATH': f.path, 'XOSO_FCM_PROJECT_ID': 'over'})!.projectId, 'over');

    expect(buildPushSender({}, () => _db()), isA<NoopPushSender>());
    expect(buildPushSender({'XOSO_FCM_CREDENTIALS_PATH': f.path}, () => _db()), isA<FcmSender>());

    final db = _db();
    upsertPushToken(db, 'u1', 'ios', 'ab' * 32);
    final apnsKey = File('${dir.path}/a.p8')..writeAsStringSync(_ecKey);
    final apnsReqs = <ApnsRequest>[];
    final fcmReqs = <FcmHttpRequest>[];
    final s = buildPushSender(
      {'XOSO_FCM_CREDENTIALS_PATH': f.path, 'XOSO_APNS_KEY_PATH': apnsKey.path, 'XOSO_APNS_KEY_ID': 'k', 'XOSO_APNS_TEAM_ID': 't'},
      () => db,
      transport: (r) async {
        apnsReqs.add(r);
        return const ApnsResponse(200);
      },
      fcmTransport: (r) async {
        fcmReqs.add(r);
        return _isSend(r) ? const FcmHttpResponse(200, '{}') : _tokenOk();
      },
    );
    expect(s, isA<CompositePushSender>());
    await s.send('u1', _msgText);
    expect(apnsReqs.map((r) => r.token), ['ab' * 32]);
    expect(fcmReqs.where(_isSend), hasLength(2));
  });

  test('throttle is once per (sender, recipient, kind) across platforms', () async {
    final sent = <String>[];
    final db = _db();
    upsertPushToken(db, 'u1', 'ios', 'ab' * 32);
    pushSender = CompositePushSender([
      FcmSender(
        config: _cfg,
        db: () => db,
        transport: (r) async {
          if (_isSend(r)) sent.add('fcm');
          return _isSend(r) ? const FcmHttpResponse(200, '{}') : _tokenOk();
        },
      ),
      ApnsSender(
        config: const ApnsConfig(keyPem: _ecKey, keyId: 'k', teamId: 't', topic: 'x', sandbox: true),
        db: () => db,
        transport: (_) async {
          sent.add('apns');
          return const ApnsResponse(200);
        },
      ),
    ]);
    addTearDown(() => pushSender = null);
    pushThrottle = PushThrottle();
    for (var i = 0; i < 3; i++) {
      notifyOfflineRecipient(kind: PushKind.message, fromUserId: 'a', fromName: 'An', toUserId: 'u1');
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(sent..sort(), ['apns', 'fcm', 'fcm']);
  });
}
