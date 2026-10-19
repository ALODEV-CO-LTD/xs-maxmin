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
import 'package:mamba_app/core/format.dart';
import 'package:mamba_app/features/customers/customer_config_screen.dart';
import 'package:mamba_app/features/entries/entries_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});


/// A tiny fake server with state, so a whole flow (type -> save -> list -> offline -> sync) can run without installing.
class _Server {
  bool online = true;
  final List<Map<String, dynamic>> entries = [];
  final List<Map<String, dynamic>> posts = [];

  Future<http.Response> handle(http.Request r) async {
    if (!online) throw http.ClientException('no network');
    switch ('${r.method} ${r.url.path}') {
      case 'GET /api/me/entries':
        return _j({'entries': entries, 'total': entries.length, 'hasMore': false});
      case 'POST /api/me/entries':
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        posts.add(b);
        final e = {...b, 'id': b['clientId'] ?? 'e${entries.length + 1}', 'result': null, 'note': null, 'createdAt': 't', 'updatedAt': 't'};
        entries.add(e);
        return _j(e, 201);
      case 'GET /api/me/customers':
        return _j({
          'customers': [
            {'id': 'c1', 'name': 'An', 'phone': '', 'scoringRates': null, 'defaultStation': null},
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
}

Widget _app(_Server server, Widget child) {
  final auth = AuthStore()..token = 'h.${base64Url.encode(utf8.encode('{"sub":"u1"}')).replaceAll('=', '')}.s'; // the account id is the token's `sub`
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthStore>.value(value: auth),
      Provider<ApiClient>.value(value: ApiClient(auth, client: MockClient(server.handle))),
      ChangeNotifierProvider<LotteryStations>(create: (_) => LotteryStations()),
      ChangeNotifierProvider<MaskStore>(create: (_) => MaskStore()),
    ],
    child: MaterialApp(theme: darkTheme, home: Scaffold(body: child)),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402 * 3, 874 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _pickAn(WidgetTester tester) async {
  await tester.tap(find.text('-- Chọn khách hàng --'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('An').last);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Luồng: Nhập số -> lưu -> hiện trong danh sách, luôn ghi ngày hôm nay', (tester) async {
    _phone(tester);
    final server = _Server();
    await tester.pumpWidget(_app(server, const EntriesScreen()));
    await tester.pumpAndSettle();
    await _pickAn(tester);

    // the date is today and cannot be changed; the old filters / copy / pick-to-delete are gone
    expect(find.text(viDate(todayIso())), findsWidgets);
    for (final gone in ['Mọi hạng mục', 'Tất cả khách hàng', 'Chọn để xoá']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.textContaining('Sao chép'), findsNothing);
    expect(find.byType(Checkbox), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Số'), '12');
    await tester.enterText(find.widgetWithText(TextField, 'Điểm'), '5');
    await tester.ensureVisible(find.text('Thêm số liệu'));
    await tester.tap(find.text('Thêm số liệu'));
    await tester.pumpAndSettle();

    expect(server.posts, hasLength(1));
    expect(server.posts.single['entryDate'], todayIso());
    expect(server.posts.single['customerName'], 'An');
    expect(server.posts.single['value'], '12');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Luồng: mất mạng -> số liệu chờ đồng bộ -> có mạng -> Đồng bộ ngay', (tester) async {
    _phone(tester);
    final server = _Server();
    await tester.pumpWidget(_app(server, const EntriesScreen()));
    await tester.pumpAndSettle();
    await _pickAn(tester);

    server.online = false;
    await tester.enterText(find.widgetWithText(TextField, 'Số'), '34');
    await tester.enterText(find.widgetWithText(TextField, 'Điểm'), '7');
    await tester.ensureVisible(find.text('Thêm số liệu'));
    await tester.tap(find.text('Thêm số liệu'));
    await tester.pumpAndSettle();
    expect(server.posts, isEmpty);
    expect(find.textContaining('đang chờ đồng bộ'), findsWidgets);

    server.online = true;
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 600)); // back to the top, where the banner is
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đồng bộ ngay'));
    await tester.pumpAndSettle();
    expect(server.posts, hasLength(1));
    expect(server.posts.single['value'], '34');
    expect(server.posts.single['entryDate'], todayIso());
    expect(find.textContaining('đang chờ đồng bộ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Luồng: Cấu hình tính điểm -> Sửa -> đổi giá -> Huỷ trả về như cũ; không có dòng Đề thứ hai', (tester) async {
    _phone(tester);
    final server = _Server();
    await tester.pumpWidget(_app(server, const DefaultConfigScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Sửa'), findsOneWidget);
    expect(find.textContaining('chọn ở ô Hạng mục'), findsNothing);

    await tester.tap(find.text('Sửa'));
    await tester.pumpAndSettle();
    expect(find.text('Huỷ'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Giá tiền / 1 điểm').first, '15000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    expect(find.text('Sửa'), findsOneWidget);
    expect(find.text('15.000'), findsNothing);
    expect(find.text('23.000'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
