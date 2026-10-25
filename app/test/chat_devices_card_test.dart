import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/account/account_devices_tab.dart';
import 'package:provider/provider.dart';

class _Auth extends AuthStore {
  _Auth() {
    token = 'T';
    role = 'user';
    ready = true;
  }
}

http.Response _j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json; charset=utf-8'});

class _Server {
  final devices = <Map<String, dynamic>>[
    {'id': 'phone-AAAA-1234', 'createdAt': '2026-10-01T03:00:00.000Z', 'lastSeen': '2026-10-24T08:30:00.000Z'},
    {'id': 'tablet-BBBB-7K2M', 'createdAt': '2026-10-10T03:00:00.000Z', 'lastSeen': '2026-10-20T08:30:00.000Z'},
    {'id': 'legacy', 'createdAt': '2026-09-01T03:00:00.000Z', 'lastSeen': '2026-09-02T08:30:00.000Z'},
  ];
  final deleted = <String>[];
  bool failDelete = false;

  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    if (r.method == 'DELETE' && p.contains('/me/e2ee-devices/')) {
      if (failDelete) return _j({'error': 'Máy chủ đang bận'}, 500);
      final id = p.split('/').last;
      deleted.add(id);
      devices.removeWhere((d) => d['id'] == id);
      return _j({'ok': true});
    }
    if (p.endsWith('/me/e2ee-devices')) return _j({'devices': devices});
    return http.Response('{}', 404);
  }
}

void main() {
  late _Server server;

  Future<void> pump(WidgetTester t, {String? mine = 'phone-AAAA-1234'}) async {
    t.view.physicalSize = const Size(400 * 3, 1200 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    server = _Server();
    final api = ApiClient(_Auth(), client: MockClient(server.handle));
    await t.pumpWidget(MultiProvider(
      providers: [Provider<ApiClient>.value(value: api)],
      child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: ChatDevicesCard(thisDeviceId: mine)))),
    ));
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('lists every chat device, marks this one, and offers "Xoá" only for the others', (t) async {
    await pump(t);
    expect(find.text('Thiết bị nhắn tin'), findsOneWidget);
    expect(find.text('Thiết bị ·1234'), findsOneWidget);
    expect(find.text('Thiết bị ·7K2M'), findsOneWidget);
    expect(find.text('Bản app cũ (một khoá chung)'), findsOneWidget);
    expect(find.text('Thiết bị này'), findsOneWidget);
    expect(find.text('Xoá'), findsNWidgets(2)); // not for this device
  });

  testWidgets('removing a device asks first, then forgets it', (t) async {
    await pump(t);
    await t.tap(find.text('Xoá').first);
    await t.pumpAndSettle();
    expect(find.text('Xoá thiết bị nhắn tin'), findsOneWidget);
    expect(server.deleted, isEmpty);
    await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Xoá')));
    await t.pumpAndSettle();
    expect(server.deleted, hasLength(1));
    expect(find.text('Xoá'), findsOneWidget); // two devices left besides this one: one removable
    expect(find.text('Thiết bị này'), findsOneWidget);
  });

  testWidgets('"Huỷ" in the question removes nothing', (t) async {
    await pump(t);
    await t.tap(find.text('Xoá').first);
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Huỷ')));
    await t.pumpAndSettle();
    expect(server.deleted, isEmpty);
    expect(find.text('Xoá'), findsNWidgets(2));
  });

  testWidgets('a failed removal shows the server message and keeps the list', (t) async {
    await pump(t);
    server.failDelete = true;
    await t.tap(find.text('Xoá').first);
    await t.pumpAndSettle();
    await t.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Xoá')));
    await t.pumpAndSettle();
    expect(find.text('Máy chủ đang bận'), findsOneWidget);
    expect(find.text('Xoá'), findsNWidgets(2));
  });

  testWidgets('when this device is unknown (chat not started) every device can be removed', (t) async {
    await pump(t, mine: null);
    expect(find.text('Thiết bị này'), findsNothing);
    expect(find.text('Xoá'), findsNWidgets(3));
  });

  test('device names', () {
    expect(chatDeviceName({'id': 'abcdefgh-12ab'}), 'Thiết bị ·12AB');
    expect(chatDeviceName({'id': 'legacy'}), 'Bản app cũ (một khoá chung)');
  });
}
