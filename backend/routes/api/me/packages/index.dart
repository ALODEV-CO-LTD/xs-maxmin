import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/database.dart';
import 'package:server/src/package_plans.dart';
import 'package:sqlite3/sqlite3.dart';

/// The purchasable plan catalog, with Admin's price overrides already
/// applied - the single source of truth `purchase_screen.dart` should read
/// instead of hardcoding its own copy of `package_plans.dart`'s defaults.
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final db = context.read<Database>();
  // `?all=1`: every package incl. hidden ones, labels only (for showing history).
  final all = context.request.uri.queryParameters['all'] == '1';
  return Response.json(
    body: {
      'packages': [
        for (final p in listPackages(db, onlyActive: !all))
          if (p.active) p.toJson() else {'type': p.code, 'label': p.label, 'active': false},
      ],
    },
  );
}
