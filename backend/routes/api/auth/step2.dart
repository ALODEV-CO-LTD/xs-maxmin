import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/security.dart';
import 'package:sqlite3/sqlite3.dart';

/// Step 2 of login: exchanges a pending token (from a step-1 login that
/// required a second password) plus the second password for a real access
/// token.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final pendingToken = body['pendingToken'] as String?;
  final password = body['password'] as String?;
  if (pendingToken == null || password == null || password.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu thông tin xác thực'});
  }

  final userId = verifyPendingSecondFactorToken(pendingToken);
  if (userId == null) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại'},
    );
  }

  final db = context.read<Database>();
  final rows = db.select('SELECT * FROM users WHERE id = ?', [userId]);
  if (rows.isEmpty) {
    return Response.json(statusCode: 401, body: {'error': 'Tài khoản không tồn tại'});
  }

  final row = rows.first;
  final secondPasswordHash = row['second_password_hash'] as String?;
  if (secondPasswordHash != null && BCrypt.checkpw(password, secondPasswordHash)) {
    final token = issueToken(userId: userId, role: row['role'] as String);
    return Response.json(body: {'token': token, 'role': row['role']});
  }

  // Not the second-layer password either - same single field also accepts
  // the account's wipe-password, so the user only ever has one extra
  // prompt to remember instead of two. As with step 1, this never logs the
  // caller in and never deletes anything by itself: it only hands back a
  // short-lived token that the app must show an explicit confirmation for
  // before calling `/api/auth/confirm-wipe`.
  final wipePasswordHash = row['wipe_password_hash'] as String?;
  if (wipePasswordHash != null && BCrypt.checkpw(password, wipePasswordHash)) {
    return Response.json(body: {
      'stage': 'wipe_confirmation_required',
      'wipeToken': issuePendingWipeToken(userId),
    });
  }

  return Response.json(statusCode: 401, body: {'error': 'Mật khẩu lớp hai không đúng'});
}
