import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/permissions.dart';
import 'package:server/src/package_plans.dart';
import 'package:sqlite3/sqlite3.dart';

/// Aggregate stats only - counts of subscribers per package/status, plus a
/// time series for the combined chart: `?range=7|30|90` (daily) or `12m`
/// (monthly) -> `series: [{date, newUsers, revenue}]`. `revenue` (sum of
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

  final range = context.request.uri.queryParameters['range'] ?? '30';
  final monthly = range == '12m';
  final buckets = monthly ? 12 : (const {'7': 7, '30': 30, '90': 90}[range] ?? 30);
  final canRevenue = denyUnless(context, auth, 'payments.manage') == null;

  // Bucket keys (UTC): YYYY-MM-DD, or YYYY-MM for the monthly view, oldest first.
  final now = DateTime.now().toUtc();
  final keys = <String>[
    for (var i = buckets - 1; i >= 0; i--)
      monthly
          ? _key(DateTime.utc(now.year, now.month - i, 1), 7)
          : _key(now.subtract(Duration(days: i)), 10),
  ];
  final len = monthly ? 7 : 10;
  final newUsers = {for (final k in keys) k: 0};
  final revenue = {for (final k in keys) k: 0};
  for (final r in db.select(
    "SELECT substr(created_at, 1, $len) AS k, COUNT(*) AS c FROM users WHERE role = 'user' AND substr(created_at, 1, $len) >= ? GROUP BY k",
    [keys.first],
  )) {
    if (newUsers.containsKey(r['k'])) newUsers[r['k'] as String] = r['c'] as int;
  }
  if (canRevenue) {
    for (final r in db.select(
      'SELECT substr(created_at, 1, $len) AS k, SUM(amount) AS s FROM transactions WHERE substr(created_at, 1, $len) >= ? GROUP BY k',
      [keys.first],
    )) {
      if (revenue.containsKey(r['k'])) revenue[r['k'] as String] = r['s'] as int;
    }
  }

  return Response.json(
    body: {
      'series': [
        for (final k in keys)
          {'date': k, 'newUsers': newUsers[k], if (canRevenue) 'revenue': revenue[k]},
      ],
      'seriesRange': monthly ? '12m' : '$buckets',
      'canRevenue': canRevenue,
      'totalSubscribers': totalRow['c'],
      'activeSubscribers': activeRow['c'],
      'expiredSubscribers': (totalRow['c'] as int) - (activeRow['c'] as int),
      'byPackage': byPackage,
    },
  );
}

String _key(DateTime d, int len) => d.toIso8601String().substring(0, len);
