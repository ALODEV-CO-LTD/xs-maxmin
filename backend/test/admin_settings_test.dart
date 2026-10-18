import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/admin/settings/index.dart' as route;
import 'support.dart';

void main() {
  Future<Response> put(Database db, Object body) => callRoute(route.onRequest, db, userId: 'adm', role: 'admin', method: HttpMethod.put, body: body);

  test('bank info and max_virtual_ids can be saved', () async {
    final db = testDb();
    final r = await put(db, {'bank_bin': '970422', 'bank_name': 'MB', 'bank_account_number': '123', 'bank_account_holder': 'A', 'max_virtual_ids': '7'});
    expect(r.statusCode, 200);
    final b = await jsonBody(r);
    expect(b['bank_bin'], '970422');
    expect(b['max_virtual_ids'], '7');
  });

  test('policy keys in any case, maintenance keys and markers are refused and nothing is written', () async {
    final db = testDb();
    for (final k in ['policy.tokenDays', 'POLICY.tokenDays', 'Policy.loginFreeAttempts', 'maintenance_enabled', 'maintenance_message', 'perm_split_maintenance', 'app_min_version', 'whatever']) {
      final r = await put(db, {'bank_bin': '1', k: '1'});
      expect(r.statusCode, anyOf(400, 403), reason: k);
    }
    expect(db.select('SELECT 1 FROM settings'), isEmpty);
  });

  test('DELETE only for allowed keys; markers survive', () async {
    final db = testDb();
    db.execute("INSERT INTO settings (key, value) VALUES ('perm_split_maintenance', '1'), ('bank_bin', '9'), ('POLICY.x', '1')");
    Future<Response> del(Object body) => callRoute(route.onRequest, db, userId: 'adm', role: 'admin', method: HttpMethod.delete, body: body);
    expect((await del({'keys': ['perm_split_maintenance']})).statusCode, 400);
    expect((await del({'keys': ['POLICY.x']})).statusCode, 403);
    expect((await del({'keys': [5]})).statusCode, 400);
    expect((await del({'keys': ['bank_bin']})).statusCode, 200);
    expect(db.select('SELECT key FROM settings ORDER BY key').map((r) => r['key']).toList(), ['POLICY.x', 'perm_split_maintenance']);
  });

  test('values must be strings or numbers', () async {
    final db = testDb();
    expect((await put(db, {'bank_name': {'a': 1}})).statusCode, 400);
    expect((await put(db, {'bank_name': 'x' * 201})).statusCode, 400);
  });
}
