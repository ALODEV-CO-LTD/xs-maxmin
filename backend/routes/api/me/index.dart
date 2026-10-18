import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/request_body.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/reauth_limit.dart';
import 'package:server/src/sessions.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET` - the logged-in account's own profile.
///
/// `PATCH` body `{"name": "...", "username": "...", "currentPassword": "..."}`
/// - edits the account's own display name and/or login username (works the
/// same for `user` and `admin` roles; it only ever touches the caller's own
/// row). Fields are optional but at least one must be given. Same rules as
/// registration: name non-empty, username >= 3 chars and not already taken.
/// Changing the username changes the login identity, so it also requires the
/// current password (name-only edits don't). Tokens carry the user id, not
/// the username, so existing sessions stay valid.
Future<Response> onRequest(RequestContext context) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  return switch (context.request.method) {
    HttpMethod.get => _get(context, auth.userId),
    HttpMethod.patch => _patch(context, auth.userId),
    _ => Response(statusCode: 405, body: 'Method not allowed'),
  };
}

Response _get(RequestContext context, String userId) {
  final row = loadSelfRow(context, userId);
  if (row == null) return unauthorized('Tài khoản không tồn tại');
  return Response.json(body: meJson(row));
}

Future<Response> _patch(RequestContext context, String userId) async {
  final read = await readJsonBody(context, smallBodyMaxBytes);
  if (read.error != null) return read.error!;
  final body = read.body!;

  final self = loadSelfRow(context, userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');

  final newName = (body['name'] as String?)?.trim();
  final newUsername = (body['username'] as String?)?.trim();
  if (newName == null && newUsername == null) {
    return Response.json(
      statusCode: 400,
      body: {'error': "Thiếu trường 'name' hoặc 'username'"},
    );
  }

  if (newName != null && newName.isEmpty) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Vui lòng nhập tên hiển thị'},
    );
  }

  final usernameChanged =
      newUsername != null && newUsername != self['username'] as String;
  if (newUsername != null && newUsername.length < 3) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Tên đăng nhập phải có ít nhất 3 ký tự'},
    );
  }

  final db = context.read<Database>();

  if (usernameChanged) {
    // Shared throttle (403 wrong / 429 locked), never 401.
    final denied = checkReauthPassword(
      db,
      self,
      body['currentPassword'] as String?,
      action: 'Đổi tên đăng nhập',
      ip: clientIp(context),
    );
    if (denied != null) return denied;
    final taken = db.select(
      'SELECT id FROM users WHERE username = ? AND id != ?',
      [newUsername, userId],
    );
    if (taken.isNotEmpty) {
      return Response.json(
        statusCode: 409,
        body: {'error': 'Tên đăng nhập đã được sử dụng'},
      );
    }
  }

  if (newName != null) {
    db.execute('UPDATE users SET name = ? WHERE id = ?', [newName, userId]);
  }
  if (usernameChanged) {
    db.execute('UPDATE users SET username = ? WHERE id = ?', [
      newUsername,
      userId,
    ]);
  }

  final updated = loadSelfRow(context, userId);
  return Response.json(body: meJson(updated!));
}
