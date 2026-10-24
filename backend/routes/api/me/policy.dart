import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/security_policy.dart';
import 'package:sqlite3/sqlite3.dart';

/// The part of the admin-set security policy the app itself needs (A09):
/// the default idle auto-lock, the default lock-when-away time, the viewer watermark and the screenshot guard.
/// `GET -> {autoLockMinutes, hideLockSeconds, watermarkEnabled, screenshotGuardEnabled, blurOnHideEnabled}` for any logged-in account.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  if (requireAuth(context) == null) return unauthorized();
  final p = loadPolicy(context.read<Database>());
  return Response.json(body: {
    'autoLockMinutes': p.autoLockMinutes,
    'hideLockSeconds': p.hideLockSeconds,
    'watermarkEnabled': p.watermarkEnabled,
    'screenshotGuardEnabled': p.screenshotGuardEnabled,
    'blurOnHideEnabled': p.blurOnHideEnabled,
  });
}
