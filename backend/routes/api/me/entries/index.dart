import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _list(context, auth.userId),
    HttpMethod.post => _create(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _list(RequestContext context, String userId) {
  final db = context.read<Database>();
  final rows = db.select(
    'SELECT * FROM data_entries WHERE user_id = ? ORDER BY entry_date DESC, created_at DESC LIMIT 200',
    [userId],
  );
  return Response.json(
    body: {
      'entries': [
        for (final r in rows)
          {
            'id': r['id'],
            'customerName': r['customer_name'],
            'entryDate': r['entry_date'],
            'value': r['value'],
            'score': r['score'],
            'result': r['result'],
            'betType': r['bet_type'],
            'note': r['note'],
            'createdAt': r['created_at'],
          },
      ],
    },
  );
}

Future<Response> _create(RequestContext context, String userId) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final value = (body['value'] as String?)?.trim();
  final note = (body['note'] as String?)?.trim();
  final customerName = (body['customerName'] as String?)?.trim();
  final score = (body['score'] as String?)?.trim();
  final result = (body['result'] as String?)?.trim();
  final betType = (body['betType'] as String?)?.trim();
  if (value == null || value.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập số liệu'});
  }
  if (customerName == null || customerName.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tên khách hàng'});
  }

  final now = DateTime.now().toUtc();
  final requestedDate = (body['entryDate'] as String?)?.trim();
  String entryDate;
  if (requestedDate == null || requestedDate.isEmpty) {
    entryDate = now.toIso8601String().substring(0, 10);
  } else {
    try {
      entryDate = DateTime.parse(requestedDate).toIso8601String().substring(0, 10);
    } catch (_) {
      return Response.json(statusCode: 400, body: {'error': 'Ngày không hợp lệ'});
    }
  }

  final self = loadSelfRow(context, userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final expiresAt = self['package_expires_at'] as String?;
  final isActive =
      expiresAt != null && DateTime.parse(expiresAt).isAfter(DateTime.now().toUtc());
  if (!isActive) {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Gói đã hết hạn, vui lòng gia hạn để tiếp tục nhập số liệu'},
    );
  }

  final quotaTotal = self['data_quota_total'] as int;
  final quotaUsed = self['data_used'] as int;
  if (quotaUsed >= quotaTotal) {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Đã dùng hết số liệu của gói hiện tại'},
    );
  }

  final db = context.read<Database>();
  final id = newId();
  final createdAt = now.toIso8601String();
  db.execute(
    '''
    INSERT INTO data_entries (id, user_id, customer_name, entry_date, value, score, result, bet_type, note, created_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [id, userId, customerName, entryDate, value, score, result, betType, note, createdAt],
  );
  db.execute('UPDATE users SET data_used = data_used + 1 WHERE id = ?', [userId]);

  return Response.json(
    statusCode: 201,
    body: {
      'id': id,
      'customerName': customerName,
      'entryDate': entryDate,
      'value': value,
      'score': score,
      'result': result,
      'betType': betType,
      'note': note,
      'createdAt': createdAt,
    },
  );
}
