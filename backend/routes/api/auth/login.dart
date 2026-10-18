import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/security.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// Step 1 of login: verifies username + primary password. If the account
/// has a second-layer password configured, this does NOT issue an access
/// token - it returns a short-lived pending token that only unlocks
/// `/api/auth/step2` (see that route), so the caller still needs the
/// second password before they can reach any user data.
///
/// Account enumeration: an unknown username is checked against a dummy bcrypt
/// hash so it takes as long as a wrong password, and "tài khoản bị khoá" is
/// only said AFTER the password was right - a wrong password on a locked
/// account gets the same generic 401 as any other account.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final read = await readJsonBody(context, authBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;

  if (!fieldsAreStrings(body, ['username', 'password'])) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
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
  // K03/S03: too many wrong tries for this account+IP => temporary lock with
  // growing backoff. Checked first, before any password work, and the reply
  // is generic (never says which field was wrong). Nothing is deleted.
  final ip = clientIp(context);
  final wait = lockedSecondsLeft(db, username, ip);
  if (wait > 0) return lockedResponse(wait);

  final rows = db.select('SELECT * FROM users WHERE username = ?', [username]);
  final row = rows.isEmpty ? null : rows.first;
  final passwordHash = row == null ? dummyPasswordHash : row['password_hash'] as String;
  final secondPasswordHash = row?['second_password_hash'] as String?;
  // Always exactly one bcrypt here, whether or not the account exists.
  final passwordOk = BCrypt.checkpw(password, passwordHash);
  if (row == null || !passwordOk) {
    // Not the login password. If this account has no second-layer password
    // (so there is no step 2 to check it in) the wipe-password is checked
    // here instead - see routes/api/auth/step2.dart for the other case.
    // A second bcrypt runs on EVERY failure (against a dummy when there is no
    // wipe hash) so timing does not reveal whether the account exists / has one.
    final wipePasswordHash = row?['wipe_password_hash'] as String?;
    final checkWipe = row != null && secondPasswordHash == null && wipePasswordHash != null;
    final wipeOk = BCrypt.checkpw(password, checkWipe ? wipePasswordHash : dummyPasswordHash) && checkWipe;
    if (row != null && wipeOk) {
      if (row['status'] == 'locked') return _lockedAccount();
      return Response.json(
        body: {
          'stage': 'wipe_confirmation_required',
          'wipeToken': issuePendingWipeToken(row['id'] as String),
        },
      );
    }
    return _loginFailed(db, username, ip, row?['id'] as String?);
  }

  // Password was right: only now is it safe to say the account is locked
  // (set by an admin via PATCH /api/admin/users/:id) - blocks login entirely.
  if (row['status'] == 'locked') return _lockedAccount();

  final userId = row['id'] as String;
  if (secondPasswordHash != null) {
    return Response.json(
      body: {
        'stage': 'second_password_required',
        'pendingToken': issuePendingSecondFactorToken(userId),
      },
    );
  }

  clearLoginFailures(db, username, ip);
  final sessionId = createSession(db, userId, context);
  final token = issueToken(userId: userId, role: row['role'] as String, sessionId: sessionId);
  return Response.json(
    body: {
      'stage': 'done',
      'token': token,
      'role': row['role'],
    },
  );
}

Response _lockedAccount() => Response.json(
      statusCode: 403,
      body: {'error': 'Tài khoản đã bị khoá. Vui lòng liên hệ quản trị viên.'},
    );

/// Counts the wrong attempt and answers with the same generic message
/// whichever field was wrong (or 429 if this attempt triggered a lock).
Response _loginFailed(Database db, String username, String ip, String? userId) {
  final lock = recordLoginFailure(db, username, ip, userId: userId);
  if (lock > 0) return lockedResponse(lock);
  return Response.json(
    statusCode: 401,
    body: {'error': 'Tên đăng nhập hoặc mật khẩu không đúng'},
  );
}
