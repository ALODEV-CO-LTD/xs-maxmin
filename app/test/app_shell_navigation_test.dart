import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/app.dart';
import 'package:mamba_app/core/admin_session.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/lottery_stations.dart';
import 'package:mamba_app/core/mask_store.dart';
import 'package:mamba_app/core/scoring_config_bus.dart';
import 'package:mamba_app/core/theme.dart';
import 'package:mamba_app/features/account/privacy/privacy_store.dart';
import 'package:mamba_app/features/calc/calc_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthStore {
  _Auth(String role) {
    ready = true;
    token = 'tok';
    this.role = role;
  }
}

http.Response _j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});

Future<http.Response> _handler(http.Request r) async {
  switch ('${r.method} ${r.url.path}') {
    case 'GET /api/me/entries':
      return _j({'entries': [], 'total': 0, 'hasMore': false});
    case 'GET /api/me/customers':
      return _j({
        'customers': [
          {'id': 'c1', 'name': 'An', 'phone': '0901', 'scoringRates': null, 'defaultStation': null},
        ],
      });
    case 'GET /api/me/scoring-settings':
      return _j({
        'rates': {
          'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2},
          'lo': {'rate': 20, 'tiers': ['dacBiet', 'giaiNhat'], 'digits': 2},
        },
      });
    case 'GET /api/me/syntax-templates':
      return _j({'templates': []});
  }
  return _j({'error': 'nope'}, 404);
}

Future<GoRouter> _pump(WidgetTester tester, {String role = 'user'}) async {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final auth = _Auth(role);
  final router = buildRouter(auth);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthStore>.value(value: auth),
      Provider<ApiClient>.value(value: ApiClient(auth, client: MockClient(_handler))),
      ChangeNotifierProvider<LotteryStations>(create: (_) => LotteryStations()),
      ChangeNotifierProvider<MaskStore>(create: (_) => MaskStore()),
      ChangeNotifierProvider<AdminSession>(create: (_) => AdminSession()),
      ChangeNotifierProvider<PrivacyStore>(create: (_) => PrivacyStore()),
      ChangeNotifierProvider<ScoringConfigBus>(create: (_) => ScoringConfigBus()),
    ],
    child: MaterialApp.router(theme: darkTheme, routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

/// Screens with a spinner never settle: a few frames are enough.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Finder _nav(String label) => find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
Finder _tab(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the bottom bar has five items in order and no "Thêm"; the app opens on Tổng quan', (tester) async {
    await _pump(tester);
    final labels = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).map((d) => d.label).toList();
    expect(labels, ['Tổng quan', 'Tính toán', 'Bạn bè', 'Cấu hình', 'Tài khoản']);
    expect(_nav('Thêm'), findsNothing);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
    // the statistics are the home page
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Tổng quan')), findsOneWidget);
  });

  testWidgets('Tính điểm opens on the customer and day chosen in Nhập số (no second pick)', (tester) async {
    await _pump(tester);
    await tester.tap(_nav('Tính toán'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('-- Chọn khách hàng --'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('An').last);
    await tester.pumpAndSettle();
    await tester.tap(_tab('Tính điểm'));
    await _settle(tester);
    await tester.pumpAndSettle();
    // the customer is already chosen there: the "pick a customer" hint is gone, only customer + day are asked
    expect(find.text('Chọn khách hàng ở trên để xem điểm ra của họ.'), findsNothing);
    expect(find.text('Xổ số'), findsNothing);
    expect(find.text('Thời gian'), findsNothing);
  });

  testWidgets('Tính toán has the four sub-tabs in order and each keeps its state', (tester) async {
    await _pump(tester);
    await tester.tap(_nav('Tính toán'));
    await tester.pumpAndSettle();
    final tabs = tester.widget<TabBar>(find.byType(TabBar)).tabs.map((t) => (t as Tab).text).toList();
    expect(tabs, ['Nhập số', 'Kết quả', 'Tính điểm', 'Khách hàng']);
    expect(find.text('Chọn khách hàng để xem và nhập số liệu.'), findsOneWidget); // Nhập số

    await tester.tap(find.text('-- Chọn khách hàng --'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('An').last);
    await tester.pumpAndSettle();
    expect(find.text('Thêm số liệu mới'), findsOneWidget);

    await tester.tap(_tab('Khách hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm khách hàng'), findsOneWidget);
    expect(find.text('Cấu hình tính điểm mặc định'), findsNothing); // moved to the Cấu hình tab
    expect(find.byTooltip('Cấu hình tính điểm'), findsOneWidget); // the customer's own config stays (an icon button)

    await tester.tap(_tab('Nhập số'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm số liệu mới'), findsOneWidget); // the picked customer is still there

    await tester.tap(_tab('Kết quả'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kết quả xổ số'), findsWidgets);
    await tester.tap(_tab('Tính điểm'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('old paths and links open the matching sub-tab of Tính toán', (tester) async {
    final router = await _pump(tester);
    router.go('/customers');
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 1);
    expect(find.text('Thêm khách hàng'), findsOneWidget);

    router.go(calcLocation('results', date: '2026-10-05'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kết quả xổ số'), findsWidgets);
    expect(find.text('Thêm khách hàng'), findsNothing);
    expect(find.text('05/10/2026'), findsWidgets);

    router.go('/entries');
    await tester.pumpAndSettle();
    expect(find.text('Chọn khách hàng để xem và nhập số liệu.'), findsOneWidget);
    router.go('/more');
    await tester.pumpAndSettle();
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 0);
  });

  testWidgets('Bạn bè, Cấu hình and Tài khoản are tabs (no back arrow)', (tester) async {
    await _pump(tester);
    await tester.tap(_nav('Bạn bè'));
    await _settle(tester);
    expect(find.text('Tin nhắn'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(_nav('Cấu hình'));
    await _settle(tester);
    expect(find.text('Cấu hình tính điểm mặc định'), findsOneWidget);
    expect(find.text('Giá tiền / 1 điểm'), findsWidgets); // the table, in view mode
    expect(find.text('Sửa'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);

    await tester.tap(_nav('Tài khoản'));
    await _settle(tester);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Tài khoản')), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(find.byTooltip('Đăng xuất'), findsOneWidget);
    expect(find.text('Hồ sơ'), findsOneWidget);
    expect(find.text('Thống kê'), findsNothing); // now the Tổng quan tab
  });

  testWidgets('an Admin keeps the Admin shell, with no customer bottom bar', (tester) async {
    final router = await _pump(tester, role: 'admin');
    expect(find.byType(NavigationBar), findsNothing);
    router.go('/overview');
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing); // sent back to /admin
  });
}
