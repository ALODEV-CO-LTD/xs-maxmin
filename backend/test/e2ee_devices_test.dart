import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/call_signaling.dart';
import 'package:server/src/e2ee_devices.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../routes/api/me/e2ee-devices/[deviceId].dart' as device;
import '../routes/api/me/e2ee-devices/index.dart' as devices;
import '../routes/api/me/e2ee-key.dart' as legacyKey;
import '../routes/api/me/friends/index.dart' as friends;
import 'support.dart';

class _Sink implements WebSocketSink {
  final sent = <Map<String, dynamic>>[];
  @override
  void add(Object? data) => sent.add(jsonDecode(data as String) as Map<String, dynamic>);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Chan extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  _Chan() : sink = _Sink();
  @override
  final _Sink sink;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

String _b64(int n) => String.fromCharCodes(List.filled(43, 65 + n % 26)); // 43 url-safe characters, like a P-256 coordinate

Map<String, String> keyOf(int n) => {'kty': 'EC', 'crv': 'P-256', 'x': _b64(n), 'y': _b64(n + 1)};

late Database db;

Future<Response> putDevice(String user, String id, Object? body) =>
    callRoute((c) => device.onRequest(c, id), db, userId: user, method: HttpMethod.put, body: body);

void main() {
  setUp(() {
    db = testDb();
    db.execute('ALTER TABLE users ADD COLUMN e2ee_public_key TEXT');
    ensureE2eeDevicesTable(db);
  });

  test('two devices of one account keep their own keys: neither replaces the other', () async {
    expect((await putDevice('u1', 'phone-device-1', {'publicKey': keyOf(1)})).statusCode, 200);
    expect((await putDevice('u1', 'tablet-device-2', {'publicKey': keyOf(3)})).statusCode, 200);
    // the phone opens the app again with the same key: nothing changes, nothing is overwritten
    final again = await jsonBody(await putDevice('u1', 'phone-device-1', {'publicKey': keyOf(1)}));
    expect(again['changed'], isFalse);
    final list = await jsonBody(await callRoute(devices.onRequest, db, userId: 'u1', method: HttpMethod.get));
    final ids = [for (final d in list['devices'] as List) (d as Map)['id']];
    expect(ids.toSet(), {'phone-device-1', 'tablet-device-2'});
  });

  test('the friend list carries every device key of a friend (and the single key older apps read)', () async {
    db.execute("INSERT INTO friendships (id,user_id,friend_id,created_at) VALUES ('a','u1','u2','x')");
    await putDevice('u2', 'phone-device-1', {'publicKey': keyOf(1)});
    await putDevice('u2', 'tablet-device-2', {'publicKey': keyOf(3)});
    final res = await jsonBody(await callRoute(friends.onRequest, db, userId: 'u1', method: HttpMethod.get));
    final f = (res['friends'] as List).single as Map;
    expect([for (final d in f['devices'] as List) (d as Map)['id']].toSet(), {'phone-device-1', 'tablet-device-2'});
    expect((f['publicKey'] as Map)['x'], keyOf(3)['x']); // the newest registration
  });

  test('the single key of an older app is the `legacy` device; an account that already had one is migrated', () async {
    db.execute("UPDATE users SET e2ee_public_key = ? WHERE id = 'u2'", [jsonEncode(keyOf(5))]);
    ensureE2eeDevicesTable(db);
    expect(devicesOf(db, 'u2').single['id'], legacyDeviceId);
    // an older app publishing again does not disturb the new devices
    await putDevice('u2', 'phone-device-1', {'publicKey': keyOf(1)});
    final r = await callRoute(legacyKey.onRequest, db, userId: 'u2', method: HttpMethod.put, body: {'publicKey': keyOf(7)});
    expect(r.statusCode, 200);
    final ids = [for (final d in devicesOf(db, 'u2')) d['id']];
    expect(ids.toSet(), {legacyDeviceId, 'phone-device-1'});
  });

  test('bad ids and keys are refused; `legacy` cannot be registered by a new app', () async {
    expect((await putDevice('u1', 'short', {'publicKey': keyOf(1)})).statusCode, 400);
    expect((await putDevice('u1', 'legacy', {'publicKey': keyOf(1)})).statusCode, 400);
    expect((await putDevice('u1', 'phone-device-1', {'publicKey': {'kty': 'EC', 'crv': 'P-256', 'x': 'a', 'y': 'b'}})).statusCode, 400);
    expect((await putDevice('u1', 'phone-device-1', {'publicKey': {...keyOf(1), 'd': 'private'}})).statusCode, 200);
    expect(jsonEncode(devicesOf(db, 'u1')), isNot(contains('"d"'))); // a private part is never kept
  });

  test('at most $maxDevicesPerUser devices: the one unseen for longest is dropped, never the new one', () async {
    for (var i = 0; i < maxDevicesPerUser + 2; i++) {
      await putDevice('u1', 'device-number-$i', {'publicKey': keyOf(i * 2)});
      db.execute('UPDATE e2ee_devices SET last_seen = ? WHERE device_id = ?', ['2026-01-0${i + 1}T00:00:00Z', 'device-number-$i']);
    }
    final ids = [for (final d in devicesOf(db, 'u1')) d['id']];
    expect(ids.length, maxDevicesPerUser);
    expect(ids, contains('device-number-${maxDevicesPerUser + 1}'));
    expect(ids, isNot(contains('device-number-0')));
  });

  test('deleting a device forgets it; the key older apps read follows the newest remaining device', () async {
    await putDevice('u1', 'phone-device-1', {'publicKey': keyOf(1)});
    await putDevice('u1', 'tablet-device-2', {'publicKey': keyOf(3)});
    final r = await callRoute((c) => device.onRequest(c, 'tablet-device-2'), db, userId: 'u1', method: HttpMethod.delete);
    expect(r.statusCode, 200);
    expect([for (final d in devicesOf(db, 'u1')) d['id']], ['phone-device-1']);
    expect((jsonDecode(db.select("SELECT e2ee_public_key FROM users WHERE id = 'u1'").first['e2ee_public_key'] as String) as Map)['x'], keyOf(1)['x']);
    // someone else cannot touch it
    await callRoute((c) => device.onRequest(c, 'phone-device-1'), db, userId: 'u2', method: HttpMethod.delete);
    expect(devicesOf(db, 'u1').length, 1);
  });

  group('relay registry', () {
    test('a frame for one device reaches only that device; `legacy` reaches connections without a device id', () {
      final reg = CallSignalingRegistry.instance;
      final phone = _Chan(), tablet = _Chan(), old = _Chan();
      reg.register('md-u1', phone, deviceId: 'phone-device-1');
      reg.register('md-u1', tablet, deviceId: 'tablet-device-2');
      reg.register('md-u1', old);
      expect(reg.deviceOf(phone), 'phone-device-1');

      expect(reg.sendToDevice('md-u1', 'tablet-device-2', {'type': 'e2ee-msg', 'id': 'a'}), isTrue);
      expect(tablet.sink.sent.length, 1);
      expect(phone.sink.sent, isEmpty);
      expect(old.sink.sent, isEmpty);

      expect(reg.sendToDevice('md-u1', legacyDeviceId, {'type': 'e2ee-msg', 'id': 'b'}), isTrue);
      expect(old.sink.sent.length, 1);
      expect(phone.sink.sent, isEmpty);

      expect(reg.sendToDevice('md-u1', 'unknown-device-9', {'type': 'e2ee-msg', 'id': 'c'}), isFalse); // that device is not online
      reg.unregister('md-u1', tablet);
      expect(reg.sendToDevice('md-u1', 'tablet-device-2', {'type': 'e2ee-msg', 'id': 'd'}), isFalse);
      expect(reg.deviceOf(tablet), isNull);
    });
  });
}
