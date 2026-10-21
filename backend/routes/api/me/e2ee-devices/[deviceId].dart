import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';
import 'package:server/src/e2ee_devices.dart';
import 'package:server/src/request_body.dart';
import 'package:sqlite3/sqlite3.dart';

import '../e2ee-key.dart' show normalizePublicKey;

/// One device of the signed-in account (docs/MA_HOA_2_DAU.md).
///   `PUT {publicKey}` publishes or refreshes this device's key (idempotent; a new device id is added next to the others).
///   `DELETE` forgets a device (a lost phone): friends stop encrypting to it.
Future<Response> onRequest(RequestContext context, String deviceId) async {
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();
  final db = context.read<Database>();
  final okId = deviceId == legacyDeviceId || deviceIdPattern.hasMatch(deviceId);
  if (!okId) return Response.json(statusCode: 400, body: {'error': 'Mã thiết bị không hợp lệ'});

  switch (context.request.method) {
    case HttpMethod.put:
      // `legacy` is the single key of older app versions; the new app always has an id of its own.
      if (deviceId == legacyDeviceId) return Response.json(statusCode: 400, body: {'error': 'Mã thiết bị không hợp lệ'});
      final read = await readJsonBody(context, smallBodyMaxBytes);
      if (read.error != null) return read.error!;
      final key = normalizePublicKey(read.body!['publicKey']);
      if (key == null) return Response.json(statusCode: 400, body: {'error': 'Khoá công khai không hợp lệ'});
      final changed = upsertDevice(db, auth.userId, deviceId, key);
      return Response.json(body: {'publicKey': key, 'changed': changed, 'devices': devicesOf(db, auth.userId).length});
    case HttpMethod.delete:
      removeDevice(db, auth.userId, deviceId);
      return Response.json(body: {'ok': true});
    default:
      return Response(statusCode: 405, body: 'Method not allowed');
  }
}
