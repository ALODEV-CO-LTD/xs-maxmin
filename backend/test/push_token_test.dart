import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/src/push_tokens.dart';
import 'package:server/src/security.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/me/push-token.dart' as route;

class _Ctx extends Mock implements RequestContext {}

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON');
  db.execute(File('schema.sql').readAsStringSync());
  for (final u in [('u1', 'user'), ('u2', 'user'), ('adm', 'admin')]) {
    db.execute(
      'INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) '
      "VALUES (?, ?, ?, 'x', ?, 0, '2026-01-01')",
      [u.$1, 'name${u.$1}', 'U ${u.$1}', u.$2],
    );
  }
  return db;
}

final _tok = 'ab' * 32; // 64 hex chars
final _tok2 = 'cd' * 32;

Future<Response> _call(Database db, String userId, HttpMethod method, Object? body, {String role = 'user'}) {
  final ctx = _Ctx();
  final req = Request(method.value, Uri.parse('http://localhost/api/me/push-token'), body: body is String ? body : jsonEncode(body));
  when(() => ctx.request).thenReturn(req);
  when(() => ctx.read<Database>()).thenReturn(db);
  when(() => ctx.read<AuthTokenPayload?>()).thenReturn(AuthTokenPayload(userId: userId, role: role));
  return Future.value(route.onRequest(ctx));
}

List<Row> _rows(Database db) => db.select('SELECT * FROM push_tokens ORDER BY token').toList();

void main() {
  test('POST registers, re-POST updates, another account moves the token', () async {
    final db = _db();
    var r = await _call(db, 'u1', HttpMethod.post, {'platform': 'ios', 'token': _tok, 'deviceLabel': 'iPhone A'});
    expect(r.statusCode, 200);
    expect(_rows(db), hasLength(1));
    r = await _call(db, 'u1', HttpMethod.post, {'platform': 'ios', 'token': _tok, 'deviceLabel': 'iPhone B'});
    expect(r.statusCode, 200);
    expect(_rows(db).single['device_label'], 'iPhone B');
    r = await _call(db, 'u2', HttpMethod.post, {'platform': 'ios', 'token': _tok});
    expect(r.statusCode, 200);
    expect(_rows(db).single['user_id'], 'u2');
    expect(pushTokensOf(db, 'u1'), isEmpty);
    expect(pushTokensOf(db, 'u2'), [_tok]);
  });

  test('validation', () async {
    final db = _db();
    for (final bad in [
      {'platform': 'ios', 'token': 'abc'},
      {'platform': 'ios', 'token': 'zz' * 32},
      {'platform': 'ios', 'token': 'a' * 201},
      {'platform': 'ios'},
      {'platform': 'android', 'token': _tok},
      {'platform': 'ios', 'token': _tok, 'deviceLabel': 5},
    ]) {
      expect((await _call(db, 'u1', HttpMethod.post, bad)).statusCode, 400, reason: '$bad');
    }
    expect((await _call(db, 'u1', HttpMethod.post, '{nope')).statusCode, 400);
    expect((await _call(db, 'u1', HttpMethod.get, {})).statusCode, 405);
    expect(_rows(db), isEmpty);
  });

  test('DELETE removes only own token', () async {
    final db = _db();
    await _call(db, 'u1', HttpMethod.post, {'platform': 'ios', 'token': _tok});
    await _call(db, 'u2', HttpMethod.post, {'platform': 'ios', 'token': _tok2});
    var r = await _call(db, 'u2', HttpMethod.delete, {'token': _tok});
    expect(r.statusCode, 200);
    expect(_rows(db), hasLength(2));
    r = await _call(db, 'u1', HttpMethod.delete, {'token': _tok});
    expect(jsonDecode(await r.body())['removed'], true);
    expect(_rows(db).single['user_id'], 'u2');
  });

  test('admin accounts are forbidden, unauthenticated is 401', () async {
    final db = _db();
    final r = await _call(db, 'adm', HttpMethod.post, {'platform': 'ios', 'token': _tok}, role: 'admin');
    expect(r.statusCode, 403);
    expect(_rows(db), isEmpty);

    final ctx = _Ctx();
    when(() => ctx.request).thenReturn(Request('POST', Uri.parse('http://localhost/x'), body: '{}'));
    when(() => ctx.read<Database>()).thenReturn(db);
    when(() => ctx.read<AuthTokenPayload?>()).thenReturn(null);
    expect((await route.onRequest(ctx)).statusCode, 401);
  });

  test('tokens are removed when the account is deleted', () async {
    final db = _db();
    await _call(db, 'u1', HttpMethod.post, {'platform': 'ios', 'token': _tok});
    db.execute("DELETE FROM users WHERE id = 'u1'");
    expect(_rows(db), isEmpty);
  });
}
