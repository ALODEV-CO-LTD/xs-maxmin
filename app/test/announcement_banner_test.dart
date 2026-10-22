import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/widgets/svg_icon.dart';

import 'svg_finder.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/shell/announcement_banner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _j(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});

Future<void> _pump(WidgetTester tester, Map<String, dynamic> body) async {
  final auth = AuthStore()..token = 't';
  await tester.pumpWidget(MaterialApp(
    home: Provider<ApiClient>.value(
      value: ApiClient(auth, client: MockClient((r) async => r.url.path == '/api/announcements' ? _j(body) : _j({'error': 'x'}))),
      child: const Scaffold(body: Column(children: [AnnouncementBanner()])),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

void main() {
  test('state parses maintenance and announcements, skipping rows without an id', () {
    final s = NoticesState.fromJson({
      'maintenance': {'enabled': true, 'message': 'Nâng cấp'},
      'announcements': [
        {'id': 'a', 'kind': 'policy', 'title': 'T', 'body': 'B'},
        {'kind': 'info', 'title': 'no id'},
        {'id': 'b', 'kind': 'maintenance', 'title': 'M'},
      ],
    });
    expect(s.maintenance, isTrue);
    expect(s.maintenanceMessage, 'Nâng cấp');
    expect(s.announcements.map((a) => a.id), ['a', 'b']);
    expect(s.announcements.first.kindLabel, 'Chính sách');
    expect(s.visible({'a'}).map((a) => a.id), ['b']);
    expect(NoticesState.fromJson({}).maintenance, isFalse);
  });

  testWidgets('shows notices, hides one and remembers it on the device', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final body = {
      'maintenance': {'enabled': true, 'message': ''},
      'announcements': [
        {'id': 'a', 'kind': 'info', 'title': 'Lịch nghỉ', 'body': 'Nghỉ lễ'},
      ],
    };
    await _pump(tester, body);
    expect(find.text('Hệ thống đang bảo trì.'), findsOneWidget);
    expect(find.text('Thông báo: Lịch nghỉ'), findsOneWidget);
    // The maintenance notice cannot be closed, the announcement can.
    expect(find.byTooltip('Ẩn thông báo'), findsOneWidget);
    await tester.tap(find.byTooltip('Ẩn thông báo'));
    await tester.pump();
    expect(find.text('Thông báo: Lịch nghỉ'), findsNothing);
    expect(find.text('Hệ thống đang bảo trì.'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getStringList(dismissedNoticesKey), ['a']);

    // A new start of the app: still hidden.
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, body);
    expect(find.text('Thông báo: Lịch nghỉ'), findsNothing);
  });

  testWidgets('nothing on screen when there is nothing to show', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await _pump(tester, {'maintenance': {'enabled': false, 'message': ''}, 'announcements': []});
    expect(find.byType(Card), findsNothing);
    expect(bySvg(AppSvg.megaphone), findsNothing);
  });
}
