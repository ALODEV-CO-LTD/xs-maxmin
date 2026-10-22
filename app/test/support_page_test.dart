import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/widgets/svg_icon.dart';

import 'svg_finder.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/support/support_page.dart';
import 'package:provider/provider.dart';

http.Response _j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});

void main() {
  testWidgets('support thread: loads oldest first, marks read, sends a message', (tester) async {
    final calls = <String>[];
    Map<String, dynamic>? sent;
    final handler = MockClient((r) async {
      calls.add('${r.method} ${r.url.path}');
      if (r.method == 'GET' && r.url.path == '/api/me/messages') {
        return _j({
          'messages': [
            {'id': '1', 'sender': 'user', 'content': 'Cho hỏi về gói', 'createdAt': '2026-10-10T01:00:00Z'},
            {'id': '2', 'sender': 'admin', 'content': 'Chào bạn, mình hỗ trợ ngay', 'createdAt': '2026-10-10T02:00:00Z'},
          ],
        });
      }
      if (r.method == 'POST' && r.url.path == '/api/me/messages') {
        sent = jsonDecode(r.body) as Map<String, dynamic>;
        return _j({'id': '3', 'sender': 'user', 'content': sent!['content'], 'createdAt': '2026-10-10T03:00:00Z'}, 201);
      }
      if (r.url.path == '/api/me/unread/read') return _j({'ok': true});
      return _j({'error': 'nope'}, 404);
    });
    final auth = AuthStore()..token = 't';
    await tester.pumpWidget(MaterialApp(
      home: Provider<ApiClient>.value(value: ApiClient(auth, client: handler), child: const SupportPage()),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Hỗ trợ từ Admin'), findsOneWidget);
    final mine = tester.getTopLeft(find.text('Cho hỏi về gói'));
    final admin = tester.getTopLeft(find.text('Chào bạn, mình hỗ trợ ngay'));
    expect(mine.dy, lessThan(admin.dy)); // old on top, new at the bottom
    expect(find.text('Admin'), findsOneWidget); // sender label on the Admin's bubble only
    expect(calls, contains('POST /api/me/unread/read'));

    await tester.enterText(find.byType(TextField), '  Cảm ơn  ');
    await tester.pump();
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pump();
    await tester.pump();
    expect(sent, {'content': 'Cảm ơn'});
    expect(find.text('Cảm ơn'), findsWidgets);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox()); // stops the refresh timer
  });

  testWidgets('send is disabled while the box is empty', (tester) async {
    final auth = AuthStore()..token = 't';
    await tester.pumpWidget(MaterialApp(
      home: Provider<ApiClient>.value(value: ApiClient(auth, client: MockClient((r) async => _j({'messages': []}))), child: const SupportPage()),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Chưa có tin nhắn nào'), findsOneWidget);
    final send = tester.widget<IconButton>(find.ancestor(of: bySvg(AppSvg.send), matching: find.byType(IconButton)));
    expect(send.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
