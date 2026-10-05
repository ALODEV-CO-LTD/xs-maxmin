import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:sqlite3/sqlite3.dart';

/// Notices for the banner in AppShell (A12/A16). Any logged-in user may read.
///
/// GET -> {
///   maintenance: { enabled: bool, message: String },   // settings keys
///   announcements: [{ id, kind, title, body, createdAt }]  // active only
/// }
///
/// Maintenance mode is configured by the admin through the generic
/// `settings` store (keys `maintenance_enabled` = "true"/"false" and
/// `maintenance_message`) - see admin/AnnouncementsView.vue. It only shows a
/// notice; it does not lock anyone out.
Response onRequest(RequestContext context) {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }

  final db = context.read<Database>();
  String? setting(String key) {
    final rows = db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  final rows = db.select(
    'SELECT id, kind, title, body, created_at FROM announcements WHERE active = 1 ORDER BY created_at DESC LIMIT 20',
  );
  return Response.json(
    body: {
      'maintenance': {
        'enabled': setting('maintenance_enabled') == 'true',
        'message': setting('maintenance_message') ?? '',
      },
      'announcements': [
        for (final r in rows)
          {
            'id': r['id'],
            'kind': r['kind'],
            'title': r['title'],
            'body': r['body'],
            'createdAt': r['created_at'],
          },
      ],
    },
  );
}
