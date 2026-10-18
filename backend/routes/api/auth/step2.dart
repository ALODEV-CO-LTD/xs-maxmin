import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/security.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// Step 2 of login: exchanges a pending token (from a step-1 login that
/// required a second password) plus the second password for a real access
/// token.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final read = await readJsonBody(context, authBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;

  if (!fieldsAreStrings(body, ['pendingToken', 'password'])) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
  }
  final pendingToken = body['pendingToken'] as String?;
  final password = body['password'] as String?;
  if (pendingToken == null || password == null || password.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Thiếu thông tin xác thực'});
  }

  final userId = verifyPendingSecondFactorToken(pendingToken);
  if (userId == null) return _expired();

  final db = context.read<Database>();
  final rows = db.select('SELECT * FROM users WHERE id = ?', [userId]);
  if (rows.isEmpty) {
    return Response.json(statusCode: 401, body: {'error': 'Tài khoản không tồn tại'});
  }

  final row = rows.first;
  // The pending token proves the login password was right, so saying "locked"
  // here reveals nothing new. An admin-locked account never gets a token.
  if (row['status'] == 'locked') {
    return Response.json(
      statusCode: 403,
      body: {'error': 'Tài khoản đã bị khoá. Vui lòng liên hệ quản trị viên.'},
    );
  }
  // Same counter as login (account+IP) so step 2 can't be brute-forced by
  // re-running step 1 - see routes/api/auth/login.dart.
  final username = row['username'] as String;
  final ip = clientIp(context);
  final wait = lockedSecondsLeft(db, username, ip);
  if (wait > 0) return lockedResponse(wait);
  final secondPasswordHash = row['second_password_hash'] as String?;
  if (secondPasswordHash != null && BCrypt.checkpw(password, secondPasswordHash)) {
    // The pending token is single-use: spent here, a replay gets 401.
    if (!spendPendingSecondFactorToken(pendingToken)) return _expired();
    clearLoginFailures(db, username, ip);
    final sessionId = createSession(db, userId, context);
    final token = issueToken(userId: userId, role: row['role'] as String, sessionId: sessionId);
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
    if (!spendPendingSecondFactorToken(pendingToken)) return _expired();
    return Response.json(body: {
      'stage': 'wipe_confirmation_required',
      'wipeToken': issuePendingWipeToken(userId),
    });
  }

  final lock = recordLoginFailure(db, username, ip, userId: userId);
  if (lock > 0) return lockedResponse(lock);
  return Response.json(statusCode: 401, body: {'error': 'Mật khẩu lớp hai không đúng'});
}

Response _expired() => Response.json(
      statusCode: 401,
      body: {'error': 'Phiên đăng nhập đã hết hạn, vui lòng đăng nhập lại'},
    );
