import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/security.dart';
import 'package:sqlite3/sqlite3.dart';

/// Step 1 of login: verifies username + primary password. If the account
/// has a second-layer password configured, this does NOT issue an access
/// token - it returns a short-lived pending token that only unlocks
/// `/api/auth/step2` (see that route), so the caller still needs the
/// second password before they can reach any user data.
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

  final username = (body['username'] as String?)?.trim();
  final password = body['password'] as String?;
  if (username == null ||
      username.isEmpty ||
      password == null ||
      password.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Vui lòng nhập tên đăng nhập và mật khẩu'},
    );
  }

  final db = context.read<Database>();
  final rows = db.select('SELECT * FROM users WHERE username = ?', [username]);
  if (rows.isEmpty) {
    return Response.json(
      statusCode: 401,
      body: {'error': 'Tên đăng nhập hoặc mật khẩu không đúng'},
    );
  }

  final row = rows.first;
  if (row['status'] == 'locked') {
    // Set by an admin via PATCH /api/admin/users/:id (see that route) -
    // blocks login entirely regardless of password correctness.
    return Response.json(
      statusCode: 403,
      body: {'error': 'Tài khoản đã bị khoá. Vui lòng liên hệ quản trị viên.'},
    );
  }
  final passwordHash = row['password_hash'] as String;
  final secondPasswordHash = row['second_password_hash'] as String?;
  if (!BCrypt.checkpw(password, passwordHash)) {
    // Not the login password. If this account has a second-layer password,
    // the wipe-password is checked there instead (routes/api/auth/step2.dart)
    // - same single prompt the user already types their second password
    // into, rather than a second place to remember. Only accounts with no
    // second-layer password (so there is no step 2 to check it in) fall
    // back to checking it here.
    if (secondPasswordHash == null) {
      final wipePasswordHash = row['wipe_password_hash'] as String?;
      if (wipePasswordHash != null &&
          BCrypt.checkpw(password, wipePasswordHash)) {
        return Response.json(
          body: {
            'stage': 'wipe_confirmation_required',
            'wipeToken': issuePendingWipeToken(row['id'] as String),
          },
        );
      }
    }
    return Response.json(
      statusCode: 401,
      body: {'error': 'Tên đăng nhập hoặc mật khẩu không đúng'},
    );
  }

  final userId = row['id'] as String;
  if (secondPasswordHash != null) {
    return Response.json(
      body: {
        'stage': 'second_password_required',
        'pendingToken': issuePendingSecondFactorToken(userId),
      },
    );
  }

  final token = issueToken(userId: userId, role: row['role'] as String);
  return Response.json(
    body: {
      'stage': 'done',
      'token': token,
      'role': row['role'],
    },
  );
}
