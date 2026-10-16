import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/lottery_stations.dart';
import 'package:mamba_app/core/mask_store.dart';
import 'package:mamba_app/core/theme.dart';
import 'package:mamba_app/features/results/results_controller.dart';
import 'package:mamba_app/features/results/results_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'results_controller_test.dart' show FakeServer, fillColumn, date;
import 'scoring_fixtures.dart';

ApiClient client(FakeServer f) => ApiClient(AuthStore(), client: MockClient(f.handle));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shapeForm keeps groups longer than usual; resultBody drops empty extra boxes only', () {
    final st = testStations().regionOf('mn').structure;
    final bay = st.firstWhere((p) => p.tier == 'giaiBay');
    final f = shapeForm(st, {'giaiBay': ['111', '222', '333']});
    expect(f['giaiBay'], ['111', '222', '333']);
    f['giaiBay']!.add('');
    final tu = st.firstWhere((p) => p.tier == 'giaiTu');
    for (final p in st) {
      for (var k = 0; k < p.count; k++) {
        f[p.tier]![k] = f[p.tier]![k].isEmpty ? '1' * p.digits : f[p.tier]![k];
      }
    }
    expect(requiredFilled(st, f), isTrue);
    final body = resultBody(date, 'mn-cantho', st, f);
    expect(body['giaiBay'], ['111', '222', '333']); // trailing empty extra dropped
    expect((body['giaiTu'] as List).length, tu.count);
    expect(body['dacBiet'], isA<String>());
    // an empty box inside the usual count is not "filled"
    f['giaiBay']![0] = '';
    expect(requiredFilled(st, f), isFalse);
    expect(bay.count, 1);
  });

  test('stations: schedule + added + saved-out-of-schedule; one form at a time; extra boxes are saved', () async {
    final fs = FakeServer();
    // Tp.HCM is not on the schedule but already has a result that day
    fs.saved['mn-tphcm'] = {
      'dacBiet': '123456', 'giaiNhat': '11111', 'giaiNhi': '22222', 'giaiBa': ['33331', '33332'], 'giaiTu': List.filled(7, '44444'),
      'giaiNam': '5555', 'giaiSau': List.filled(3, '6666'), 'giaiBay': ['777', '888'], 'giaiTam': '88',
    };
    fs.saved['mn-tphcm'] = {
      ...fs.saved['mn-tphcm']!,
      'giaiNhi': ['22222'], 'giaiNam': ['5555'], 'giaiTam': ['88'],
    };
    final c = ResultsController(client(fs), testStations(), initialDate: date);
    await c.init();
    await c.setRegion('mn');
    expect(c.scheduledStations, ['mn-dongnai', 'mn-cantho', 'mn-soctrang']);
    expect(c.extraStations, ['mn-tphcm']);
    expect(c.boardStations, ['mn-dongnai', 'mn-cantho', 'mn-soctrang', 'mn-tphcm']);
    expect(c.otherStations, isEmpty);
    expect(c.board['mn-tphcm']!['giaiBay'], ['777', '888']); // longer than usual
    expect(c.boardLocked('mn-tphcm'), isTrue);
    expect(c.curStation, 'mn-dongnai');
    c.selectStation('mn-tphcm');
    expect(c.curStation, 'mn-tphcm');
    expect(c.gridOpen, isTrue); // something in it
  });

  test('+ Đài khác adds a station; + and − add/remove boxes (never below usual, never above the API limit)', () async {
    final fs = FakeServer();
    final c = ResultsController(client(fs), testStations(), initialDate: date);
    await c.init();
    await c.setRegion('mn');
    expect(c.otherStations.map((o) => o.value), ['mn-tphcm']);
    expect(c.gridOpen, isFalse);
    c.addStation('mn-tphcm');
    expect(c.curStation, 'mn-tphcm');
    expect(c.otherStations, isEmpty);
    expect(c.boardStations.last, 'mn-tphcm');

    fillColumn(c, 'mn-tphcm', tam: '47');
    final bay = c.structure.firstWhere((p) => p.tier == 'giaiBay');
    final tu = c.structure.firstWhere((p) => p.tier == 'giaiTu');
    c.removeCell('mn-tphcm', bay); // nothing extra: no-op
    expect(c.board['mn-tphcm']!['giaiBay']!.length, 1);
    c.addCell('mn-tphcm', bay);
    c.addCell('mn-tphcm', bay);
    c.setCell('mn-tphcm', bay, 1, '999');
    expect(c.board['mn-tphcm']!['giaiBay'], ['111', '999', '']);
    c.removeCell('mn-tphcm', bay);
    c.addCell('mn-tphcm', bay);
    for (var i = 0; i < 30; i++) {
      c.addCell('mn-tphcm', tu);
    }
    expect(c.board['mn-tphcm']!['giaiTu']!.length, tu.count + maxExtraCells);
    c.addCell('mn-tphcm', c.structure.first); // a single box (đặc biệt) never grows
    expect(c.board['mn-tphcm']!['dacBiet']!.length, 1);
    while (c.board['mn-tphcm']!['giaiTu']!.length > tu.count) {
      c.removeCell('mn-tphcm', tu);
    }
    expect(c.board['mn-tphcm']!['giaiTu']!.length, tu.count);

    await c.save();
    expect(c.error, isNull);
    expect(fs.posts.single['station'], 'mn-tphcm');
    expect(fs.posts.single['giaiBay'], ['111', '999']); // the empty extra box was dropped
    expect(c.boardSaved, {'mn-tphcm'});
  });

  test('a day with an extra box in a Miền Bắc group saves it', () async {
    final fs = FakeServer();
    final c = ResultsController(client(fs), testStations(), initialDate: date);
    await c.init();
    for (final p in c.structure) {
      for (var k = 0; k < p.count; k++) {
        c.setCell(null, p, k, '7' * p.digits);
      }
    }
    final bay = c.structure.firstWhere((p) => p.tier == 'giaiBay');
    c.addCell(null, bay);
    c.setCell(null, bay, 4, '55');
    await c.save();
    expect(fs.posts.single['giaiBay'], ['77', '77', '77', '77', '55']);
  });

  testWidgets('chips pick the station; + Đài khác adds one; + and − change the boxes', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final fs = FakeServer();
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: ApiClient(AuthStore(), client: MockClient(fs.handle))),
        ChangeNotifierProvider<LotteryStations>.value(value: testStations()),
        ChangeNotifierProvider<MaskStore>(create: (_) => MaskStore()),
      ],
      child: MaterialApp(theme: darkTheme, home: const Scaffold(body: ResultsScreen())),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miền Nam'));
    await tester.pumpAndSettle();
    expect(find.text('Đồng Nai'), findsOneWidget);
    expect(find.text('+ Đài khác (1)'), findsOneWidget);
    expect(find.textContaining('Giải bảy', findRichText: true), findsNothing); // the grid is folded

    await tester.tap(find.text('Cần Thơ'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Nhập tay các giải · Cần Thơ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Giải bảy', findRichText: true), findsOneWidget);
    expect(find.byType(DigitCell), findsNWidgets(18));

    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Thêm ô Giải bảy'));
    await tester.pumpAndSettle();
    expect(find.byType(DigitCell), findsNWidgets(19));
    expect(find.byTooltip('Bớt ô Giải bảy'), findsOneWidget);
    await tester.tap(find.byTooltip('Bớt ô Giải bảy'));
    await tester.pumpAndSettle();
    expect(find.byType(DigitCell), findsNWidgets(18));
    expect(find.byTooltip('Bớt ô Giải bảy'), findsNothing);

    await tester.drag(find.byType(ListView).first, const Offset(0, 1500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('+ Đài khác (1)'), warnIfMissed: false); // the chip itself ignores pointers; the menu button around it takes the tap
    await tester.pumpAndSettle();
    await tester.tap(find.text('TP. Hồ Chí Minh').last);
    await tester.pumpAndSettle();
    expect(find.text('TP. Hồ Chí Minh'), findsWidgets);
    expect(find.text('+ Đài khác (1)'), findsNothing);
    expect(find.textContaining('Nhập tay các giải · TP. Hồ Chí Minh'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
