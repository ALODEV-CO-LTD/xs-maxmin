import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';

import 'security.dart';

/// Maintenance mode (Admin > Thông báo & bảo trì > Chế độ bảo trì, settings `maintenance_enabled` / `maintenance_message`).
/// While it is on every request of a CUSTOMER account is answered with 503 `{error, maintenance: true}`; admins and staff
/// (role `admin`) keep working. Left open on purpose: the auth routes (so anybody can sign in or out), the notices feed
/// (the apps read the maintenance message there) and the app-version check.
const defaultMaintenanceMessage = 'Hệ thống đang bảo trì, vui lòng quay lại sau.';

/// The 503 for [role]'s request to [path], or null when it may go on. Pure, so it is unit-tested.
Response? maintenanceBlock({required bool enabled, required String message, required String? role, required String path}) {
  if (!enabled || role != 'user') return null;
  const open = ['/api/auth/', '/api/announcements', '/api/app-version', '/api/me/sessions'];
  if (open.any(path.startsWith)) return null;
  if (!path.startsWith('/api/')) return null;
  return Response.json(
    statusCode: 503,
    body: {'error': message.trim().isEmpty ? defaultMaintenanceMessage : message.trim(), 'maintenance': true},
  );
}

({bool enabled, String message}) _read(Database db) {
  final rows = db.select("SELECT key, value FROM settings WHERE key IN ('maintenance_enabled', 'maintenance_message')");
  final m = {for (final r in rows) r['key'] as String: r['value'] as String};
  return (enabled: m['maintenance_enabled'] == 'true', message: m['maintenance_message'] ?? '');
}

/// Runs after the auth provider (it reads the token's role).
Middleware maintenanceGate(Database Function() db) => (handler) => (context) async {
      final auth = context.read<AuthTokenPayload?>();
      if (auth != null && auth.role == 'user') {
        final s = _read(db());
        final blocked = maintenanceBlock(enabled: s.enabled, message: s.message, role: auth.role, path: context.request.uri.path);
        if (blocked != null) return blocked;
      }
      return handler(context);
    };
