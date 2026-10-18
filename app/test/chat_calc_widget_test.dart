// Màn Đối chiếu, Tính toán từ chat và Nhập số nhận nội dung từ chat.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/widgets/app_dropdown.dart';
import 'package:mamba_app/core/lottery_stations.dart';
import 'package:mamba_app/core/mask_store.dart';
import 'package:mamba_app/features/calc/calc_screen.dart';
import 'package:mamba_app/features/scoring/scoring_screen.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/chat_calc/chat_calc_services.dart';
import 'package:mamba_app/features/chat_calc/chat_decode_model.dart';
import 'package:mamba_app/features/chat_calc/chat_decode_screen.dart';
import 'package:mamba_app/features/chat_calc/chat_prefill.dart';
import 'package:mamba_app/features/entries/entries_controller.dart';
import 'package:mamba_app/features/entries/offline_store.dart';
import 'package:mamba_app/features/entries/quick_entry_box.dart';
import 'package:mamba_app/features/scoring/entry_model.dart';
import 'package:mamba_app/features/scoring/scoring_logic.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'scoring_fixtures.dart';

const _result = <String, dynamic>{
  'giaiTam': ['20'],
  'giaiBay': ['120'],
  'giaiSau': ['1234', '5678', '0020'],
  'giaiNam': ['9020'],
  'giaiTu': ['11111', '22222', '33333', '44444', '55555', '66666', '77720'],
  'giaiBa': ['12345', '23456'],
  'giaiNhi': ['34567'],
  'giaiNhat': ['45678'],
  'dacBiet': ['123456'],
};

class _Data implements ChatCalcData {
  _Data({this.results = const {}});
  final Map<String, LotteryResult> results;
  final asked = <String>[];
  @override
  Future<List<CustomerRec>> customers() async => const [CustomerRec(id: 'c1', name: 'An'), CustomerRec(id: 'c2', name: 'Bình', homeRegion: 'mn')];
  @override
  Future<RatesMap> accountRates() async => Map<String, dynamic>.from(defaultRates);
  @override
  Future<void> loadStations() async {}
  @override
  Future<LotteryResult?> result(String date, String station) async {
    asked.add('$date|$station');
    return results['$date|$station'];
  }
}

class _Sender implements ChatSender {
  final sent = <(String, String)>[];
  @override
  Future<({bool ok, String message})> send(String friendId, String text) async {
    sent.add((friendId, text));
    return (ok: true, message: 'Đã gửi báo cáo.');
  }
}

Future<void> _pumpScreen(WidgetTester tester, ChatCalcServices svc, {List<DecodeSource>? messages, String? date}) async {
  tester.view.physicalSize = const Size(360 * 3, 2200 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: ChatDecodeScreen(services: svc, friendId: 'f1', friendName: 'Khách A', initialDate: date, messages: messages ?? const [DecodeSource('m1', '20lo10 70lo5\nxin chào'), DecodeSource('m2', '45lo2')]),
  ));
  await tester.pumpAndSettle();
}

ChatCalcServices _svc(_Data data, MemoryChatMeta meta, _Sender? sender) => ChatCalcServices(data: data, meta: meta, sender: sender, stations: testStations());

void main() {
  testWidgets('Đối chiếu: tin gốc, bản giải mã sửa được, Khôi phục, Lưu bản sửa, bắt buộc chọn khách', (tester) async {
    final meta = MemoryChatMeta();
    await _pumpScreen(tester, _svc(_Data(), meta, null));
    expect(find.text('Tin 1'), findsOneWidget);
    expect(find.text('Tin 2'), findsOneWidget);
    expect(find.text('20lo10 70lo5'), findsOneWidget); // tin gốc, chỉ đọc
    expect(find.widgetWithText(TextField, '20lô10 70lô5'), findsOneWidget); // bản giải mã

    await tester.enterText(find.widgetWithText(TextField, '20lô10 70lô5'), '20lô100 70lô5');
    await tester.pump();
    expect(find.text('Khôi phục'), findsOneWidget);
    await tester.tap(find.text('Khôi phục'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '20lô10 70lô5'), findsOneWidget);
    expect(find.text('Khôi phục'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, '20lô10 70lô5'), '20lô100 70lô5');
    await tester.pump();
    await tester.tap(find.text('Lưu bản sửa'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã lưu bản sửa trên máy này'), findsOneWidget);
    expect(jsonDecode(meta.data['decode:m1']!)['lines'], ['20lô100 70lô5', 'xin chào']);
    expect(meta.data.containsKey('decode:m2'), isFalse);

    // chưa chọn khách: không sang Nhập số / Tính toán
    await tester.tap(find.text('Tính toán'));
    await tester.pumpAndSettle();
    expect(find.text('Hãy chọn khách hàng cho số liệu đã nhập trước khi tiếp tục.'), findsOneWidget);
    expect(find.text('Chọn đài tính toán'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Đối chiếu mở lại thấy bản đã sửa; Giải mã lại hỏi xác nhận rồi bỏ chỗ sửa', (tester) async {
    final meta = MemoryChatMeta()..data['decode:m1'] = jsonEncode({'original': '20lo10 70lo5\nxin chào', 'lines': ['20lô1 70lô5', 'xin chào']});
    await _pumpScreen(tester, _svc(_Data(), meta, null));
    expect(find.widgetWithText(TextField, '20lô1 70lô5'), findsOneWidget);
    await tester.tap(find.text('Giải mã lại'));
    await tester.pumpAndSettle();
    expect(find.textContaining('bỏ mọi chỗ bạn đã sửa'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Giải mã lại'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '20lô10 70lô5'), findsOneWidget);
    expect(find.textContaining('Đã giải mã lại'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Đối chiếu > Tính toán > chọn đài > báo cáo > Lưu, Copy, Gửi cho khách', (tester) async {
    final meta = MemoryChatMeta();
    final sender = _Sender();
    final data = _Data(results: {'2026-10-15|mn-dongnai': _result});
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clip = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await _pumpScreen(tester, _svc(data, meta, sender), messages: const [DecodeSource('m1', '20lo10\n99xx')], date: '2026-10-15');

    // chọn khách (ngày 15/10/2026)
    await tester.tap(find.byType(AppDropdown<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('An').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tính toán'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn đài tính toán'), findsOneWidget);
    expect(find.text('Khách hàng: An'), findsOneWidget);
    expect(find.text('Dùng kết quả Miền Bắc'), findsOneWidget);
    expect(find.text('Dùng kết quả đài Đồng Nai'), findsOneWidget);
    expect(find.text('Dùng kết quả đài Thừa Thiên Huế'), findsOneWidget); // tên đài lấy từ danh mục
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Xác nhận chọn đài')).onPressed, isNull); // chưa chọn thì chưa bấm được

    // đài Huế chưa có kết quả ngày này (chỉ Đồng Nai có)
    await tester.tap(find.byKey(const ValueKey('station-card-mt-hue')));
    await tester.pump();
    await tester.tap(find.text('Xác nhận chọn đài'));
    await tester.pumpAndSettle();
    expect(data.asked.single, '2026-10-15|mt-hue'); // lấy kết quả ĐÚNG đài
    expect(find.text('Kết quả tính toán'), findsOneWidget);
    expect(find.textContaining('Chưa có kết quả đài Thừa Thiên Huế'), findsOneWidget); // không tự đặt số
    expect(find.text('Thử lại'), findsOneWidget);
    expect(find.text('Tổng tiền khách trúng'), findsOneWidget);
    expect(find.text('Chưa đủ dữ liệu'), findsNWidgets(2)); // tiền trúng và lợi nhuận
    expect(find.textContaining('1 dòng cần kiểm tra chưa được tính: 99'), findsOneWidget);

    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Đã lưu báo cáo.'), findsOneWidget);
    expect(meta.data.keys.where((k) => k.startsWith('report:')).length, 1);
    expect(jsonDecode(meta.data['reports:index']!), hasLength(1));

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(find.text('Đã sao chép báo cáo'), findsOneWidget);
    expect(clip, startsWith('BÁO CÁO KẾT QUẢ\nĐài: Thừa Thiên Huế\nNgày: 15/10/2026'));

    await tester.tap(find.text('Gửi cho khách hàng'));
    await tester.pumpAndSettle();
    expect(find.text('Gửi cho Khách A'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Gửi'));
    await tester.pumpAndSettle();
    expect(sender.sent.single.$1, 'f1');
    expect(sender.sent.single.$2, clip); // gửi đúng nội dung báo cáo đã copy
    expect(find.text('Đã gửi báo cáo.'), findsOneWidget);

    // quay lại: về chọn đài, rồi mở báo cáo đã lưu
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Chọn đài tính toán'), findsOneWidget);
    await tester.tap(find.text('Báo cáo đã lưu (1)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đài Thừa Thiên Huế'), findsOneWidget);
    await tester.tap(find.textContaining('Đài Thừa Thiên Huế'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Báo cáo đã lưu lúc'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Tính toán có kết quả của đúng đài và ngày: hiện tiền trúng và lợi nhuận', (tester) async {
    final data = _Data(results: {'2026-10-15|mn-dongnai': _result});
    await _pumpScreen(tester, _svc(data, MemoryChatMeta(), null), messages: const [DecodeSource('m1', '20lo10')], date: '2026-10-15');
    await tester.tap(find.byType(AppDropdown<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bình').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tính toán'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('station-card-mn-dongnai')));
    await tester.pump();
    await tester.tap(find.text('Xác nhận chọn đài'));
    await tester.pumpAndSettle();
    expect(data.asked.single, '2026-10-15|mn-dongnai');
    expect(find.text('Trúng 50 điểm'), findsOneWidget);
    expect(find.text('3.500.000đ'), findsNWidgets(2)); // dòng trúng của nhóm và tổng tiền khách trúng
    expect(find.text('Tổng tiền khách đánh'), findsOneWidget);
    expect(find.text('126.000đ'), findsWidgets);
    expect(find.text('-3.374.000đ'), findsOneWidget); // tổng lợi nhuận
    expect(find.textContaining('Chưa có kết quả'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  group('Nhập số từ chat', () {
    Future<(EntriesController, List<String>)> setup() async {
      SharedPreferences.setMockInitialValues({});
      final saved = <String>[];
      final auth = AuthStore()..token = 't';
      final api = ApiClient(auth, client: MockClient((r) async {
        http.Response j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});
        switch ('${r.method} ${r.url.path}') {
          case 'GET /api/me/customers':
            return j({'customers': [{'id': 'c1', 'name': 'An', 'phone': '', 'scoringRates': null, 'defaultStation': null}]});
          case 'GET /api/me/scoring-settings':
            return j({'rates': {'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2}, 'lo': {'rate': 20, 'tiers': ['dacBiet'], 'digits': 2}}});
          case 'GET /api/me/entries':
            return j({'entries': [], 'total': 0, 'hasMore': false});
          case 'GET /api/me/syntax-templates':
            return j({'templates': []});
          case 'GET /api/me':
            return j({'package': {'isActive': true}, 'stats': {}});
          case 'POST /api/me/entries':
            final b = jsonDecode(r.body) as Map<String, dynamic>;
            saved.add('${b['betType']}:${b['value']}:${b['score']}:${b['entryDate']}:${b['station']}');
            return j({...b, 'id': 'n${saved.length}', 'result': null, 'createdAt': 't', 'updatedAt': 't'}, 201);
        }
        return j({'error': 'nope'}, 404);
      }));
      final store = OfflineStore(api: api, prefs: await SharedPreferences.getInstance(), userId: 'u1');
      final c = EntriesController(api: api, auth: auth, stations: testStations(), store: store);
      await c.init();
      return (c, saved);
    }

    testWidgets('nội dung vào ô nhập nhanh và tự Phân tích; lưu hết thì chuyển sang Tính điểm kèm khách, ngày, số lượng', (tester) async {
      final (c, saved) = await setup();
      final went = <(String, String, int)>[];
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<LotteryStations>.value(value: c.stations)],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickEntryBox(controller: c, goToScoring: (_, name, date, n) => went.add((name, date, n)))))),
      ));
      await tester.pump();

      await c.applyChatPrefill(const ChatPrefill(text: '20lo10\n30lo5', customer: 'An', date: '2026-10-15', station: 'mn-dongnai'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, '20lo10\n30lo5');
      expect(find.textContaining('Đã chọn 2/2 dòng'), findsOneWidget); // đã Phân tích, không cần bấm

      await tester.tap(find.textContaining('Xác nhận và lưu'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pumpAndSettle();
      expect(saved, ['lo:20:10:2026-10-15:mn-dongnai', 'lo:30:5:2026-10-15:mn-dongnai']);
      expect(went, [('An', '2026-10-15', 2)]);
      expect(c.fromChat, isFalse); // chỉ chuyển một lần
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets('nhập tay bình thường (không từ chat) thì không chuyển trang', (tester) async {
      final (c, _) = await setup();
      c.selectCustomer('An');
      final went = <int>[];
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<LotteryStations>.value(value: c.stations)],
        child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: QuickEntryBox(controller: c, goToScoring: (_, _, _, n) => went.add(n))))),
      ));
      await tester.enterText(find.byType(TextField).first, 'lo 12 34 x 5');
      await tester.pump();
      await tester.tap(find.text('Phân tích'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Xác nhận và lưu'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
      await tester.pumpAndSettle();
      expect(went, isEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  });

  testWidgets('"Dùng cho Nhập số": đưa nội dung đã đối chiếu, khách, ngày, đài sang Nhập số và đóng các màn chat', (tester) async {
    ChatPrefillHub.instance.take();
    tester.view.physicalSize = const Size(360 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final svc = _svc(_Data(), MemoryChatMeta(), null);
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (c, _) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(c).push(MaterialPageRoute(builder: (_) => ChatDecodeScreen(services: svc, friendId: 'f1', friendName: 'A', initialDate: '2026-10-15', messages: const [DecodeSource('m1', '20lo10\n30lo5')]))),
            child: const Text('mở'),
          ),
        ),
      ),
      GoRoute(path: '/calc', builder: (_, _) => const Scaffold(body: Text('NHAP SO'))),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    // chưa chọn khách: không đi
    await tester.tap(find.text('Dùng cho Nhập số'));
    await tester.pumpAndSettle();
    expect(find.text('Hãy chọn khách hàng cho số liệu đã nhập trước khi tiếp tục.'), findsOneWidget);
    expect(ChatPrefillHub.instance.hasPending, isFalse);

    await tester.tap(find.byType(AppDropdown<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bình').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dùng cho Nhập số'));
    await tester.pumpAndSettle();
    expect(find.text('NHAP SO'), findsOneWidget);
    expect(find.byType(ChatDecodeScreen), findsNothing);
    expect(router.routeInformationProvider.value.uri.queryParameters['tab'], 'entries');
    final p = ChatPrefillHub.instance.take()!;
    expect((p.text, p.customer, p.date, p.station), ('20lô10\n30lô5', 'Bình', '2026-10-15', 'mb'));
  });

  testWidgets('mở Tính điểm bằng đường dẫn có khách + ngày + số lượng: chọn sẵn khách, ngày, hiện thông báo', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final auth = AuthStore()..token = 't';
    http.Response j(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});
    final api = ApiClient(auth, client: MockClient((r) async {
      switch (r.url.path) {
        case '/api/me/entries':
          return j({'entries': [{'id': 'e1', 'customerName': 'An', 'entryDate': '2026-10-15', 'value': '20', 'score': '10', 'result': null, 'betType': 'lo', 'station': 'mb', 'note': null, 'createdAt': 't', 'updatedAt': 't'}], 'hasMore': false});
        case '/api/me/customers':
          return j({'customers': [{'id': 'c1', 'name': 'An', 'phone': '', 'scoringRates': null, 'defaultStation': null}]});
        case '/api/me/scoring-settings':
          return j({'rates': {'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2}, 'lo': {'rate': 20, 'tiers': ['dacBiet'], 'digits': 2}}});
        case '/api/lottery-results':
          return j({'result': null});
      }
      return http.Response('{}', 404);
    }));
    final router = GoRouter(
      initialLocation: calcLocation('scoring', customer: 'An', date: '2026-10-15', added: 3),
      routes: [GoRoute(path: '/calc', builder: (_, _) => const Scaffold(body: ScoringScreen()))],
    );
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<LotteryStations>.value(value: testStations()),
        ChangeNotifierProvider<MaskStore>(create: (_) => MaskStore()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã thêm 3 số liệu cho An ngày 15/10/2026'), findsOneWidget);
    expect(find.text('15/10/2026'), findsWidgets); // khoảng ngày đã đặt đúng ngày vừa nhập
    await tester.pumpWidget(const SizedBox());
  });
}
