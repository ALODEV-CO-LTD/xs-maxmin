import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/widgets/app_dialog.dart';
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
    // quick-entry box (message or photo): parse -> preview (nothing is saved)
    expect(find.text('Chọn ảnh'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nhập nhanh: tin nhắn hoặc ảnh của khách'), 'de 12 34 x 10\n56 x 3\n77');
    await tester.pump();
    await tester.ensureVisible(find.text('Phân tích'));
    await tester.tap(find.text('Phân tích'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã chọn 3/4 dòng'), findsOneWidget); // the line without a score is unticked
    expect(find.textContaining('chưa chắc chắn (tô vàng)'), findsOneWidget);

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
    expect(find.textContaining('Khách thuộc miền nào'), findsOneWidget);
    expect(find.text('Chưa chọn (tính như khách Bắc)'), findsOneWidget);
    expect(find.text('Giá tiền / 1 điểm'), findsWidgets);
    expect(find.text('Giá trúng / 1 điểm'), findsWidgets);
    expect(find.text('Bao lô 2 số'), findsOneWidget);
    expect(find.text('Lấy số: 2 số cuối của cả 27 lô'), findsOneWidget);
    expect(find.textContaining('Đề'), findsWidgets);
    expect(find.textContaining('4 cách đánh'), findsOneWidget); // the Đề group
    expect(find.textContaining('3 cách đánh'), findsNWidgets(3)); // Lô, Xiên, Lô trượt
    expect(find.textContaining('2 cách đánh'), findsOneWidget); // Thần tài
    // view mode: text only (✓ for a row the customer uses), a "Sửa" button and no footer
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('23.000'), findsWidgets); // bao lô of the account's older Lô entry (23.000 đ/điểm), vi-VN thousands
    expect(find.text('L, l, lo, lô, x, X'), findsOneWidget);
    expect(find.text('✓'), findsWidgets);
    expect(find.text('Kiểu đánh khác'), findsNothing);
    expect(find.text('Huỷ'), findsNothing);
    expect(find.text('Miền Nam'), findsOneWidget);
    await tester.tap(find.text('Miền Nam'));
    await tester.pumpAndSettle();
    expect(find.text('460.000'), findsWidgets);

    // edit mode
    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    expect(find.byType(Switch), findsWidgets); // "Dùng"
    expect(find.byType(TextFormField), findsWidgets);
    expect(find.byKey(const ValueKey('group-other')), findsOneWidget); // empty groups show while editing
    expect(find.text('+ Thêm cách đánh'), findsWidgets);
    expect(find.byKey(const ValueKey('add-de')), findsOneWidget);
    expect(find.text('Bỏ cấu hình riêng'), findsOneWidget);
    expect(find.text('Lưu cấu hình khách này'), findsOneWidget);
    final price = find.widgetWithText(TextFormField, 'Giá tiền / 1 điểm').first;
    await tester.enterText(price, '15000');
    await tester.pumpAndSettle();

    // + Thêm cách đánh in the Đề group: a new custom row, shown inside that group
    await tester.ensureVisible(find.byKey(const ValueKey('add-de')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-de')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Thêm vào "Đề"'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(AppDialog), matching: find.widgetWithText(TextField, 'Tên')), 'Đề 3 số');
    await tester.enterText(find.descendant(of: find.byType(AppDialog), matching: find.widgetWithText(TextField, 'Ký hiệu')), 'd3');
    await tester.tap(find.text('Thêm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 cách đánh'), findsOneWidget); // Đề: 4 standard + the new one
    expect(find.text('Xoá'), findsNWidgets(2)); // only the custom rows (the older Đề and the new one) can be removed by a customer

    // "Chỉnh lấy số" of Bao lô 2 số: the panel with the prizes of Miền Nam
    final srcBtn = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('srcbtn-') && (w.key! as ValueKey<String>).value.endsWith('-lo'));
    await tester.ensureVisible(srcBtn);
    await tester.pumpAndSettle();
    await tester.tap(srcBtn);
    await tester.pumpAndSettle();
    expect(find.textContaining('Giải tám (1 lô × 2 số)'), findsOneWidget);
    expect(find.textContaining('Đang lấy: 2 số cuối của cả 18 lô'), findsOneWidget);
    expect(find.text('Về mặc định'), findsOneWidget);

    // Huỷ: back to the view with the saved value
    await tester.ensureVisible(find.text('Huỷ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Sửa'), findsOneWidget);
    expect(find.text('15.000'), findsNothing);
    expect(find.text('Huỷ'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
