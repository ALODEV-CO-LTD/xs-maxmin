import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/push_tokens.dart';
import 'package:server/src/user_repo.dart';
import 'package:sqlite3/sqlite3.dart';

/// `POST /api/me/push-token {platform:'ios'|'android', token, deviceLabel?}` registers
/// (or moves) the device's APNs token for the caller; `DELETE {token}` removes
/// it (logout). Customers only - admin accounts get 403.
Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;
  if (method != HttpMethod.post && method != HttpMethod.delete) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final Map<String, dynamic> body;
  try {
    body = jsonDecode(await context.request.body()) as Map<String, dynamic>;
  } catch (_) {
    return Response.json(statusCode: 400, body: {'error': 'Body không hợp lệ'});
  }

  final self = loadSelfRow(context, auth.userId);
  if (self == null) return unauthorized('Tài khoản không tồn tại');
  if (self['role'] == 'admin') {
    return Response.json(statusCode: 403, body: {'error': 'Tài khoản quản trị không dùng thông báo đẩy'});
  }
  final db = context.read<Database>();

  final token = body['token'];
  final platform = body['platform'];
  if (token is! String || !(isValidPushToken(token) || isValidFcmToken(token))) {
    return Response.json(statusCode: 400, body: {'error': 'Token không hợp lệ'});
  }

  if (method == HttpMethod.delete) {
    // Only the owner can remove it.
    final removed = deletePushToken(db, token, userId: auth.userId);
    return Response.json(body: {'removed': removed});
  }

  if (platform is! String || !isValidPushTokenFor(platform, token)) {
    return Response.json(statusCode: 400, body: {'error': 'Nền tảng hoặc token không hợp lệ'});
  }
  final label = body['deviceLabel'];
  if (label != null && label is! String) {
    return Response.json(statusCode: 400, body: {'error': 'Dữ liệu không hợp lệ'});
  }
  upsertPushToken(db, auth.userId, platform, token, deviceLabel: (label as String?)?.trim(), sessionId: auth.sessionId);
  return Response.json(body: {'ok': true});
}
