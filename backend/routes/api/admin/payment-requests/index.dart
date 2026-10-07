import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/payments.dart';
import 'package:server/src/text_fold.dart';
import 'package:sqlite3/sqlite3.dart';

/// Payment requests for Admin, with filters and paging:
///   status  = pending (default) | approved | rejected | cancelled | all
///   q       = user name / username / transfer reference (accent-insensitive)
///   from,to = YYYY-MM-DD on the request date (inclusive)
///   limit (default 50, max 200), offset
/// `summary` always covers ALL requests (not the filtered page): pending count
/// and approved revenue today / 7 days / 30 days / all time.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (auth.role != 'admin') return forbidden();

  final db = context.read<Database>();
  final qp = context.request.uri.queryParameters;
  final limit = (int.tryParse(qp['limit'] ?? '') ?? 50).clamp(1, 200);
  final offset = (int.tryParse(qp['offset'] ?? '') ?? 0).clamp(0, 1000000);

  final rows = filterPaymentRequests(db, qp);
  final page = rows.skip(offset).take(limit).toList();

  return Response.json(
    body: {
      'requests': [for (final r in page) paymentJson(r, withUser: true)],
      'total': rows.length,
      'hasMore': offset + page.length < rows.length,
      'summary': paymentSummary(db),
    },
  );
}

/// Shared with the CSV export: every row matching the filters, newest first
/// (oldest first for the default 'pending' queue).
List<Row> filterPaymentRequests(Database db, Map<String, String> qp) {
  final status = qp['status'] ?? 'pending';
  final where = <String>[];
  final args = <Object?>[];
  switch (status) {
    case 'pending':
      where.add("pr.status = 'pending'");
    case 'approved':
      where.add("pr.status = 'approved'");
    case 'rejected':
      where.add("pr.status = 'rejected' AND pr.cancelled = 0");
    case 'cancelled':
      where.add("pr.status = 'rejected' AND pr.cancelled = 1");
  }
  final from = qp['from'];
  final to = qp['to'];
  if (from != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(from)) {
    where.add('pr.created_at >= ?');
    args.add('${from}T00:00:00');
  }
  if (to != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(to)) {
    where.add('pr.created_at < ?');
    args.add('${DateTime.parse(to).add(const Duration(days: 1)).toIso8601String().substring(0, 10)}T00:00:00');
  }
  final rows = db.select(
    '''
    SELECT pr.*, u.name AS user_name, u.username AS username
    FROM payment_requests pr JOIN users u ON u.id = pr.user_id
    ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
    ORDER BY pr.created_at ${status == 'pending' ? 'ASC' : 'DESC'}
    ''',
    args,
  );
  final q = foldVi((qp['q'] ?? '').trim());
  if (q.isEmpty) return rows.toList();
  return rows
      .where((r) => foldVi('${r['user_name']} ${r['username']} ${r['reference_code'] ?? ''}').contains(q))
      .toList();
}

Map<String, Object?> paymentSummary(Database db) {
  final now = DateTime.now().toUtc();
  String ago(int days) => now.subtract(Duration(days: days)).toIso8601String();
  int sum(String? since) {
    final r = db.select(
      "SELECT COALESCE(SUM(amount), 0) AS s FROM payment_requests WHERE status = 'approved'${since == null ? '' : ' AND decided_at >= ?'}",
      since == null ? [] : [since],
    );
    return r.first['s'] as int;
  }

  final startOfToday = DateTime.utc(now.year, now.month, now.day).toIso8601String();
  return {
    'pending': db.select("SELECT COUNT(*) AS c FROM payment_requests WHERE status = 'pending'").first['c'],
    'approvedCount': db.select("SELECT COUNT(*) AS c FROM payment_requests WHERE status = 'approved'").first['c'],
    'revenueToday': sum(startOfToday),
    'revenue7d': sum(ago(7)),
    'revenue30d': sum(ago(30)),
    'revenueAll': sum(null),
  };
}
