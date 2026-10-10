import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// End-to-end encryption identity (docs/MA_HOA_2_DAU.md). The browser/app makes
/// an ECDH P-256 key pair and keeps the private half on the device; only the
/// PUBLIC half (JWK) is stored here so friends can encrypt to it.
///
/// `GET` -> `{publicKey: {...}|null}`, `PUT {publicKey: {kty:'EC', crv:'P-256', x, y}}`
/// publishes/replaces it (a new device or a cleared browser makes a new key, and
/// friends are told the key changed).
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final db = context.read<Database>();

  if (context.request.method == HttpMethod.get) {
    final rows = db.select('SELECT e2ee_public_key FROM users WHERE id = ?', [auth.userId]);
    final raw = rows.isEmpty ? null : rows.first['e2ee_public_key'] as String?;
    return Response.json(body: {'publicKey': raw == null ? null : jsonDecode(raw)});
  }
  if (context.request.method != HttpMethod.put) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }
  final key = normalizePublicKey(body['publicKey']);
  if (key == null) {
    return Response.json(statusCode: 400, body: {'error': 'Khoá công khai không hợp lệ'});
  }
  db.execute('UPDATE users SET e2ee_public_key = ? WHERE id = ?', [jsonEncode(key), auth.userId]);
  return Response.json(body: {'publicKey': key});
}

/// Keeps only the public fields of an EC P-256 JWK; null if it is not one.
/// Never accepts a private part (`d`).
Map<String, String>? normalizePublicKey(Object? raw) {
  if (raw is! Map) return null;
  final x = raw['x'];
  final y = raw['y'];
  if (raw['kty'] != 'EC' || raw['crv'] != 'P-256' || x is! String || y is! String) return null;
  final b64 = RegExp(r'^[A-Za-z0-9_-]{40,50}$');
  if (!b64.hasMatch(x) || !b64.hasMatch(y)) return null;
  return {'kty': 'EC', 'crv': 'P-256', 'x': x, 'y': y};
}
