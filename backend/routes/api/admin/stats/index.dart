import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/package_plans.dart';
import 'package:sqlite3/sqlite3.dart';

/// Aggregate stats only - counts of subscribers per package/status.
/// Never touches data_entries (that stays private to each user).
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final denied = denyUnless(context, auth, 'stats.view');
  if (denied != null) return denied;

  final db = context.read<Database>();
  final totalRow = db.select("SELECT COUNT(*) AS c FROM users WHERE role = 'user'").first;
  final activeRow = db
      .select(
        "SELECT COUNT(*) AS c FROM users WHERE role = 'user' AND package_expires_at > ?",
        [DateTime.now().toUtc().toIso8601String()],
      )
      .first;

  final byPackage = <String, int>{};
  for (final pkg in PackageType.values) {
    if (pkg == PackageType.none) continue;
    final row = db
        .select(
          "SELECT COUNT(*) AS c FROM users WHERE role = 'user' AND package_type = ?",
          [pkg.wireValue],
        )
        .first;
    byPackage[pkg.wireValue] = row['c'] as int;
  }

  return Response.json(
    body: {
      'totalSubscribers': totalRow['c'],
      'activeSubscribers': activeRow['c'],
      'expiredSubscribers': (totalRow['c'] as int) - (activeRow['c'] as int),
      'byPackage': byPackage,
    },
  );
}
