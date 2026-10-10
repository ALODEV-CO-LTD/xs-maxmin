import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/phone.dart';
import 'package:sqlite3/sqlite3.dart';

/// Removes a customer from the roster - only removes them from the
/// picklist EntriesView reads; their historical data_entries rows (which
/// store the name as plain text, not a foreign key) are untouched and
/// still show up everywhere as before.
///
/// PATCH { phone } -> sets (or clears, with '') the customer's phone number.
Future<Response> onRequest(RequestContext context, String id) async {
  final method = context.request.method;
  if (method != HttpMethod.delete && method != HttpMethod.patch) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  final existing = db.select(
    'SELECT id FROM customers WHERE id = ? AND user_id = ?',
    [id, auth.userId],
  );
  if (existing.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy khách hàng'});
  }

  if (method == HttpMethod.patch) {
    final Map<String, dynamic> body;
    try {
      body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
    } catch (_) {
      return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
    }
    final phone = normalizePhone(body['phone']);
    if (phone == null) {
      return Response.json(statusCode: 400, body: {'error': 'Số điện thoại không hợp lệ'});
    }
    db.execute('UPDATE customers SET phone = ? WHERE id = ? AND user_id = ?', [phone, id, auth.userId]);
    return Response.json(body: {'id': id, 'phone': phone});
  }

  db.execute('DELETE FROM customers WHERE id = ? AND user_id = ?', [id, auth.userId]);
  return Response.json(body: {'ok': true});
}
