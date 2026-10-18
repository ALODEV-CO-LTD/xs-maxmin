import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/database.dart';
import 'package:server/src/customer_codes.dart';
import 'package:server/src/package_plans.dart';
import 'package:server/src/password_policy.dart';
import 'package:server/src/recovery_codes.dart';
import 'package:server/src/security.dart';
import 'package:sqlite3/sqlite3.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final read = await readJsonBody(context, authBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;

  if (!fieldsAreStrings(body, ['name', 'username', 'password', 'secondPassword', 'wipePassword'])) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
  }
  final name = (body['name'] as String?)?.trim();
  final username = (body['username'] as String?)?.trim();
  final password = body['password'] as String?;
  final secondPassword = body['secondPassword'] as String?;
  final wipePassword = (body['wipePassword'] as String?)?.trim();

  if (name == null || name.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tên hiển thị'});
  }
  if (username == null || username.length < 3) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Tên đăng nhập phải có ít nhất 3 ký tự'},
    );
  }
  final passwordError = password == null ? 'Vui lòng nhập mật khẩu' : validateNewPassword(password);
  if (password == null || passwordError != null) {
    return Response.json(statusCode: 400, body: {'error': passwordError});
  }
  final secondError = secondPassword == null ? 'Vui lòng đặt mật khẩu lớp hai' : validateNewPassword(secondPassword);
  if (secondPassword == null || secondError != null) {
    return Response.json(statusCode: 400, body: {'error': secondError});
  }
  // Wipe-password is optional at registration - the user can also set it
  // later from Tài khoản. Only validated when they choose to fill it in.
  if (wipePassword != null && wipePassword.isNotEmpty) {
    final wipeError = validateNewPassword(wipePassword);
    if (wipeError != null) {
      return Response.json(statusCode: 400, body: {'error': wipeError});
    }
    if (wipePassword == password || wipePassword == secondPassword) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Mật khẩu xoá dữ liệu phải khác 2 mật khẩu còn lại'},
      );
    }
  }

  final db = context.read<Database>();
  final existing = db.select('SELECT id FROM users WHERE username = ?', [username]);
  if (existing.isNotEmpty) {
    return Response.json(
      statusCode: 409,
      body: {'error': 'Tên đăng nhập đã được sử dụng'},
    );
  }

  final id = newId();
  final nowDt = DateTime.now().toUtc();
  final now = nowDt.toIso8601String();
  final wipePasswordHash =
      (wipePassword != null && wipePassword.isNotEmpty) ? BCrypt.hashpw(wipePassword, BCrypt.gensalt()) : null;
  // Every new account starts on a free trial (see package_plans.dart) so
  // people can try the app before buying a package - gated by the same
  // package_expires_at/data_quota_total check every paid plan uses, so it
  // expires on its own with no separate code path.
  final trialExpiresAt = nowDt.add(const Duration(days: trialDurationDays));
  db.execute(
    '''
    INSERT INTO users (
      id, name, username, password_hash, second_password_hash, wipe_password_hash,
      role, package_type, package_started_at, package_expires_at, data_quota_total, status, created_at
    ) VALUES (?, ?, ?, ?, ?, ?, 'user', ?, ?, ?, ?, 'active', ?)
    ''',
    [
      id,
      name,
      username,
      BCrypt.hashpw(password, BCrypt.gensalt()),
      BCrypt.hashpw(secondPassword, BCrypt.gensalt()),
      wipePasswordHash,
      PackageType.trial.wireValue,
      now,
      trialExpiresAt.toIso8601String(),
      trialQuota,
      now,
    ],
  );

  // Every customer gets a Mã ID right away so others can find them by it.
  ensureCustomerCode(db, id);

  // Mã khôi phục: shown to the user exactly once in this response (only its
  // hash is stored) - the client must make them confirm they saved it.
  final recoveryCode = rotateRecoveryCode(db, id);

  // The account now has a second password, so the client must still go
  // through step 2 before it gets a real session - same as any login.
  return Response.json(statusCode: 201, body: {
    'stage': 'second_password_required',
    'pendingToken': issuePendingSecondFactorToken(id),
    'recoveryCode': recoveryCode,
  });
}
