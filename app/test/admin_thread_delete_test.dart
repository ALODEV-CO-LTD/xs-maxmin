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
    'Admin can delete only ITS OWN replies; the message becomes "Tin nhắn đã bị xoá" in place',
    (tester) async {
      final calls = <String>[];
      var msgs = <Map<String, dynamic>>[
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
        {
          'id': 'm3',
          'sender': 'admin',
          'content': '',
          'createdAt': '2026-10-10T10:06:00Z',
          'deleted': true,
        },
      ];
      final api = ApiClient(
        AuthStore()..token = 't',
        client: MockClient((r) async {
          if (r.method == 'DELETE') {
            calls.add('${r.method} ${r.url.path}');
            msgs = [
              for (final m in msgs)
                m['id'] == 'm2' ? {...m, 'content': '', 'deleted': true} : m,
            ];
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

      // m1 is the customer's (no trash), m2 is Admin's (trash), m3 is already deleted (notice, no trash)
      expect(find.text('Xin chào admin'), findsOneWidget);
      expect(find.byKey(const Key('delete-message')), findsOneWidget);
      expect(find.byKey(const Key('clear-thread')), findsNothing);
      expect(find.byKey(const Key('deleted-message')), findsOneWidget);

      await tester.tap(find.byKey(const Key('delete-message')));
      await tester.pumpAndSettle();
      expect(find.text('Xoá tin nhắn'), findsOneWidget);
      await tester.tap(find.text('Xoá').last);
      await tester.pumpAndSettle();
      expect(calls, ['DELETE /api/admin/messages/u1/m2']);
      expect(find.text('Chào bạn'), findsNothing);
      expect(find.byKey(const Key('deleted-message')), findsNWidgets(2));
      expect(find.byKey(const Key('delete-message')), findsNothing);
      expect(find.text('Xin chào admin'), findsOneWidget);
    },
  );
}
