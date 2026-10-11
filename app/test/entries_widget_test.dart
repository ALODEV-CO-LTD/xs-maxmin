import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/lottery_stations.dart';
import 'package:mamba_app/core/mask_store.dart';
import 'package:mamba_app/core/theme.dart';
import 'package:mamba_app/features/customers/customers_screen.dart';
import 'package:mamba_app/features/entries/entries_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});

Future<http.Response> _handler(http.Request r) async {
  switch ('${r.method} ${r.url.path}') {
    case 'GET /api/me/entries':
      return _j({
        'entries': [
          {'id': 'e1', 'customerName': 'An', 'entryDate': '2026-10-10', 'value': '12', 'score': '5000', 'result': '', 'betType': 'de', 'station': 'mb', 'note': 'gấp', 'createdAt': 't', 'updatedAt': 't'},
          {'id': 'e2', 'customerName': 'An', 'entryDate': '2026-10-10', 'value': '45', 'score': '3', 'result': '60', 'betType': 'lo', 'station': 'mn', 'note': null, 'createdAt': 't', 'updatedAt': 't'},
        ],
        'total': 2,
        'hasMore': false,
      });
    case 'GET /api/me/customers':
      return _j({
        'customers': [
          {'id': 'c1', 'name': 'An', 'phone': '0901', 'scoringRates': null, 'defaultStation': null},
          {'id': 'c2', 'name': 'Bình', 'phone': '', 'scoringRates': null, 'defaultStation': 'mn'},
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
    case 'GET /api/me':
      return _j({'package': {'isActive': true}, 'stats': {}});
  }
  return _j({'error': 'nope'}, 404);
}

Widget _app(Widget child) {
  final auth = AuthStore();
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthStore>.value(value: auth),
      Provider<ApiClient>.value(value: ApiClient(auth, client: MockClient(_handler))),
      ChangeNotifierProvider<LotteryStations>(create: (_) => LotteryStations()),
      ChangeNotifierProvider<MaskStore>(create: (_) => MaskStore()),
    ],
    child: MaterialApp(theme: darkTheme, home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Nhập số: pick a customer, see the form and the list', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const EntriesScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Chọn khách hàng để xem và nhập số liệu.'), findsOneWidget);

    await tester.tap(find.text('-- Chọn khách hàng --'));
    await tester.pumpAndSettle();
    expect(find.text('Bình'), findsOneWidget);
    await tester.tap(find.text('An').last);
    await tester.pumpAndSettle();

    expect(find.text('Thêm số liệu mới'), findsOneWidget);
    expect(find.text('Thêm số liệu'), findsOneWidget);
    // paste importer: parse -> preview (nothing is saved)
    await tester.tap(find.text('Từ tin nhắn'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nội dung tin nhắn'), 'de 12 34 x 10\n56 x 3\n77');
    await tester.pump();
    await tester.tap(find.text('Phân tích'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã chọn 3/4 dòng'), findsOneWidget); // the line without a score is unticked
    expect(find.textContaining('chưa chắc chắn (tô vàng)'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop(); // close the sheet
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Thống kê: An'), 400, scrollable: find.byType(Scrollable).first);
    expect(find.text('Thống kê: An'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Khách hàng: list with totals and search', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(const CustomersScreen()));
    await tester.pumpAndSettle();
    expect(find.text('An'), findsOneWidget);
    expect(find.text('Bình'), findsOneWidget);
    expect(find.text('+ Thêm khách hàng'), findsNothing);
    expect(find.text('Thêm khách hàng'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'binh');
    await tester.pumpAndSettle();
    expect(find.text('An'), findsNothing);
    expect(find.text('Bình'), findsOneWidget);

    await tester.tap(find.text('Cấu hình tính điểm'));
    await tester.pumpAndSettle();
    expect(find.text('Tỉ lệ ăn'), findsWidgets);
    expect(find.text('Miền Nam'), findsOneWidget);
    await tester.tap(find.text('Miền Nam'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
