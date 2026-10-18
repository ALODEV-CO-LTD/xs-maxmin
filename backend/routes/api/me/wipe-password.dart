import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/database.dart';
import 'package:server/src/reauth_limit.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Lets the logged-in user set, change or remove their own wipe-password -
/// a distinct password (from their login password) that, if typed into the
/// login form instead, prompts a confirm-before-delete flow rather than
/// logging in. Purely opt-in and visible to the account owner; nothing
/// about it is hidden from them.
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;

  final self = loadSelfRow(context, auth.userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final db = context.read<Database>();
  final denied = checkReauthPassword(
    db,
    self,
    body['currentPassword'] as String?,
    action: 'Đặt mật khẩu xoá dữ liệu',
    ip: clientIp(context),
  );
  if (denied != null) return denied;
  final wipePassword = body['wipePassword'] as String?;
  final alreadyEnabled = self['wipe_password_hash'] != null;

  if (wipePassword == null || wipePassword.isEmpty) {
    // Once set, the wipe-password can only be changed, never turned off -
    // same rule as second-password. Matches how it's presented client-side.
    if (alreadyEnabled) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Mật khẩu xoá dữ liệu chỉ có thể đổi, không thể tắt'},
      );
    }
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập mật khẩu xoá dữ liệu'});
  }

  final wipeError = validateNewPassword(wipePassword);
  if (wipeError != null) {
    return Response.json(statusCode: 400, body: {'error': wipeError});
  }
  if (BCrypt.checkpw(wipePassword, self['password_hash'] as String)) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu xoá dữ liệu phải khác mật khẩu đăng nhập'},
    );
  }
  final secondPasswordHash = self['second_password_hash'] as String?;
  if (secondPasswordHash != null && BCrypt.checkpw(wipePassword, secondPasswordHash)) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Mật khẩu xoá dữ liệu phải khác mật khẩu lớp hai'},
    );
  }

  db.execute(
    'UPDATE users SET wipe_password_hash = ? WHERE id = ?',
    [BCrypt.hashpw(wipePassword, BCrypt.gensalt()), auth.userId],
  );
  return Response.json(body: {'enabled': true});
}
