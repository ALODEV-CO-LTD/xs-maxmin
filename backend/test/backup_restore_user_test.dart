import 'dart:async';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:path/path.dart' as p;
import 'package:server/src/admin_trash.dart';
import 'package:server/src/backup_restore.dart';
import 'package:server/src/e2ee_devices.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/admin/backups/index.dart' as listRoute;
import '../routes/api/admin/backups/restore-user.dart' as restoreRoute;
import '../routes/api/admin/backups/users.dart' as usersRoute;
import 'support.dart';

late Database db;
late Directory manual, cron;
const backupId = 'manual:xoso-2026-10-20T01-00-00-000000Z.db';

Future<Response> post(Object body) => callRoute(restoreRoute.onRequest, db, userId: 'adm', role: 'admin', method: HttpMethod.post, body: body);

void addEntry(String id, String user, String value) =>
    db.execute("INSERT INTO data_entries (id, user_id, customer_name, entry_date, bet_type, value, score, created_at) VALUES (?, ?, 'Khach A', '2026-10-20', 'de', ?, '1', '2026-10-20')", [id, user, value]);

List<String> entryIds(String user) => [for (final r in db.select('SELECT id FROM data_entries WHERE user_id = ? ORDER BY id', [user])) r['id'] as String];

void main() {
  setUp(() {
    db = testDb();
    db.execute('ALTER TABLE users ADD COLUMN staff_permissions TEXT');
    ensureAdminTrashTable(db);
    ensureE2eeDevicesTable(db);
    final tmp = Directory.systemTemp.createTempSync('mamba-bk-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    manual = Directory(p.join(tmp.path, 'manual'))..createSync();
    cron = Directory(p.join(tmp.path, 'cron'))..createSync();
    manualBackupDirOverride = manual;
    cronBackupDirOverride = cron;
    addTearDown(() {
      manualBackupDirOverride = null;
      cronBackupDirOverride = null;
    });
    // u1 and u2 have data; the backup is taken now
    db.execute("INSERT INTO customers (id, user_id, name, created_at) VALUES ('c1', 'u1', 'Khach A', '2026-10-01'), ('c2', 'u2', 'Khach Z', '2026-10-01')");
    addEntry('e1', 'u1', '12');
    addEntry('e2', 'u1', '34');
    addEntry('z1', 'u2', '99');
    final mf = p.join(manual.path, 'xoso-2026-10-20T01-00-00-000000Z.db');
    db.execute('VACUUM INTO ?', [mf]);
    File(mf).setLastModifiedSync(DateTime.utc(2026, 10, 20, 1)); // what its name says
  });

  test('the list holds the Admin\'s own backups and the daily cron ones, newest first, and nothing else', () async {
    final cronFile = File(p.join(cron.path, 'xoso-20261025-0200.db'))..writeAsBytesSync([0]);
    cronFile.setLastModifiedSync(DateTime.utc(2026, 10, 25, 2));
    File(p.join(cron.path, 'notes.txt')).writeAsStringSync('x');
    final r = await callRoute(listRoute.onRequest, db, userId: 'adm', role: 'admin', method: HttpMethod.get);
    final body = await jsonBody(r);
    final src = (body['sources'] as List).cast<Map>();
    expect(src.map((x) => x['id']), ['cron:xoso-20261025-0200.db', backupId]);
    expect(src.map((x) => x['source']), ['cron', 'manual']);
    expect((body['backups'] as List), hasLength(1)); // the old list (downloads) is unchanged
  });

  test('the users of a backup come with counts of then and now, never data', () async {
    db.execute("DELETE FROM data_entries WHERE id = 'e1'");
    db.execute("DELETE FROM users WHERE id = 'u2'"); // gone since the backup
    final r = await callRoute(usersRoute.onRequest, db, userId: 'adm', role: 'admin', method: HttpMethod.get, path: '/api/admin/backups/users?backup=$backupId');
    expect(r.statusCode, 200);
    final body = await jsonBody(r);
    final users = {for (final u in (body['users'] as List).cast<Map>()) u['username']: u};
    expect(users.keys, containsAll(['nameu1', 'nameu2']));
    expect(users.keys, isNot(contains('nameadm'))); // only customers
    expect((users['nameu1']!['inBackup'] as Map)['data_entries'], 2);
    expect((users['nameu1']!['now'] as Map)['data_entries'], 1);
    expect(users['nameu2']!['now'], isNull); // no longer an account: restoring needs the trash
    expect(r.headers, isNotNull);
    expect(body.toString(), isNot(contains('Khach A')));
    final missing = await callRoute(usersRoute.onRequest, db, userId: 'adm', role: 'admin', method: HttpMethod.get, path: '/api/admin/backups/users?backup=manual:nope.db');
    expect(missing.statusCode, 404);
  });

  test('merge puts back what the customer deleted, keeps what they typed since, and touches nobody else', () async {
    db.execute("DELETE FROM data_entries WHERE user_id = 'u1'");
    db.execute("DELETE FROM customers WHERE user_id = 'u1'");
    addEntry('e3', 'u1', '56'); // typed after the backup
    db.execute("UPDATE data_entries SET value = '00' WHERE id = 'z1'"); // another customer changed theirs
    final r = await post({'backup': backupId, 'userId': 'u1', 'mode': 'merge'});
    expect(r.statusCode, 200);
    final body = await jsonBody(r);
    expect(body['restored'], isTrue);
    expect(entryIds('u1'), ['e1', 'e2', 'e3']);
    expect(db.select("SELECT id FROM customers WHERE user_id = 'u1'").single['id'], 'c1');
    expect(db.select("SELECT value FROM data_entries WHERE id = 'z1'").single['value'], '00'); // u2 untouched
    expect((body['written'] as Map)['data_entries'], 2);
    // a backup of the live database was made first and can itself be listed
    expect(File(p.join(manual.path, body['safetyBackup'] as String)).existsSync(), isTrue);
  });

  test('merge never overwrites a row that exists now and never doubles one', () async {
    db.execute("UPDATE data_entries SET value = '77' WHERE id = 'e1'"); // edited after the backup
    expect((await post({'backup': backupId, 'userId': 'u1', 'mode': 'merge'})).statusCode, 200);
    expect(db.select("SELECT value FROM data_entries WHERE id = 'e1'").single['value'], '77');
    expect(entryIds('u1'), ['e1', 'e2']);
    expect((await post({'backup': backupId, 'userId': 'u1', 'mode': 'merge'})).statusCode, 200); // twice: still no duplicates
    expect(entryIds('u1'), ['e1', 'e2']);
  });

  test('replace brings the customer\'s data back to the backup (what was typed since is gone) and still leaves others alone', () async {
    db.execute("DELETE FROM data_entries WHERE id = 'e1'");
    addEntry('e3', 'u1', '56');
    db.execute("UPDATE data_entries SET value = '77' WHERE id = 'e2'");
    final r = await post({'backup': backupId, 'userId': 'u1', 'mode': 'replace'});
    expect(r.statusCode, 200);
    expect(entryIds('u1'), ['e1', 'e2']);
    expect(db.select("SELECT value FROM data_entries WHERE id = 'e2'").single['value'], '34');
    expect(entryIds('u2'), ['z1']);
    expect(((await jsonBody(r))['removed'] as Map)['data_entries'], 2);
  });

  test('refused with a reason: customer not in the backup, account gone, bad backup id, bad mode, path tricks', () async {
    db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at) VALUES ('u7', 'newer', 'N', 'x', 'user', 0, '2026-10-22')");
    final notInBackup = await post({'backup': backupId, 'userId': 'u7'});
    expect(notInBackup.statusCode, 409);
    expect((await jsonBody(notInBackup))['error'], contains('không có trong bản sao lưu'));
    db.execute("DELETE FROM users WHERE id = 'u1'");
    final gone = await post({'backup': backupId, 'userId': 'u1'});
    expect(gone.statusCode, 409);
    expect((await jsonBody(gone))['error'], contains('Thùng rác'));
    expect((await post({'backup': 'manual:nope.db', 'userId': 'u2'})).statusCode, 404);
    expect((await post({'backup': 'manual:../../etc/passwd', 'userId': 'u2'})).statusCode, 404);
    expect((await post({'backup': 'other:xoso-2026-10-20T01-00-00-000000Z.db', 'userId': 'u2'})).statusCode, 404);
    expect((await post({'backup': backupId, 'userId': 'u2', 'mode': 'wipe'})).statusCode, 400);
    expect((await post({'backup': backupId})).statusCode, 400);
  });

  test('a customer account (not an Admin) may not use it, nor a staff account without the backups permission', () async {
    db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at, staff_permissions) VALUES ('st1', 'staff1', 'S', 'x', 'admin', 0, '2026-01-01', '[\"users.view\"]')");
    expect((await callRoute(restoreRoute.onRequest, db, userId: 'u1', role: 'user', method: HttpMethod.post, body: {'backup': backupId, 'userId': 'u1'})).statusCode, 403);
    expect((await callRoute(restoreRoute.onRequest, db, userId: 'st1', role: 'admin', method: HttpMethod.post, body: {'backup': backupId, 'userId': 'u1'})).statusCode, 403);
  });

  test('restoring works on the cron backups too (read from the other folder)', () async {
    db.execute('VACUUM INTO ?', [p.join(cron.path, 'xoso-20261025-0200.db')]);
    db.execute("DELETE FROM data_entries WHERE user_id = 'u1'");
    expect((await post({'backup': 'cron:xoso-20261025-0200.db', 'userId': 'u1'})).statusCode, 200);
    expect(entryIds('u1'), ['e1', 'e2']);
  });
}
