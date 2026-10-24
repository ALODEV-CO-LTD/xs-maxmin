import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/shell/maintenance_gate.dart';

http.Response _j(Object o, [int code = 200]) => http.Response(
  jsonEncode(o),
  code,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('a 503 {maintenance: true} fills ApiClient.maintenance; the notice feed clears it', () async {
    var down = true;
    final api = ApiClient(
      AuthStore()..token = 't',
      client: MockClient((r) async {
        if (r.url.path == '/api/announcements') {
          return _j({
            'maintenance': {'enabled': down, 'message': 'Bảo trì 23h'},
            'announcements': [],
          });
        }
        return down
            ? _j({'error': 'Bảo trì 23h', 'maintenance': true}, 503)
            : _j({'ok': true});
      }),
    );
    await expectLater(api.get('/me/entries'), throwsA(isA<ApiError>()));
    expect(api.maintenance.value, 'Bảo trì 23h');
    down = false;
    final res = await api.get('/announcements') as Map;
    api.applyNotices(res['maintenance']);
    expect(api.maintenance.value, isNull);
    api.applyNotices({'enabled': true, 'message': ''});
    expect(
      api.maintenance.value,
      'Hệ thống đang bảo trì, vui lòng quay lại sau.',
    );
  });

  Future<(ApiClient, AuthStore, bool Function())> pump(
    WidgetTester tester, {
    String role = 'user',
  }) async {
    var down = true;
    final auth = AuthStore()
      ..token = 't'
      ..role = role;
    final api = ApiClient(
      auth,
      client: MockClient(
        (r) async => _j({
          'maintenance': {'enabled': down, 'message': 'Bảo trì 23h'},
          'announcements': [],
        }),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MaintenanceGate(
          api: api,
          auth: auth,
          recheck: const Duration(seconds: 5),
          child: const Scaffold(body: Text('ứng dụng')),
        ),
      ),
    );
    return (api, auth, () => down = false);
  }

  testWidgets(
    'a customer sees the full-screen notice, and it goes away once maintenance is over',
    (tester) async {
      final (api, _, _) = await pump(tester);
      expect(find.text('Hệ thống đang bảo trì'), findsNothing);
      api.maintenance.value = 'Bảo trì 23h';
      await tester.pump();
      expect(find.text('Hệ thống đang bảo trì'), findsOneWidget);
      expect(find.byKey(const Key('maintenance-message')), findsOneWidget);
      api.applyNotices({'enabled': false});
      await tester.pump();
      expect(find.text('Hệ thống đang bảo trì'), findsNothing);
      expect(find.text('ứng dụng'), findsOneWidget);
    },
  );

  testWidgets('an admin is never covered', (tester) async {
    final (api, _, _) = await pump(tester, role: 'admin');
    api.maintenance.value = 'Bảo trì 23h';
    await tester.pump();
    expect(find.text('Hệ thống đang bảo trì'), findsNothing);
  });

  testWidgets('signing out forgets the notice', (tester) async {
    final (api, auth, _) = await pump(tester);
    api.maintenance.value = 'Bảo trì 23h';
    await tester.pump();
    auth
      ..token = null
      ..notifyListeners();
    await tester.pump();
    expect(api.maintenance.value, isNull);
  });
}
