import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/package_plans.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// No longer applies a package instantly - the user must transfer money
/// manually first (bank info from `GET /api/me/payment-info`) and this
/// just records a *pending* request for an admin to confirm/reject (see
/// routes/api/admin/payment-requests/**). The actual package/quota grant
/// only happens on approval (`user_repo.dart`'s `applyApprovedPackage`).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final wireType = body['packageType'] as String?;
  PackageType? pkg;
  for (final p in PackageType.values) {
    if (p != PackageType.none && p.wireValue == wireType) {
      pkg = p;
      break;
    }
  }
  if (pkg == null) {
    return Response.json(statusCode: 400, body: {'error': 'Gói không hợp lệ'});
  }

  final self = loadSelfRow(context, auth.userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final db = context.read<Database>();
  final pending = db.select(
    "SELECT id FROM payment_requests WHERE user_id = ? AND status = 'pending'",
    [auth.userId],
  );
  if (pending.isNotEmpty) {
    return Response.json(
      statusCode: 409,
      body: {'error': 'Bạn đã có một yêu cầu đang chờ admin xác nhận'},
    );
  }

  final priceVnd = resolvedPriceVnd(db, pkg);
  final id = newId();
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    'INSERT INTO payment_requests (id, user_id, package_type, amount, status, created_at) '
    "VALUES (?, ?, ?, ?, 'pending', ?)",
    [id, auth.userId, pkg.wireValue, priceVnd, now],
  );

  return Response.json(
    statusCode: 201,
    body: {
      'id': id,
      'packageType': pkg.wireValue,
      'amount': priceVnd,
      'status': 'pending',
      'createdAt': now,
    },
  );
}
