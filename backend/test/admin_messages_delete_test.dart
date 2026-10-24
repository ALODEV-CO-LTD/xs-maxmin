import 'dart:typed_data';

import 'package:dart_frog/dart_frog.dart';
import 'package:test/test.dart';

import '../routes/api/admin/messages/[userId]/[messageId].dart' as one;
import '../routes/api/admin/messages/[userId]/index.dart' as thread;
import '../routes/api/admin/messages/index.dart' as inbox;
import '../routes/api/me/messages/index.dart' as mine;
import 'support.dart';

void main() {
  late dynamic db;
  setUp(() {
    db = testDb();
    void msg(String id, String from, String to, {String content = 'x', Uint8List? att, String at = '2026-01-01'}) => db.execute(
          "INSERT INTO direct_messages (id, from_user_id, to_user_id, content, created_at, attachment_name, attachment_type, attachment_size, attachment_data) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
          [id, from, to, content, at, att == null ? null : 'a.png', att == null ? null : 'image/png', att?.length, att],
        );
    msg('m1', 'u1', 'adm', content: 'khach hoi'); // customer -> admin
    msg('m2', 'adm', 'u1', content: 'admin tra loi', att: Uint8List.fromList([1, 2, 3]), at: '2026-01-02'); // admin reply (with a picture)
    msg('m3', 'u2', 'adm'); // another customer
    msg('f1', 'u1', 'u2'); // a friend chat of u1 (never touched)
  });

  Future<dynamic> del(String user, String id, {String uid = 'adm', String role = 'admin'}) =>
      callRoute((c) => one.onRequest(c, user, id), db, userId: uid, role: role, method: HttpMethod.delete);

  test('Admin deletes ITS OWN reply: the row stays as a notice, text and picture are gone, both sides see "deleted"', () async {
    final r = await del('u1', 'm2');
    expect(r.statusCode, 200);
    final row = db.select("SELECT * FROM direct_messages WHERE id = 'm2'").first;
    expect(row['content'], '');
    expect(row['attachment_data'], isNull);
    expect(row['attachment_name'], isNull);
    expect(row['deleted_at'], isNotNull);

    final adminView = await jsonBody(await callRoute((c) => thread.onRequest(c, 'u1'), db, userId: 'adm', role: 'admin', method: HttpMethod.get));
    final m2 = (adminView['messages'] as List).firstWhere((m) => m['id'] == 'm2');
    expect(m2['deleted'], true);
    expect(m2['content'], '');
    expect(m2['attachment'], isNull);

    final customerView = await jsonBody(await callRoute(mine.onRequest, db, userId: 'u1', method: HttpMethod.get));
    expect((customerView['messages'] as List).firstWhere((m) => m['id'] == 'm2')['deleted'], true);
    expect((customerView['messages'] as List).firstWhere((m) => m['id'] == 'm1')['deleted'], false);
  });

  test('deleting twice is fine, and the inbox preview says the message was deleted', () async {
    expect((await del('u1', 'm2')).statusCode, 200);
    expect((await del('u1', 'm2')).statusCode, 200);
    final list = await jsonBody(await callRoute(inbox.onRequest, db, userId: 'adm', role: 'admin', method: HttpMethod.get));
    final c1 = (list['conversations'] as List).firstWhere((c) => c['userId'] == 'u1');
    expect(c1['lastMessage'], 'Tin nhắn đã bị xoá');
  });

  test('Admin can NOT delete a customer\'s message', () async {
    final r = await del('u1', 'm1');
    expect(r.statusCode, 403);
    expect(db.select("SELECT content, deleted_at FROM direct_messages WHERE id = 'm1'").first['content'], 'khach hoi');
  });

  test('only a row of that thread: another customer, a friend chat, a missing id', () async {
    for (final id in ['m3', 'f1', 'nope']) {
      expect((await del('u1', id)).statusCode, 404, reason: id);
    }
  });

  test('a customer cannot use the admin delete, and the whole-thread DELETE no longer exists', () async {
    expect((await del('u1', 'm2', uid: 'u1', role: 'user')).statusCode, 403);
    final t = await callRoute((c) => thread.onRequest(c, 'u1'), db, userId: 'adm', role: 'admin', method: HttpMethod.delete);
    expect(t.statusCode, 405);
    expect(db.select('SELECT COUNT(*) c FROM direct_messages').first['c'], 4);
  });
}
