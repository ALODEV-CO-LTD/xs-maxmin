import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/maintenance.dart';
import 'package:test/test.dart';

void main() {
  Response? block({bool on = true, String msg = 'Bảo trì 23h', String? role = 'user', String path = '/api/me/entries'}) => maintenanceBlock(enabled: on, message: msg, role: role, path: path);

  test('customers get 503 with the admin message while maintenance is on', () async {
    final r = block()!;
    expect(r.statusCode, 503);
    expect(await r.json(), {'error': 'Bảo trì 23h', 'maintenance': true});
  });

  test('an empty message falls back to the default text', () async {
    expect((await block(msg: '  ')!.json())['error'], defaultMaintenanceMessage);
  });

  test('off, admins/staff and the open paths are untouched', () {
    expect(block(on: false), isNull);
    expect(block(role: 'admin'), isNull);
    expect(block(role: null), isNull);
    for (final p in ['/api/auth/login', '/api/announcements', '/api/app-version', '/api/me/sessions', '/api/me/sessions/abc']) {
      expect(block(path: p), isNull, reason: p);
    }
  });

  test('chat sockets and data routes are blocked', () {
    for (final p in ['/api/ws/calls', '/api/me/messages', '/api/me/friends', '/api/lottery-results']) {
      expect(block(path: p)?.statusCode, 503, reason: p);
    }
  });
}
