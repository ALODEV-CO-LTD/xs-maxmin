import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/security_policy.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// Security policy configuration (A09), permission `security.policy`.
/// `GET` -> `{policy, defaults}`; `PUT {any subset of fields}` saves (validated,
/// logged to the security log); `DELETE` restores the built-in defaults.
/// The policy applies to the very next request: the login throttle and token
/// lifetime are read from the database each time (token lifetime affects
/// logins from then on, existing tokens keep the expiry they were issued with).
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'security.policy');
  if (denied != null) return denied;
  final db = context.read<Database>();

  switch (context.request.method) {
    case HttpMethod.get:
      return _view(db);
    case HttpMethod.put:
      final read = await readJsonBody(context, smallBodyMaxBytes);
      if (read.error != null) return read.error!;
      final body = read.body!;
      // Validate the merged result, so lowering "max lock" below the stored "first lock" is refused too.
      final merged = {...loadPolicy(db).toJson(), ...body};
      final error = validatePolicyInput(merged);
      if (error != null) return Response.json(statusCode: 400, body: {'error': error});
      final before = loadPolicy(db).toJson();
      savePolicy(db, body);
      final after = loadPolicy(db).toJson();
      final changed = [for (final k in after.keys) if (before[k] != after[k]) '$k: ${before[k]} -> ${after[k]}'];
      if (changed.isNotEmpty) {
        logSecurityEvent(db, 'security_policy_changed', userId: auth.userId, ip: clientIp(context), detail: changed.join('; '));
      }
      return _view(db);
    case HttpMethod.delete:
      resetPolicy(db);
      logSecurityEvent(db, 'security_policy_reset', userId: auth.userId, ip: clientIp(context), detail: 'Đặt lại chính sách bảo mật về mặc định');
      return _view(db);
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}

Response _view(Database db) => Response.json(body: {
      'policy': loadPolicy(db).toJson(),
      'defaults': const SecurityPolicy().toJson(),
    });
