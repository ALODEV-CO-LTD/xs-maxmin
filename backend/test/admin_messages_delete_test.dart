import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

import '../routes/api/admin/messages/[userId]/[messageId].dart' as one;
import '../routes/api/admin/messages/[userId]/index.dart' as thread;
import 'support.dart';

void main() {
  late dynamic db;
  setUp(() {
    db = testDb();
    void msg(String id, String from, String to) => db.execute(
          "INSERT INTO direct_messages (id, from_user_id, to_user_id, content, created_at) VALUES (?, ?, ?, 'x', '2026-01-01')",
          [id, from, to],
        );
    msg('m1', 'u1', 'adm'); // customer -> admin
    msg('m2', 'adm', 'u1'); // admin reply
    msg('m3', 'u2', 'adm'); // another customer
    msg('f1', 'u1', 'u2'); // a friend chat of u1 (never touched)
  });

  int count() => db.select('SELECT COUNT(*) c FROM direct_messages').first['c'] as int;

  test('admin deletes one message of a customer thread (the customer message or an admin reply)', () async {
    var r = await callRoute((c) => one.onRequest(c, 'u1', 'm1'), db, userId: 'adm', role: 'admin', method: HttpMethod.delete);
    expect(r.statusCode, 200);
    r = await callRoute((c) => one.onRequest(c, 'u1', 'm2'), db, userId: 'adm', role: 'admin', method: HttpMethod.delete);
    expect(r.statusCode, 200);
    expect(count(), 2);
  });

  test('only a row of that thread can be deleted: another customer\'s message, a friend chat, a missing id', () async {
    for (final id in ['m3', 'f1', 'nope']) {
      final r = await callRoute((c) => one.onRequest(c, 'u1', id), db, userId: 'adm', role: 'admin', method: HttpMethod.delete);
      expect(r.statusCode, 404, reason: id);
    }
    expect(count(), 4);
  });

  test('a customer cannot delete through the admin routes', () async {
    final r = await callRoute((c) => one.onRequest(c, 'u1', 'm1'), db, userId: 'u1', method: HttpMethod.delete);
    expect(r.statusCode, 403);
    final t = await callRoute((c) => thread.onRequest(c, 'u1'), db, userId: 'u1', method: HttpMethod.delete);
    expect(t.statusCode, 403);
    expect(count(), 4);
  });

  test('clearing a thread removes both directions for that customer only', () async {
    final r = await callRoute((c) => thread.onRequest(c, 'u1'), db, userId: 'adm', role: 'admin', method: HttpMethod.delete);
    expect(r.statusCode, 200);
    expect((await jsonBody(r))['deleted'], 2);
    expect(db.select("SELECT id FROM direct_messages ORDER BY id").map((e) => e['id']).toList(), ['f1', 'm3']);
  });
}
