import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/src/security.dart';
import 'package:sqlite3/sqlite3.dart';

class FakeCtx extends Mock implements RequestContext {}

/// In-memory database with the real schema and users: `adm` (root admin), `u1`, `u2` (customers).
Database testDb() {
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

/// Calls a route handler as [userId] without any HTTP server. [body] may be a String (sent raw) or JSON-encodable.
Future<Response> callRoute(
  FutureOr<Response> Function(RequestContext) handler,
  Database db, {
  String userId = 'u1',
  String role = 'user',
  HttpMethod method = HttpMethod.post,
  Object? body,
  Map<String, String> headers = const {},
  String path = '/api/x',
}) async {
  final ctx = FakeCtx();
  final raw = body == null ? '' : (body is String ? body : jsonEncode(body));
  final req = Request(method.value, Uri.parse('http://localhost$path'), body: raw, headers: headers);
  when(() => ctx.request).thenReturn(req);
  when(() => ctx.read<Database>()).thenReturn(db);
  when(() => ctx.read<AuthTokenPayload?>()).thenReturn(AuthTokenPayload(userId: userId, role: role));
  return handler(ctx);
}

Future<Map<String, dynamic>> jsonBody(Response r) async => jsonDecode(await r.body()) as Map<String, dynamic>;
