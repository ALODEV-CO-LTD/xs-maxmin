import 'package:sqlite3/sqlite3.dart';

/// Paging for GET /api/me/entries. One page is at most [maxEntriesPageSize]
/// rows; the client (frontend `loadAllEntries`) walks the pages with
/// limit/offset until `hasMore` is false, so a user is never cut off at some
/// fixed number of records.
const defaultEntriesPageSize = 500;
const maxEntriesPageSize = 1000;

int _clamp(String? raw, int fallback, int min, int max) {
  final n = int.tryParse(raw ?? '');
  if (n == null) return fallback;
  return n < min ? min : (n > max ? max : n);
}

/// Rows of one page plus the user's total number of records.
/// The order is total/stable (entry_date, created_at, id DESC) so pages never
/// overlap or skip rows between two requests.
({List<Row> rows, int total, int limit, int offset}) listEntriesPage(
  Database db,
  String userId, {
  String? limitParam,
  String? offsetParam,
}) {
  final limit = _clamp(limitParam, defaultEntriesPageSize, 1, maxEntriesPageSize);
  final offset = _clamp(offsetParam, 0, 0, 1 << 31);
  final total = db.select('SELECT COUNT(*) AS n FROM data_entries WHERE user_id = ?', [userId]).first['n'] as int;
  final rows = db.select(
    'SELECT * FROM data_entries WHERE user_id = ? ORDER BY entry_date DESC, created_at DESC, id DESC LIMIT ? OFFSET ?',
    [userId, limit, offset],
  );
  return (rows: rows, total: total, limit: limit, offset: offset);
}

/// Today's date (YYYY-MM-DD) in Vietnam (UTC+7, no DST), used as the default
/// entry date when the client does not send one.
String vietnamToday([DateTime? nowUtc]) {
  final t = (nowUtc ?? DateTime.now().toUtc()).add(const Duration(hours: 7));
  return t.toIso8601String().substring(0, 10);
}
