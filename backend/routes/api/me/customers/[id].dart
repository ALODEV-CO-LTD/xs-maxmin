import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/phone.dart';
import 'package:server/src/scoring_rates.dart';
import 'package:sqlite3/sqlite3.dart';

/// Removes a customer from the roster - only removes them from the
/// picklist EntriesView reads; their historical data_entries rows (which
/// store the name as plain text, not a foreign key) are untouched and
/// still show up everywhere as before.
///
/// PATCH { phone?, scoringRates? } -> sets (or clears, with '' / null) the customer's phone
/// number and/or their own scoring config.
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
    // Each field is optional and only the ones present are changed.
    final reply = <String, dynamic>{'id': id};
    if (body.containsKey('phone')) {
      final phone = normalizePhone(body['phone']);
      if (phone == null) {
        return Response.json(statusCode: 400, body: {'error': 'Số điện thoại không hợp lệ'});
      }
      db.execute('UPDATE customers SET phone = ? WHERE id = ? AND user_id = ?', [phone, id, auth.userId]);
      reply['phone'] = phone;
    }
    if (body.containsKey('scoringRates')) {
      // null / {} = follow the account's settings again; otherwise this customer's own overrides.
      final raw = body['scoringRates'];
      final (rates, error) = raw == null ? (const <String, dynamic>{}, null) : normalizeRatesMap(raw, allowEmpty: true);
      if (error != null) return Response.json(statusCode: 400, body: {'error': error});
      db.execute(
        'UPDATE customers SET scoring_rates = ? WHERE id = ? AND user_id = ?',
        [rates!.isEmpty ? null : jsonEncode(rates), id, auth.userId],
      );
      reply['scoringRates'] = rates.isEmpty ? null : rates;
    }
    return Response.json(body: reply);
  }

  db.execute('DELETE FROM customers WHERE id = ? AND user_id = ?', [id, auth.userId]);
  return Response.json(body: {'ok': true});
}
