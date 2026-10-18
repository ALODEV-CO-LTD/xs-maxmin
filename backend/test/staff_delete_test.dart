import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

import '../routes/api/admin/staff/[id].dart' as route;
import 'support.dart';

void main() {
  test('deleting a staff member with payment and announcement history works and keeps the history', () async {
    final db = testDb();
    db.execute('ALTER TABLE users ADD COLUMN staff_permissions TEXT');
    db.execute('''CREATE TABLE announcements (id TEXT PRIMARY KEY, kind TEXT NOT NULL DEFAULT 'info', title TEXT NOT NULL,
      body TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, created_by TEXT REFERENCES users(id))''');
    db.execute("INSERT INTO users (id, username, name, password_hash, role, data_used, created_at, staff_permissions) VALUES ('st1','staff1','S','x','admin',0,'2026-01-01','[\"payments.manage\"]')");
    db.execute("INSERT INTO payment_requests (id, user_id, package_type, amount, status, created_at, decided_by) VALUES ('p1','u1','x',1,'approved','2026-01-01','st1')");
    db.execute("INSERT INTO announcements (id, title, created_at, created_by) VALUES ('a1','t','2026-01-01','st1')");

    final r = await callRoute((c) => route.onRequest(c, 'st1'), db, userId: 'adm', role: 'admin', method: HttpMethod.delete);
    expect(r.statusCode, 200);
    expect(db.select("SELECT 1 FROM users WHERE id = 'st1'"), isEmpty);
    expect(db.select("SELECT decided_by FROM payment_requests WHERE id = 'p1'").single['decided_by'], isNull);
    expect(db.select("SELECT created_by FROM announcements WHERE id = 'a1'").single['created_by'], isNull);
  });
}
