import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Per-customer entry-syntax templates (K16) used by EntriesView's "Nhập từ
/// tin nhắn". A template is only ever saved when the user confirms it - the
/// server never infers one from their data.
///
/// GET  -> { templates: [{ id, customerName, config, updatedAt }] }
/// POST { customerName, config: {...} } -> upsert for that customer
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final db = context.read<Database>();

  switch (context.request.method) {
    case HttpMethod.get:
      final rows = db.select(
        'SELECT * FROM customer_syntax_templates WHERE user_id = ? ORDER BY customer_name',
        [auth.userId],
      );
      return Response.json(body: {'templates': [for (final r in rows) _json(r)]});
    case HttpMethod.post:
      final read = await readJsonBody(context, smallBodyMaxBytes);
      if (read.error != null) return read.error!;
      final body = read.body!;
      final customerName = (body['customerName'] as String?)?.trim() ?? '';
      final config = body['config'];
      if (customerName.isEmpty || config is! Map) {
        return Response.json(statusCode: 400, body: {'error': 'Thiếu khách hàng hoặc mẫu cú pháp'});
      }
      final encoded = jsonEncode(config);
      if (encoded.length > 4000) {
        return Response.json(statusCode: 400, body: {'error': 'Mẫu cú pháp quá dài'});
      }
      final now = DateTime.now().toUtc().toIso8601String();
      db.execute(
        'INSERT INTO customer_syntax_templates (id, user_id, customer_name, config, updated_at) VALUES (?, ?, ?, ?, ?) '
        'ON CONFLICT(user_id, customer_name) DO UPDATE SET config = excluded.config, updated_at = excluded.updated_at',
        [newId(), auth.userId, customerName, encoded, now],
      );
      final row = db.select(
        'SELECT * FROM customer_syntax_templates WHERE user_id = ? AND customer_name = ?',
        [auth.userId, customerName],
      ).first;
      return Response.json(body: _json(row));
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}

Map<String, Object?> _json(Row r) => {
      'id': r['id'],
      'customerName': r['customer_name'],
      'config': jsonDecode(r['config'] as String),
      'updatedAt': r['updated_at'],
    };
