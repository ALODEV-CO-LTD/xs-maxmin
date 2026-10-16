import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/lottery_stations.dart';
import 'package:mamba_app/features/entries/entries_controller.dart';
import 'package:mamba_app/features/entries/entry_form.dart';
import 'package:mamba_app/features/entries/offline_store.dart';
import 'package:mamba_app/features/entries/quick_entry_box.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response _j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});

class _Net {
  bool offline = false;
  final posted = <Map<String, dynamic>>[];
  late final client = MockClient((r) async {
    if (offline && r.method == 'POST') throw http.ClientException('no network');
    switch ('${r.method} ${r.url.path}') {
      case 'GET /api/me/entries':
        return _j({'entries': [], 'total': 0, 'hasMore': false});
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
            'lo': {'rate': 20, 'tiers': ['dacBiet'], 'digits': 2},
          },
        });
      case 'GET /api/me/syntax-templates':
        return _j({'templates': []});
      case 'GET /api/me':
        return _j({'package': {'isActive': true}, 'stats': {}});
      case 'POST /api/me/entries':
        final b = jsonDecode(r.body) as Map<String, dynamic>;
        posted.add(b);
        return _j({...b, 'id': 'n${posted.length}', 'result': null, 'createdAt': 't', 'updatedAt': 't'}, 201);
    }
    return _j({'error': 'nope'}, 404);
  });
}

Future<(EntriesController, _Net)> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final net = _Net();
  final auth = AuthStore()..token = 't';
  final api = ApiClient(auth, client: net.client);
  final store = OfflineStore(api: api, prefs: await SharedPreferences.getInstance(), userId: 'u1');
  final c = EntriesController(api: api, auth: auth, stations: LotteryStations(), store: store);
  await c.init();
  c.selectCustomer('An');
  return (c, net);
}

Future<void> _pump(WidgetTester tester, EntriesController c, {Widget? child}) async {
  tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [ChangeNotifierProvider<LotteryStations>.value(value: c.stations)],
    child: MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child ?? ListenableBuilder(listenable: c, builder: (_, _) => EntryFormCard(controller: c))))),
  ));
  await tester.pump();
}

Future<void> _done(WidgetTester tester, EntriesController c) async {
  await tester.pumpWidget(const SizedBox());
  c.dispose();
}

void main() {
  testWidgets('a picture is read into the ONE box, analysed at once, and can be viewed and removed', (tester) async {
    final (c, _) = await _controller();
    await _pump(
      tester,
      c,
      child: QuickEntryBox(controller: c, pickPath: (_) async => '/nonexistent/ảnh.jpg', recognize: (_) async => 'de 12 34 x 10\nlo 45 x 3'),
    );
    await tester.enterText(find.byType(TextField).first, 'de 99 x 1');
    await tester.tap(find.text('Chọn ảnh'));
    await tester.pumpAndSettle();
    final box = tester.widget<TextField>(find.byType(TextField).first).controller!.text;
    expect(box, 'de 99 x 1\nde 12 34 x 10\nlo 45 x 3'); // the text joined what was already typed
    expect(find.textContaining('Đã chọn'), findsOneWidget); // analysed without pressing Phân tích
    expect(find.text('Văn bản đọc từ ảnh đã đưa vào ô trên.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('photo-thumb')));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget); // full size view
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Xoá ảnh'));
    await tester.pump();
    expect(find.byKey(const ValueKey('photo-thumb')), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).first).controller!.text, box); // the text stays
    await _done(tester, c);
  });

  testWidgets('a picture of plain numbers gives a preview of lines to check (no score, so none ticked)', (tester) async {
    final (c, _) = await _controller();
    await _pump(tester, c, child: QuickEntryBox(controller: c, pickPath: (_) async => '/x.jpg', recognize: (_) async => '12 34 56'));
    await tester.tap(find.text('Chọn ảnh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã chọn 0/3 dòng'), findsOneWidget);
    await _done(tester, c);
  });

  testWidgets('a picture with no text shows a message and keeps the box', (tester) async {
    final (c, _) = await _controller();
    await _pump(tester, c, child: QuickEntryBox(controller: c, pickPath: (_) async => '/x.jpg', recognize: (_) async => '  '));
    await tester.tap(find.text('Chọn ảnh'));
    await tester.pumpAndSettle();
    expect(find.text('Không đọc được chữ nào từ ảnh. Hãy chụp rõ hơn hoặc nhập tay.'), findsOneWidget);
    await _done(tester, c);
  });

  testWidgets('adding by hand shows the green "Đã thêm N số liệu" above the button and it goes away after 7 seconds', (tester) async {
    final (c, net) = await _controller();
    await _pump(tester, c);
    c.rows.first
      ..value.text = '12'
      ..score.text = '5';
    c.touchRows();
    await c.submit();
    await tester.pump();
    expect(net.posted.length, 1);
    expect(find.text('Đã thêm 1 số liệu cho An.'), findsOneWidget);
    final msgY = tester.getTopLeft(find.text('Đã thêm 1 số liệu cho An.')).dy;
    final btnY = tester.getTopLeft(find.widgetWithText(FilledButton, 'Thêm số liệu')).dy;
    expect(msgY, lessThan(btnY));
    await tester.pump(EntriesController.addedMessageDuration + const Duration(milliseconds: 100));
    expect(find.textContaining('Đã thêm 1 số liệu'), findsNothing);
    await _done(tester, c);
  });

  test('saving previewed rows and saving offline both confirm', () async {
    final (c, net) = await _controller();
    final drafts = [RowDraft(type: 'de', value: '12', score: '3'), RowDraft(type: 'lo', value: '45', score: '2')];
    await c.saveDrafts(drafts, onSaved: (_) {});
    expect(c.addedMessage, 'Đã thêm 2 số liệu cho An.');
    c.clearAdded();
    expect(c.addedMessage, isEmpty);
    net.offline = true;
    await c.saveDrafts([RowDraft(type: 'de', value: '77', score: '1')], onSaved: (_) {});
    expect(c.addedMessage, 'Đã thêm 1 số liệu cho An (đang offline, sẽ tự đồng bộ).');
    c.clearAdded();
    c.dispose();
  });
}
