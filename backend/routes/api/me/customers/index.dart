import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/phone.dart';
import 'package:sqlite3/sqlite3.dart';

/// A user's own customer roster. EntriesView is meant to pick a name FROM
/// here (see routes/api/me/entries) instead of free-typing a new one on
/// every entry, so a typo never silently creates a duplicate "phantom"
/// customer - adding to the roster is a deliberate, separate step done
/// here (or on CustomersView.vue).
///
/// GET  -> { customers: [{ id, name, phone, scoringRates, createdAt }] }, ordered by name
///         (`scoringRates` = this customer's own payout config, or null to follow the account's)
/// POST { name, phone? } -> creates one; 409 if that name already exists
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _list(context, auth.userId),
    HttpMethod.post => _create(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Object? _rates(Object? raw) {
  if (raw is! String) return null;
  try {
    return jsonDecode(raw);
  } catch (_) {
    return null;
  }
}

Response _list(RequestContext context, String userId) {
  final db = context.read<Database>();
  _backfillFromEntries(db, userId);
  final rows = db.select(
    'SELECT * FROM customers WHERE user_id = ? ORDER BY name COLLATE NOCASE',
    [userId],
  );
  return Response.json(
    body: {
      'customers': [
        for (final r in rows)
          {'id': r['id'], 'name': r['name'], 'phone': r['phone'] ?? '', 'scoringRates': _rates(r['scoring_rates']), 'defaultStation': r['default_station'], 'homeRegion': r['home_region'], 'createdAt': r['created_at']},
      ],
    },
  );
}

/// Adds any customer name already used in data_entries (typed before this
/// roster existed, or by an older client) that isn't on the roster yet -
/// so the "pick from the list" dropdown in EntriesView doesn't leave out
/// customers who already have history. Idempotent: only inserts names not
/// already present, safe to call on every GET.
void _backfillFromEntries(Database db, String userId) {
  final missing = db.select(
    '''
    SELECT DISTINCT customer_name FROM data_entries
    WHERE user_id = ? AND customer_name IS NOT NULL AND TRIM(customer_name) != ''
    AND LOWER(customer_name) NOT IN (
      SELECT LOWER(name) FROM customers WHERE user_id = ?
    )
    ''',
    [userId, userId],
  );
  if (missing.isEmpty) return;
  final now = DateTime.now().toUtc().toIso8601String();
  for (final row in missing) {
    db.execute(
      'INSERT OR IGNORE INTO customers (id, user_id, name, created_at) VALUES (?, ?, ?, ?)',
      [newId(), userId, row['customer_name'], now],
    );
  }
}

Future<Response> _create(RequestContext context, String userId) async {
  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;

  final name = (body['name'] as String?)?.trim();
  if (name == null || name.isEmpty) {
    return Response.json(statusCode: 400, body: {'error': 'Vui lòng nhập tên khách hàng'});
  }

  final phone = normalizePhone(body['phone']);
  if (phone == null) {
    return Response.json(statusCode: 400, body: {'error': 'Số điện thoại không hợp lệ'});
  }

  final db = context.read<Database>();
  final existing = db.select(
    'SELECT id FROM customers WHERE user_id = ? AND name = ? COLLATE NOCASE',
    [userId, name],
  );
  if (existing.isNotEmpty) {
    return Response.json(statusCode: 409, body: {'error': 'Khách hàng "$name" đã có trong danh sách'});
  }

  final id = newId();
  final now = DateTime.now().toUtc().toIso8601String();
  db.execute(
    'INSERT INTO customers (id, user_id, name, phone, created_at) VALUES (?, ?, ?, ?, ?)',
    [id, userId, name, phone, now],
  );
  return Response.json(statusCode: 201, body: {'id': id, 'name': name, 'phone': phone, 'createdAt': now});
}
