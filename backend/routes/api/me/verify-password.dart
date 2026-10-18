import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/reauth_limit.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// `POST` body `{"password": "..."}` - used by the client's auto-lock screen
/// (K09/K40): checks the caller's login password OR second-layer password
/// without issuing a new token. Wrong password answers 403 (not 401) on
/// purpose so the client does not treat it as an expired session and log out.
/// Failures are throttled per user in the database (reauth_limit.dart), so
/// the counter survives a server restart.

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;
  final password = body['password'] as String?;
  if (password == null || password.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập mật khẩu'});
  }

  final self = loadSelfRow(context, auth.userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final denied = checkReauthPassword(
    context.read<Database>(),
    self,
    password,
    action: 'Mở khoá màn hình',
    ip: clientIp(context),
    wrongMessage: 'Mật khẩu không đúng',
    allowSecond: true,
  );
  if (denied != null) return denied;
  return Response.json(body: {'ok': true});
}
