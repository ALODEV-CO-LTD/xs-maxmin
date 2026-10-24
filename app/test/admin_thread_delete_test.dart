import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/admin/messages/admin_messages_logic.dart';
import 'package:mamba_app/features/admin/messages/admin_thread_page.dart';
import 'package:provider/provider.dart';

http.Response _j(Object o) => http.Response(
  jsonEncode(o),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  testWidgets(
    'Admin can delete one customer message, then clear the whole thread',
    (tester) async {
      final calls = <String>[];
      var msgs = [
        {
          'id': 'm1',
          'sender': 'user',
          'content': 'Xin chào admin',
          'createdAt': '2026-10-10T10:00:00Z',
        },
        {
          'id': 'm2',
          'sender': 'admin',
          'content': 'Chào bạn',
          'createdAt': '2026-10-10T10:05:00Z',
        },
      ];
      final api = ApiClient(
        AuthStore()..token = 't',
        client: MockClient((r) async {
          if (r.method == 'DELETE') {
            calls.add('${r.method} ${r.url.path}');
            if (r.url.path.endsWith('/m1')) msgs = [msgs[1]];
            if (r.url.path.endsWith('/u1')) msgs = [];
            return _j({'ok': true});
          }
          if (r.url.path == '/api/admin/messages/u1') {
            return _j({'messages': msgs});
          }
          return _j({});
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Provider<ApiClient>.value(
            value: api,
            child: AdminThreadPage(
              conversation: Conversation(
                userId: 'u1',
                userName: 'An',
                username: 'an',
                awaitingReply: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Xin chào admin'), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-message')).first);
      await tester.pumpAndSettle();
      expect(find.text('Xoá tin nhắn'), findsOneWidget);
      await tester.tap(find.text('Xoá').last);
      await tester.pumpAndSettle();
      expect(calls, ['DELETE /api/admin/messages/u1/m1']);
      expect(find.text('Xin chào admin'), findsNothing);
      expect(find.text('Chào bạn'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clear-thread')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xoá').last);
      await tester.pumpAndSettle();
      expect(calls.last, 'DELETE /api/admin/messages/u1');
      expect(find.text('Chào bạn'), findsNothing);
      expect(find.text('Chưa có tin nhắn nào'), findsOneWidget);
    },
  );
}
