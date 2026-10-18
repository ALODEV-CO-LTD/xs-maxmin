import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/chat_calc/chat_prefill.dart';
import 'package:mamba_app/features/friends/chat_models.dart';
import 'package:mamba_app/features/friends/chat_page.dart';
import 'package:mamba_app/features/friends/chat_service.dart';
import 'package:mamba_app/features/friends/chat_store.dart';
import 'package:mamba_app/features/friends/friends_controller.dart';
import 'package:mamba_app/features/friends/friends_screen.dart';
import 'package:mamba_app/features/friends/messaging_host.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Sock extends RealtimeSocket {
  _Sock() : super(tokenProvider: () => 't');
  final _in = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> sent = [];
  @override
  bool get ready => true;
  @override
  Stream<Map<String, dynamic>> get frames => _in.stream;
  @override
  void start() {}
  @override
  void reconnectNow() {}
  @override
  void send(Map<String, dynamic> frame) => sent.add(frame);
}

http.Response _json(Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});

ChatMessage msg(String id, String text, {bool mine = false, int at = 1000, String peer = 'f1'}) =>
    ChatMessage(id: id, peerId: peer, mine: mine, text: text, createdAt: at, status: MsgStatus.delivered);

ChatService svc(MemoryChatStore store) => ChatService(api: ApiClient(AuthStore(), client: MockClient((_) async => http.Response('{}', 404))), userId: 'me', store: store, vault: MemoryKeyVault(), socket: _Sock());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reply quote format (same text as the web)', () {
    test('composeReply / quoteOf round trip', () {
      final text = composeReply(msg('a', 'xin chào'), 'ok nhé');
      expect(text, '↪ xin chào\nok nhé');
      final q = quoteOf(text);
      expect(q.quote, 'xin chào');
      expect(q.body, 'ok nhé');
    });
    test('plain messages and a quote line without a body are untouched', () {
      expect(quoteOf('chào').quote, '');
      expect(quoteOf('chào').body, 'chào');
      expect(quoteOf('↪ chỉ dòng này').quote, '');
      expect(quoteOf('↪ chỉ dòng này').body, '↪ chỉ dòng này');
      expect(quoteOf('').body, '');
    });
    test('multi-line bodies keep their lines; quoting a reply drops its quote line; 60 chars; image placeholder', () {
      expect(quoteOf('↪ a\nb\nc').body, 'b\nc');
      expect(quoteText(msg('x', '↪ cũ\nmới\ndòng hai')), 'mới dòng hai');
      expect(quoteText(msg('x', 'a' * 100)).length, 60);
      final img = ChatMessage(id: 'i', peerId: 'f1', mine: true, text: '', createdAt: 1, status: 'sent', att: const ChatAttachment(name: 'a.jpg', type: 'image/jpeg', size: 1));
      expect(quoteText(img), '[Ảnh]');
      expect(composeReply(img, ''), '↪ [Ảnh]\n');
    });
  });

  group('local chat notes', () {
    test('pins toggle, survive a restart and drop with the deleted message', () async {
      final store = MemoryChatStore();
      var s = svc(store);
      await store.putMessage(msg('a', 'một'));
      await store.putMessage(msg('b', 'hai'));
      expect(await s.togglePin('f1', 'a'), ['a']);
      expect(await s.togglePin('f1', 'b'), ['a', 'b']);
      expect(await s.togglePin('f1', 'a'), ['b']);
      s = svc(store); // "restart" on the same store
      expect(await s.pinsOf('f1'), ['b']);
      await s.deleteMessage('f1', 'b');
      expect(await s.pinsOf('f1'), isEmpty);
      expect(await store.message('b'), isNull);
      expect(await store.message('a'), isNotNull);
    });

    test('own display name is kept only when it differs from the real name', () async {
      final store = MemoryChatStore();
      final s = svc(store);
      await s.setAlias('f1', '  Bạn thân ', 'Bình');
      expect(s.displayName('f1', 'Bình'), 'Bạn thân');
      final s2 = svc(store);
      await s2.restorePrefs();
      expect(s2.displayName('f1', 'Bình'), 'Bạn thân');
      await s2.setAlias('f1', 'Bình', 'Bình');
      expect(s2.displayName('f1', 'Bình'), 'Bình');
      expect(await store.meta('alias:f1'), isNull);
    });

    test('archive / unarchive and delete conversation (friend stays, other chats untouched)', () async {
      final store = MemoryChatStore();
      final s = svc(store);
      await store.putMessage(msg('a', 'x'));
      await store.putMessage(msg('b', 'y', peer: 'f2'));
      await s.setArchived(['f1', 'f2'], true);
      final s2 = svc(store);
      await s2.restorePrefs();
      expect(s2.archived, {'f1', 'f2'});
      await s2.setArchived(['f1'], false);
      expect(s2.archived, {'f2'});
      await s2.deleteConversation('f1');
      expect(await store.messagesOf('f1'), isEmpty);
      expect(await store.messagesOf('f2'), hasLength(1));
    });
  });

  group('screens', () {
    late FriendsController hub;
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => hub.dispose());

    Future<void> boot(WidgetTester t, List<ChatMessage> seed) async {
      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('/me/e2ee-key')) return _json({'publicKey': null});
        if (path.endsWith('/me/friends')) return _json({'friends': [{'id': 'f1', 'name': 'Bình', 'username': 'binh', 'isAdmin': false}]});
        if (path.endsWith('/me/customer-codes')) return _json({'codes': []});
        if (path.endsWith('/me/calls')) return _json({'calls': [], 'unseenMissed': {}});
        if (path.endsWith('/me/unread')) return _json({'support': 0});
        if (path.endsWith('/me')) return _json({'id': 'me', 'name': 'An', 'role': 'user'});
        return http.Response('{}', 404);
      });
      final store = MemoryChatStore();
      for (final m in seed) {
        await store.putMessage(m);
      }
      hub = FriendsController(api: ApiClient(AuthStore(), client: client), auth: AuthStore(), socket: _Sock())
        ..storeFactory = ((_) async => store)
        ..vault = MemoryKeyVault();
      await hub.start();
    }

    Widget host(Widget child) => MaterialApp(home: MessagingScope(hub: hub, child: child));

    testWidgets('long press opens the menu; Trả lời shows the bar; Ghim shows the pin bar', (t) async {
      await t.runAsync(() => boot(t, [msg('a', 'tin của bạn'), msg('b', 'tin của tôi', mine: true, at: 2000)]));
      await t.pumpWidget(host(ChatPage(controller: hub, friend: hub.friends.first)));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      expect(find.text('tin của bạn'), findsOneWidget);

      await t.longPress(find.text('tin của bạn'));
      await t.pumpAndSettle();
      for (final label in ['Trả lời', 'Sao chép', 'Ghim', 'Chuyển tiếp', 'Xoá', 'Chọn']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }

      await t.tap(find.text('Trả lời'));
      await t.pumpAndSettle();
      expect(find.text('↪ Trả lời: tin của bạn'), findsOneWidget);

      await t.longPress(find.text('tin của tôi'));
      await t.pumpAndSettle();
      await t.tap(find.text('Ghim'));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.text('📌 tin của tôi'), findsOneWidget);
      expect(await hub.chat!.pinsOf('f1'), ['b']);
    });

    testWidgets('select mode: ticks, the button becomes "Nhập số (N)" and sends the picked text to Nhập số; only text messages can be picked', (t) async {
      await t.runAsync(() => boot(t, [msg('a', 'một'), msg('b', 'hai', mine: true, at: 2000)]));
      await t.pumpWidget(host(ChatPage(controller: hub, friend: hub.friends.first)));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      expect(find.text('Nhập số'), findsOneWidget);
      await t.tap(find.text('Nhập số'));
      await t.pump();
      expect(find.byType(Checkbox), findsNWidgets(2));
      expect(find.text('Đã chọn 0'), findsOneWidget);
      expect(find.text('Nhập số'), findsOneWidget); // nothing picked yet
      await t.tap(find.byType(Checkbox).first);
      await t.pump();
      expect(find.text('Đã chọn 1'), findsOneWidget);
      expect(find.text('Nhập số (1)'), findsOneWidget);
      await t.tap(find.text('Chọn tất cả'));
      await t.pump();
      expect(find.text('Đã chọn 2'), findsOneWidget);
      expect(find.text('Nhập số (2)'), findsOneWidget);
      // the picked messages (display order) go to the Nhập số quick-entry box
      await t.tap(find.text('Nhập số (2)'));
      await t.pump();
      expect(ChatPrefillHub.instance.take()?.text, 'một\nhai');
      ChatPrefillHub.instance.take();
    });

    testWidgets('select mode: "Hủy" leaves select mode', (t) async {
      await t.runAsync(() => boot(t, [msg('a', 'một')]));
      await t.pumpWidget(host(ChatPage(controller: hub, friend: hub.friends.first)));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pump();
      await t.tap(find.text('Nhập số'));
      await t.pump();
      await t.tap(find.text('Hủy'));
      await t.pump();
      expect(find.byType(Checkbox), findsNothing);
      expect(find.text('Nhập số'), findsOneWidget);
    });

    testWidgets('message list: Sửa, Thêm menu, avatar initial, archive hides the chat', (t) async {
      await t.runAsync(() => boot(t, [msg('a', 'chào')]));
      await t.pumpWidget(host(const FriendsScreen()));
      await t.pumpAndSettle();
      await t.tap(find.text('Để sau')); // the first-visit notification prompt
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.text('Sửa'), findsOneWidget);
      expect(find.text('Thêm'), findsOneWidget);
      expect(find.text('B'), findsOneWidget); // round avatar with the initial
      await t.tap(find.text('Thêm'));
      await t.pumpAndSettle();
      for (final l in ['Tin nhắn mới', 'Nhóm mới', 'Danh bạ mới']) {
        expect(find.text(l), findsOneWidget);
      }
      await t.tap(find.text('Nhóm mới'));
      await t.pumpAndSettle();
      expect(t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Tạo nhóm')).onPressed, isNull);
      await t.tap(find.text('Đóng'));
      await t.pumpAndSettle();

      await t.tap(find.text('Sửa'));
      await t.pump();
      expect(find.text('Xong'), findsOneWidget);
      await t.tap(find.byType(Checkbox).first);
      await t.pump();
      expect(find.text('Lưu trữ (1)'), findsOneWidget);
      await t.runAsync(() async {
        await hub.chat!.setArchived(['f1'], true);
      });
      await t.pumpAndSettle();
      expect(find.text('Đã lưu trữ (1)'), findsNothing); // still in edit mode, bar shown instead
      await t.tap(find.text('Xong'));
      await t.pumpAndSettle();
      expect(find.text('Đã lưu trữ (1)'), findsOneWidget);
      expect(find.text('Bình'), findsNothing);
    });
  });
}
