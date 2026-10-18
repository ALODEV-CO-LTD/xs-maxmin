import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/customer_codes.dart';
import 'package:server/src/database.dart';
import 'package:server/src/rate_gate.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _list(context, auth.userId),
    HttpMethod.post => await _create(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _list(RequestContext context, String userId) {
  final db = context.read<Database>();
  final rows = db.select(
    'SELECT * FROM customer_codes WHERE user_id = ? ORDER BY created_at DESC',
    [userId],
  );
  return Response.json(
    body: {
      // `maxCodes` is Admin's per-account cap (settings.max_virtual_ids).
      'maxCodes': maxCustomerCodes(db),
      'codes': [
        for (final r in rows)
          {'id': r['id'], 'code': r['code'], 'label': r['label'], 'createdAt': r['created_at']},
      ],
    },
  );
}

/// Creates a Mã ID. Body (all optional): `code` - digits the customer picked
/// themselves (length, duplicates and too-guessable runs are rejected),
/// otherwise a random unique one is generated; `label` - a short note.
/// Refused once the account holds Admin's maximum number of IDs.
Future<Response> _create(RequestContext context, String userId) async {
  final db = context.read<Database>();
  Map<String, dynamic> body = {};
  final raw = await context.request.body();
  if (raw.trim().isNotEmpty) {
    try {
      body = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
    }
  }

  final max = maxCustomerCodes(db);
  final count = db.select('SELECT COUNT(*) AS n FROM customer_codes WHERE user_id = ?', [userId]).first['n'] as int;
  if (count >= max) {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Bạn đã đạt giới hạn $max mã ID. Hãy xoá bớt một mã trước khi tạo mã mới.'},
    );
  }

  // `label` / `code` must be strings (a number etc. is a 400, not a 500).
  final rawLabel = body['label'];
  final rawCode = body['code'];
  if ((rawLabel != null && rawLabel is! String) || (rawCode != null && rawCode is! String)) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ: mã và nhãn phải là chuỗi'});
  }
  final label = (rawLabel as String?)?.trim();
  if (label != null && label.length > 40) {
    return Response.json(statusCode: 400, body: {'error': 'Nhãn tối đa 40 ký tự'});
  }

  final String code;
  final wanted = (rawCode as String?)?.trim();
  if (wanted != null && wanted.isNotEmpty) {
    final problem = validateCustomCode(wanted);
    if (problem != null) return Response.json(statusCode: 400, body: {'error': problem});
    // "Is this number taken?" tells a guesser which IDs exist, exactly like the add-friend lookup does, so it shares
    // that lookup's throttle: every 409 below counts as a failed guess, and a locked caller gets the same 429.
    final locked = checkFriendAddLock(context, userId);
    if (locked != null) return locked;
    if (db.select('SELECT 1 FROM customer_codes WHERE code = ?', [wanted]).isNotEmpty) {
      recordFriendAddFailure(context, userId);
      return Response.json(statusCode: 409, body: {'error': 'Mã ID này đã có người dùng, hãy chọn dãy số khác'});
    }
    // Quarantine after deletion: only the previous owner may take the number back.
    final retired = retiredCodeConflict(db, wanted, userId);
    if (retired != null) {
      recordFriendAddFailure(context, userId);
      return Response.json(statusCode: 409, body: {'error': retired});
    }
    code = wanted;
  } else {
    code = generateUniqueCustomerCode(db);
  }

  final id = newId();
  final now = DateTime.now().toUtc().toIso8601String();
  final cleanLabel = (label == null || label.isEmpty) ? null : label;
  db.execute(
    'INSERT INTO customer_codes (id, user_id, code, label, created_at) VALUES (?, ?, ?, ?, ?)',
    [id, userId, code, cleanLabel, now],
  );
  // The previous owner has taken their number back: the reservation is over.
  db.execute('DELETE FROM retired_codes WHERE code = ? AND user_id = ?', [code, userId]);
  return Response.json(statusCode: 201, body: {'id': id, 'code': code, 'label': cleanLabel, 'createdAt': now});
}
