import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';

/// The bank account Admin has configured for users to transfer package
/// payments to (via `PUT /api/admin/settings`, keys below) - deliberately
/// exposes only these 4 keys, not the whole `settings` table (which also
/// holds price overrides admins may not want visible verbatim, even though
/// they're not secret). Any key missing comes back null; the client shows
/// "chưa cấu hình" rather than a broken QR code.
const _keys = [
  'bank_name',
  'bank_account_number',
  'bank_account_holder',
  'bank_bin',
];

Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  final rows = db.select(
    'SELECT key, value FROM settings WHERE key IN (${_keys.map((_) => '?').join(',')})',
    _keys,
  );
  final values = {for (final r in rows) r['key'] as String: r['value'] as String};

  return Response.json(
    body: {
      'bankName': values['bank_name'],
      'bankAccountNumber': values['bank_account_number'],
      'bankAccountHolder': values['bank_account_holder'],
      'bankBin': values['bank_bin'],
    },
  );
}
