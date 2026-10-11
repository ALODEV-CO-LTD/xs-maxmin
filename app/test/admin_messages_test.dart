import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/admin/messages/admin_messages_logic.dart';

Conversation c(String id, String name, String user, {bool awaiting = false, String? at}) => Conversation(userId: id, userName: name, username: user, awaitingReply: awaiting, lastMessageAt: at);

void main() {
  final all = [
    c('1', 'Nguyễn Văn Đạt', 'dat01', awaiting: true, at: '2026-10-10T10:00:00Z'),
    c('2', 'Trần Thị Lan', 'lan', at: '2026-10-11T08:00:00Z'),
    c('3', 'Lê Hoàng', 'hoang99', awaiting: true, at: '2026-10-09T08:00:00Z'),
  ];

  test('noAccents folds Vietnamese', () {
    expect(noAccents('Nguyễn Văn Đạt'), 'nguyen van dat');
  });

  test('filter by name/username ignoring accents and by awaiting', () {
    expect(filterConversations(all, query: 'dat').map((e) => e.userId), ['1']);
    expect(filterConversations(all, query: 'HOANG99').map((e) => e.userId), ['3']);
    expect(filterConversations(all, onlyAwaiting: true).map((e) => e.userId), ['1', '3']);
    expect(filterConversations(all, query: 'lan', onlyAwaiting: true), isEmpty);
    expect(filterConversations(all).length, 3);
  });

  test('awaiting count and newest-first sort', () {
    expect(awaitingCount(all), 2);
    expect(sortConversations(all).map((e) => e.userId), ['2', '1', '3']);
  });

  test('conversation and message parsing is null-safe', () {
    final conv = Conversation.fromJson({'userId': 5, 'userName': null, 'awaitingReply': true});
    expect(conv.userId, '5');
    expect(conv.userName, '');
    expect(conv.awaitingReply, isTrue);
    final m = AdminMsg.fromJson({
      'id': 'a',
      'sender': 'admin',
      'content': 'hi',
      'createdAt': '2026-10-11T01:00:00Z',
      'attachment': {'name': 'x.png', 'type': 'image/png', 'size': 10, 'isImage': true},
    });
    expect(m.fromAdmin, isTrue);
    expect(m.attachment!.isImage, isTrue);
    expect(AdminMsg.fromJson({'id': 'b', 'sender': 'user'}).attachment, isNull);
  });

  test('threadItems inserts one divider per day', () {
    final now = DateTime(2026, 10, 11, 12);
    final msgs = [
      AdminMsg(id: 'a', fromAdmin: false, content: '1', createdAt: DateTime(2026, 10, 9, 9).toUtc().toIso8601String()),
      AdminMsg(id: 'b', fromAdmin: true, content: '2', createdAt: DateTime(2026, 10, 10, 9).toUtc().toIso8601String()),
      AdminMsg(id: 'c', fromAdmin: true, content: '3', createdAt: DateTime(2026, 10, 10, 10).toUtc().toIso8601String()),
      AdminMsg(id: 'd', fromAdmin: false, content: '4', createdAt: DateTime(2026, 10, 11, 9).toUtc().toIso8601String()),
    ];
    final items = threadItems(msgs, now);
    expect(items.whereType<String>().toList(), ['09/10/2026', 'Hôm qua', 'Hôm nay']);
    expect(items.length, 7);
  });

  test('attachment payload: base64, anonymous name, type from magic bytes', () {
    final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3]);
    final p = buildAttachmentPayload(png, byte: () => 0xab);
    expect(p['type'], 'image/png');
    expect(p['name'], 'anh-abababababab.png'.replaceFirst('abababababab', 'ababababab'));
    expect(base64Decode(p['data'] as String), png);
    expect(buildReplyBody('  hi ', p), {'content': 'hi', 'attachment': p});
    expect(buildReplyBody('hi', null).containsKey('attachment'), isFalse);
  });

  test('attachment payload rejects non-images, empty and oversize', () {
    expect(() => buildAttachmentPayload(Uint8List(0)), throwsException);
    expect(() => buildAttachmentPayload(Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])), throwsException);
    final big = Uint8List(5 * 1024 * 1024 + 1)..setAll(0, [0xff, 0xd8, 0xff]);
    expect(() => buildAttachmentPayload(big), throwsException);
  });

  test('ApiClient round trip: list + reply with attachment', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      if (req.method == 'POST') {
        return http.Response.bytes(
          utf8.encode(jsonEncode({'id': 'n', 'sender': 'admin', 'content': 'Xin chào', 'createdAt': '2026-10-11T01:00:00Z', 'attachment': null})),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'conversations': [
              {'userId': 'u', 'userName': 'Đạt', 'username': 'dat', 'awaitingReply': true, 'lastMessage': 'Chào', 'lastMessageAt': '2026-10-11T01:00:00Z'},
            ],
          }),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final api = ApiClient(AuthStore(), client: client);
    final res = await api.get('/admin/messages') as Map<String, dynamic>;
    final convs = [for (final x in res['conversations'] as List) Conversation.fromJson(x as Map<String, dynamic>)];
    expect(convs.single.userName, 'Đạt');
    final r = await api.post('/admin/messages/u', buildReplyBody('Xin chào', null)) as Map<String, dynamic>;
    expect(AdminMsg.fromJson(r).content, 'Xin chào');
    expect(seen.url.path, endsWith('/admin/messages/u'));
  });
}
