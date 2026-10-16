import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/scoring_rates.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// Per-user payout config ("tỉ lệ ăn" + which prize tiers to compare
/// against) used by ScoringView's auto-calc and EntriesView's "Loại đánh"
/// picker - each account (each "đại lý" running their own customers) sets
/// its own, NOT admin-controlled: deliberately under /me, reachable by any
/// logged-in user, with no role check.
///
/// Each bet type maps to `{rate, tiers, digits}`: `rate` is the payout
/// multiple, `tiers` is which of the 8 prize groups in a lottery_results
/// row (dacBiet/giaiNhat/giaiNhi/giaiBa/giaiTu/giaiNam/giaiSau/giaiBay)
/// count as a match - e.g. "đề" traditionally only checks `dacBiet`, while
/// "lô" checks all 8. `digits` is how many trailing digits to compare (2
/// for "đề"/"lô", 3 for "3 càng", 4 for "bao lô 4", ...) - defaults to 2,
/// matching every type's behavior before this field existed. Stored as one
/// JSON blob (key `scoring_rates` on `users` for historical reasons - it
/// used to hold only rates, see below).
///
/// GET  -> { rates: {typeKey: {rate, tiers, digits}} }  (falls back to the
///          "bảng cấu hình" default, defaultTableRates(), if the user never saved an override)
/// PUT  { rates: {typeKey: {rate, tiers, digits}} } -> saves it as this
///      user's own
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _get(context, auth.userId),
    HttpMethod.put => _put(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _get(RequestContext context, String userId) {
  final self = loadSelfRow(context, userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final raw = self['scoring_rates'] as String?;
  Map<String, dynamic> rates = defaultTableRates();
  if (raw != null) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded.isNotEmpty) {
        // Rows the account removed from its table are kept as {disabled: true} markers.
        final (normalized, _) = normalizeRatesMap(decoded, allowEmpty: true, allowDisabled: true);
        if (normalized != null && normalized.isNotEmpty) rates = normalized;

      }
    } catch (_) {
      // Malformed row - fall back to the built-in defaults.
    }
  }
  return Response.json(
    body: {'rates': rates, 'availableTiers': validTiers, 'digitRange': [minDigits, maxDigits]},
  );
}

Future<Response> _put(RequestContext context, String userId) async {
  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final (normalized, error) = normalizeRatesMap(body['rates'], allowDisabled: true);
  if (normalized == null) return Response.json(statusCode: 400, body: {'error': error});
  if (normalized.values.every((v) => v is Map && v['disabled'] == true)) {
    return Response.json(statusCode: 400, body: {'error': 'Cần ít nhất một loại đánh'});
  }

  final db = context.read<Database>();
  db.execute('UPDATE users SET scoring_rates = ? WHERE id = ?', [jsonEncode(normalized), userId]);

  return Response.json(
    body: {'rates': normalized, 'availableTiers': validTiers, 'digitRange': [minDigits, maxDigits]},
  );
}
