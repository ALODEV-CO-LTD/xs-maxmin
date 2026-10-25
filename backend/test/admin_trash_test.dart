import 'dart:async';
import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/admin_trash.dart';
import 'package:server/src/e2ee_devices.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/admin/announcements/[id].dart' as announcementRoute;
import '../routes/api/admin/packages/[code].dart' as packageRoute;
import '../routes/api/admin/settings/index.dart' as settingsRoute;
import '../routes/api/admin/staff/[id].dart' as staffRoute;
import '../routes/api/admin/trash/[id]/index.dart' as purgeRoute;
import '../routes/api/admin/trash/[id]/restore.dart' as restoreRoute;
import '../routes/api/admin/trash/index.dart' as trashRoute;
import '../routes/api/admin/users/[id]/index.dart' as userRoute;
import 'support.dart';

late Database db;

Database freshDb() {
  final d = testDb();
  d.execute('ALTER TABLE users ADD COLUMN staff_permissions TEXT');
  d.execute('ALTER TABLE payment_requests ADD COLUMN reference_code TEXT');
  d.execute('''CREATE TABLE announcements (id TEXT PRIMARY KEY, kind TEXT NOT NULL DEFAULT 'info', title TEXT NOT NULL,
    body TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, created_by TEXT REFERENCES users(id))''');
  d.execute('''CREATE TABLE packages (code TEXT PRIMARY KEY, label TEXT NOT NULL, duration_days INTEGER NOT NULL, price_vnd INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1)''');
  ensureAdminTrashTable(d);
  ensureE2eeDevicesTable(d);
  return d;
}

Future<Response> asAdmin(FutureOr<Response> Function(RequestContext) h, {HttpMethod method = HttpMethod.get, Object? body, String user = 'adm'}) =>
    callRoute(h, db, userId: user, role: 'admin', method: method, body: body);

/// u1 with customers, numbers, results, a template, a friendship with u2 and a support message with a picture.
void seedCustomer() {
  db.execute("INSERT INTO customers (id, user_id, name, created_at) VALUES ('c1', 'u1', 'Khach A', '2026-10-01'), ('c2', 'u1', 'Khach B', '2026-10-01')");
  db.execute("INSERT INTO data_entries (id, user_id, customer_name, entry_date, bet_type, value, score, created_at) VALUES ('e1', 'u1', 'Khach A', '2026-10-20', 'de', '12', '10', '2026-10-20'), ('e2', 'u1', 'Khach A', '2026-10-20', 'lo', '34', '5', '2026-10-20')");
  db.execute("INSERT INTO friendships (id, user_id, friend_id, created_at) VALUES ('f1', 'u1', 'u2', 'x'), ('f2', 'u2', 'u1', 'x')");
  db.execute("INSERT INTO direct_messages (id, from_user_id, to_user_id, content, created_at, attachment_name, attachment_type, attachment_size, attachment_data) VALUES ('m1', 'u1', 'adm', 'bi mat', '2026-10-20', 'a.png', 'image/png', 3, ?)", [
    [1, 2, 255],
  ]);
}

void main() {
  setUp(() {
    db = freshDb();
  });

  group('deleting a customer account', () {
    test('goes to the trash with every row it owned; the Admin sees counts, never the content', () async {
      seedCustomer();
      final r = await asAdmin((c) => userRoute.onRequest(c, 'u1'), method: HttpMethod.delete);
      expect(r.statusCode, 200);
      expect(db.select("SELECT 1 FROM users WHERE id = 'u1'"), isEmpty);
      expect(db.select('SELECT 1 FROM data_entries'), isEmpty); // gone from the live data (cascade)

      final list = await jsonBody(await asAdmin(trashRoute.onRequest));
      final item = (list['items'] as List).single as Map;
      expect(item['kind'], 'user');
      expect(item['label'], contains('nameu1'));
      expect(item['counts'], containsPair('data_entries', 2));
      expect(item['counts'], containsPair('customers', 2));
      expect(item['daysLeft'], 7);
      expect(jsonEncode(list), isNot(contains('Khach A'))); // no content in what the Admin gets
      expect(jsonEncode(list), isNot(contains('bi mat')));
    });

    test('restoring puts back the account and all its rows with the same ids, the picture included', () async {
      seedCustomer();
      final hash = db.select("SELECT password_hash FROM users WHERE id = 'u1'").single['password_hash'];
      await asAdmin((c) => userRoute.onRequest(c, 'u1'), method: HttpMethod.delete);
      final id = ((await jsonBody(await asAdmin(trashRoute.onRequest)))['items'] as List).single['id'] as String;

      final r = await asAdmin((c) => restoreRoute.onRequest(c, id), method: HttpMethod.post);
      expect(r.statusCode, 200);
      expect(db.select("SELECT password_hash FROM users WHERE id = 'u1'").single['password_hash'], hash);
      expect(db.select('SELECT id FROM data_entries ORDER BY id').map((x) => x['id']).toList(), ['e1', 'e2']);
      expect(db.select('SELECT id FROM customers ORDER BY id').map((x) => x['id']).toList(), ['c1', 'c2']);
      expect(db.select('SELECT id FROM friendships ORDER BY id').map((x) => x['id']).toList(), ['f1', 'f2']);
      expect(db.select("SELECT attachment_data FROM direct_messages WHERE id = 'm1'").single['attachment_data'], [1, 2, 255]);
      expect(((await jsonBody(await asAdmin(trashRoute.onRequest)))['items'] as List), isEmpty);
    });

    test('cannot be restored when somebody took the username meanwhile (the item stays)', () async {
      seedCustomer();
      await asAdmin((c) => userRoute.onRequest(c, 'u1'), method: HttpMethod.delete);
      db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('u9', 'NAMEU1', 'Khac', 'x', 'user', 0, '2026-10-21')");
      final id = ((await jsonBody(await asAdmin(trashRoute.onRequest)))['items'] as List).single['id'] as String;
      final r = await asAdmin((c) => restoreRoute.onRequest(c, id), method: HttpMethod.post);
      expect(r.statusCode, 409);
      expect((await jsonBody(r))['error'], contains('đã có người khác dùng'));
      expect(db.select('SELECT 1 FROM admin_trash'), isNotEmpty);
    });

    test('a friend who was deleted since is simply not linked again', () async {
      seedCustomer();
      await asAdmin((c) => userRoute.onRequest(c, 'u1'), method: HttpMethod.delete);
      db.execute("DELETE FROM users WHERE id = 'u2'");
      final id = ((await jsonBody(await asAdmin(trashRoute.onRequest)))['items'] as List).single['id'] as String;
      expect((await asAdmin((c) => restoreRoute.onRequest(c, id), method: HttpMethod.post)).statusCode, 200);
      expect(db.select('SELECT 1 FROM friendships'), isEmpty);
      expect(db.select('SELECT 1 FROM data_entries'), hasLength(2));
    });
  });

  group('the other things an Admin deletes', () {
    test('a staff account is restored with its permissions', () async {
      db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at, staff_permissions) VALUES ('st1', 'staff1', 'S', 'x', 'admin', 0, '2026-01-01', '[\"payments.manage\"]')");
      expect((await asAdmin((c) => staffRoute.onRequest(c, 'st1'), method: HttpMethod.delete)).statusCode, 200);
      expect(db.select("SELECT 1 FROM users WHERE id = 'st1'"), isEmpty);
      final item = ((await jsonBody(await asAdmin(trashRoute.onRequest)))['items'] as List).single as Map;
      expect(item['kind'], 'staff');
      expect((await asAdmin((c) => restoreRoute.onRequest(c, item['id'] as String), method: HttpMethod.post)).statusCode, 200);
      expect(db.select("SELECT staff_permissions FROM users WHERE id = 'st1'").single['staff_permissions'], '["payments.manage"]');
    });

    test('an announcement, a package and the bank settings come back', () async {
      db.execute("INSERT INTO announcements (id, title, created_at) VALUES ('a1', 'Bao tri toi nay', '2026-10-01')");
      db.execute("INSERT INTO packages (code, label, duration_days, price_vnd) VALUES ('p9', 'Goi thu', 7, 1000)");
      db.execute("INSERT INTO settings (key, value) VALUES ('bank_bin', '970416'), ('bank_account_number', '123')");
      expect((await asAdmin((c) => announcementRoute.onRequest(c, 'a1'), method: HttpMethod.delete)).statusCode, 200);
      expect((await asAdmin((c) => packageRoute.onRequest(c, 'p9'), method: HttpMethod.delete)).statusCode, 200);
      expect((await asAdmin(settingsRoute.onRequest, method: HttpMethod.delete, body: {'keys': ['bank_bin', 'bank_account_number']})).statusCode, 200);
      expect(db.select('SELECT 1 FROM announcements'), isEmpty);
      expect(db.select('SELECT 1 FROM packages'), isEmpty);
      expect(db.select("SELECT 1 FROM settings WHERE key LIKE 'bank%'"), isEmpty);

      final items = ((await jsonBody(await asAdmin(trashRoute.onRequest)))['items'] as List).cast<Map>();
      expect(items.map((x) => x['kind']).toSet(), {'announcement', 'package', 'setting'});
      for (final it in items) {
        expect((await asAdmin((c) => restoreRoute.onRequest(c, it['id'] as String), method: HttpMethod.post)).statusCode, 200);
      }
      expect(db.select("SELECT title FROM announcements WHERE id = 'a1'").single['title'], 'Bao tri toi nay');
      expect(db.select("SELECT label FROM packages WHERE code = 'p9'").single['label'], 'Goi thu');
      expect(db.select("SELECT value FROM settings WHERE key = 'bank_account_number'").single['value'], '123');
    });
  });

  group('7 days', () {
    test('what is older than 7 days is dropped, what is younger counts down', () {
      seedCustomer();
      final t0 = DateTime.utc(2026, 10, 20, 12);
      trashAccount(db, 'u1', staff: false, now: t0);
      expect(listTrash(db, now: t0.add(const Duration(days: 2))).single['daysLeft'], 5);
      expect(listTrash(db, now: t0.add(const Duration(days: 6, hours: 23))).single['daysLeft'], 1);
      expect(purgeExpiredTrash(db, now: t0.add(const Duration(days: 6, hours: 23))), 0);
      expect(purgeExpiredTrash(db, now: t0.add(const Duration(days: 7, minutes: 1))), 1);
      expect(listTrash(db), isEmpty);
    });

    test('"Xoá hẳn" removes it at once', () async {
      seedCustomer();
      await asAdmin((c) => userRoute.onRequest(c, 'u1'), method: HttpMethod.delete);
      final id = ((await jsonBody(await asAdmin(trashRoute.onRequest)))['items'] as List).single['id'] as String;
      expect((await asAdmin((c) => purgeRoute.onRequest(c, id), method: HttpMethod.delete)).statusCode, 200);
      expect(db.select('SELECT 1 FROM admin_trash'), isEmpty);
      expect((await asAdmin((c) => purgeRoute.onRequest(c, id), method: HttpMethod.delete)).statusCode, 404);
    });
  });

  group('who may use it', () {
    test('a staff account without the trash permission is refused; with it, allowed; a customer never', () async {
      db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at, staff_permissions) VALUES ('st1', 'staff1', 'S', 'x', 'admin', 0, '2026-01-01', '[\"users.view\"]'), ('st2', 'staff2', 'S', 'x', 'admin', 0, '2026-01-01', '[\"trash.manage\"]')");
      expect((await asAdmin(trashRoute.onRequest, user: 'st1')).statusCode, 403);
      expect((await asAdmin(trashRoute.onRequest, user: 'st2')).statusCode, 200);
      final cust = await callRoute(trashRoute.onRequest, db, userId: 'u1', role: 'user', method: HttpMethod.get);
      expect(cust.statusCode, 403);
    });
  });
}
