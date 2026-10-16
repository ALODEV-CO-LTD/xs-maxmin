import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/features/account/account_controller.dart';
import 'package:mamba_app/features/account/account_data_tab.dart';
import 'package:mamba_app/features/account/account_devices_tab.dart';
import 'package:mamba_app/features/account/me_profile.dart';
import 'package:mamba_app/features/account/privacy/privacy_store.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _j(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});

Future<AccountController> _pump(WidgetTester tester, Widget Function(AccountController) tab, {String role = 'user'}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = AuthStore()..token = 't';
  final api = ApiClient(auth, client: MockClient((r) async {
    if (r.url.path == '/api/me/sessions') return _j({'sessions': []});
    if (r.url.path == '/api/me/deletion-schedules') return _j({'schedules': []});
    if (r.url.path == '/api/me/customers') return _j({'customers': []});
    return _j({});
  }));
  final ctl = AccountController(api)..me = MeProfile(name: 'An', username: 'an', role: role);
  await tester.pumpWidget(MultiProvider(
    providers: [Provider<ApiClient>.value(value: api), ChangeNotifierProvider<PrivacyStore>(create: (_) => PrivacyStore())],
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: tab(ctl)))),
  ));
  await tester.pump();
  await tester.pump();
  return ctl;
}

void main() {
  testWidgets('Thiết bị & riêng tư holds the recovery code (customers only)', (tester) async {
    await _pump(tester, (c) => AccountDevicesTab(ctl: c));
    expect(find.text('Mã khôi phục'), findsOneWidget);
    expect(find.text('Thiết bị đang đăng nhập'), findsOneWidget);
  });

  testWidgets('Admin has no recovery code card', (tester) async {
    await _pump(tester, (c) => AccountDevicesTab(ctl: c), role: 'admin');
    expect(find.text('Mã khôi phục'), findsNothing);
  });

  testWidgets('Dữ liệu holds the deletion schedules and the wipe, not the recovery code', (tester) async {
    await _pump(tester, (c) => AccountDataTab(ctl: c));
    expect(find.text('Lịch xoá dữ liệu'), findsOneWidget);
    expect(find.text('Các lịch xoá'), findsOneWidget);
    expect(find.text('Chưa có lịch xoá nào.'), findsOneWidget);
    expect(find.text('Xoá toàn bộ dữ liệu'), findsWidgets);
    expect(find.text('Mã khôi phục'), findsNothing);
  });
}
