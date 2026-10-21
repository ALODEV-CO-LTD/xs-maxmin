import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/e2ee_devices.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /me/e2ee-devices` -> `{devices: [{id, publicKey, createdAt, lastSeen}]}`: the devices of the signed-in account that
/// can read chat messages (docs/MA_HOA_2_DAU.md). Registering is `PUT /me/e2ee-devices/<id>`.
Response onRequest(RequestContext context) {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  if (context.request.method != HttpMethod.get) return Response(statusCode: 405, body: 'Method not allowed');
  final db = context.read<Database>();
  return Response.json(body: {'devices': devicesOf(db, auth.userId)});
}
