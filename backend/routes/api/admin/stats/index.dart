import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/stats_buckets.dart';
import 'package:server/src/package_plans.dart';
import 'package:sqlite3/sqlite3.dart';

/// Aggregate stats only - counts of subscribers per package/status, plus a
/// time series for the combined chart: `?range=day` (30 ngày) | `week` (12 tuần) | `month` (12 tháng) | `year` (5 năm)
/// (older `7|30|90|12m` still work) -> `series: [{date, newUsers, revenue}]`. `revenue` (sum of
/// `transactions`) is only included for admins holding `payments.manage`.
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
  for (final code in ['trial', for (final p in listPackages(db)) p.code]) {
    final row = db
        .select(
          "SELECT COUNT(*) AS c FROM users WHERE role = 'user' AND package_type = ?",
          [code],
        )
        .first;
    byPackage[code] = row['c'] as int;
  }

  final range = context.request.uri.queryParameters['range'] ?? 'day';
  final canRevenue = denyUnless(context, auth, 'payments.manage') == null;

  // Bucket keys (UTC), oldest first: ngày YYYY-MM-DD, tuần = Monday YYYY-MM-DD, tháng YYYY-MM, năm YYYY.
  final spec = statsBuckets(range, DateTime.now().toUtc());
  final newUsers = {for (final k in spec.keys) k: 0};
  final revenue = {for (final k in spec.keys) k: 0};
  final since = spec.since;
  for (final r in db.select("SELECT created_at FROM users WHERE role = 'user' AND substr(created_at, 1, 10) >= ?", [since])) {
    final k = spec.keyOf(r['created_at'] as String);
    if (newUsers.containsKey(k)) newUsers[k!] = newUsers[k]! + 1;
  }
  if (canRevenue) {
    for (final r in db.select('SELECT created_at, amount FROM transactions WHERE substr(created_at, 1, 10) >= ?', [since])) {
      final k = spec.keyOf(r['created_at'] as String);
      if (revenue.containsKey(k)) revenue[k!] = revenue[k]! + ((r['amount'] as num?)?.toInt() ?? 0);
    }
  }

  return Response.json(
    body: {
      'series': [
        for (final k in spec.keys)
          {'date': k, 'newUsers': newUsers[k], if (canRevenue) 'revenue': revenue[k]},
      ],
      'seriesRange': spec.unit,
      'canRevenue': canRevenue,
      'totalSubscribers': totalRow['c'],
      'activeSubscribers': activeRow['c'],
      'expiredSubscribers': (totalRow['c'] as int) - (activeRow['c'] as int),
      'byPackage': byPackage,
    },
  );
}
