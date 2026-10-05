import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Lets the user edit or delete a data entry they already saved.
Future<Response> onRequest(RequestContext context, String id) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  final existing = db.select(
    'SELECT * FROM data_entries WHERE id = ? AND user_id = ?',
    [id, auth.userId],
  );
  if (existing.isEmpty) {
    return Response.json(statusCode: 404, body: {'error': 'Không tìm thấy số liệu'});
  }

  if (context.request.method == HttpMethod.delete) {
    db.execute('DELETE FROM data_entries WHERE id = ? AND user_id = ?', [id, auth.userId]);
    // Deleting frees up the quota it used - mirrors how creating spends it,
    // and never goes below 0 even if data_used was already inconsistent.
    db.execute(
      'UPDATE users SET data_used = MAX(data_used - 1, 0) WHERE id = ?',
      [auth.userId],
    );
    return Response.json(body: {'ok': true});
  }

  if (context.request.method != HttpMethod.patch) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final row = existing.first;

  // Conflict check (offline sync): the client sends the `updatedAt` it last
  // saw as `baseUpdatedAt`. If the row changed since, answer 409 with the
  // current server copy unless the user chose to overwrite (`force: true`).
  final currentVersion = (row['updated_at'] ?? row['created_at']) as String;
  final baseUpdatedAt = (body['baseUpdatedAt'] as String?)?.trim();
  if (baseUpdatedAt != null && baseUpdatedAt.isNotEmpty && body['force'] != true && baseUpdatedAt != currentVersion) {
    return Response.json(
      statusCode: 409,
      body: {
        'error': 'Số liệu đã được sửa ở nơi khác',
        'conflict': true,
        'server': {
          'id': id,
          'customerName': row['customer_name'],
          'entryDate': row['entry_date'],
          'value': row['value'],
          'score': row['score'],
          'result': row['result'],
          'betType': row['bet_type'],
          'note': row['note'],
          'createdAt': row['created_at'],
          'updatedAt': currentVersion,
        },
      },
    );
  }

  final value = (body['value'] as String?)?.trim() ?? row['value'] as String;
  final customerName =
      (body['customerName'] as String?)?.trim() ?? row['customer_name'] as String?;
  if (value.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập số liệu'});
  }
  if (customerName == null || customerName.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tên khách hàng'});
  }

  String entryDate = row['entry_date'] as String;
  final requestedDate = (body['entryDate'] as String?)?.trim();
  if (requestedDate != null && requestedDate.isNotEmpty) {
    try {
      entryDate = DateTime.parse(requestedDate).toIso8601String().substring(0, 10);
    } catch (_) {
      return Response.json(statusCode: 400, body: {'error': 'Ngày không hợp lệ'});
    }
  }

  final score = body.containsKey('score')
      ? (body['score'] as String?)?.trim()
      : row['score'] as String?;
  final result = body.containsKey('result')
      ? (body['result'] as String?)?.trim()
      : row['result'] as String?;
  final betType = body.containsKey('betType')
      ? (body['betType'] as String?)?.trim()
      : row['bet_type'] as String?;
  final note = body.containsKey('note')
      ? (body['note'] as String?)?.trim()
      : row['note'] as String?;

  final updatedAt = DateTime.now().toUtc().toIso8601String();
  db.execute(
    '''
    UPDATE data_entries
    SET customer_name = ?, entry_date = ?, value = ?, score = ?, result = ?, bet_type = ?, note = ?, updated_at = ?
    WHERE id = ? AND user_id = ?
    ''',
    [customerName, entryDate, value, score, result, betType, note, updatedAt, id, auth.userId],
  );

  return Response.json(
    body: {
      'id': id,
      'customerName': customerName,
      'entryDate': entryDate,
      'value': value,
      'score': score,
      'result': result,
      'betType': betType,
      'note': note,
      'createdAt': row['created_at'],
      'updatedAt': updatedAt,
    },
  );
}
