import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/lottery_stations.dart';
import 'package:mamba_app/core/mask_store.dart';
import 'package:mamba_app/core/theme.dart';
import 'package:mamba_app/features/results/results_screen.dart';
import 'package:mamba_app/features/scoring/scoring_screen.dart';
import 'package:provider/provider.dart';

import 'results_controller_test.dart' show FakeServer;
import 'scoring_fixtures.dart';

Widget host(FakeServer f, Widget screen) {
  return MultiProvider(
    providers: [
      Provider<ApiClient>.value(value: ApiClient(AuthStore(), client: MockClient(f.handle))),
      ChangeNotifierProvider<LotteryStations>.value(value: testStations()),
      ChangeNotifierProvider<MaskStore>(create: (_) => MaskStore()),
    ],
    child: MaterialApp(theme: darkTheme, home: Scaffold(body: screen)),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('Nhập kết quả renders on a small phone (Miền Bắc and the Miền Nam table)', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(FakeServer(), const ResultsScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nhập kết quả xổ số rồi bấm'), findsOneWidget); // (the heading is the Kết quả tab of Tính toán)
    expect(find.text('Lưu kết quả', skipOffstage: false), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(find.textContaining('Điểm ra ngày'), findsWidgets);
    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Miền Nam'));
    await tester.pumpAndSettle();
    expect(find.text('Đồng Nai', skipOffstage: false), findsOneWidget);
    expect(find.text('Sóc Trăng', skipOffstage: false), findsOneWidget);
    expect(find.text('Sửa', skipOffstage: false), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tính điểm renders the picker, filters and the summary', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(FakeServer(), const ScoringScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Điểm ra được máy tự động tính'), findsOneWidget); // (the heading is the Tính điểm tab of Tính toán)
    expect(find.text('Chọn khách hàng ở trên để xem điểm ra của họ.', skipOffstage: false), findsOneWidget);
    await tester.tap(find.text('-- Chọn khách hàng --'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('An').last);
    await tester.pumpAndSettle();
    // (with the heading gone the summary and the first day are already on screen)
    expect(find.text('Còn lại = gửi − trúng', skipOffstage: false), findsWidgets);
    await tester.scrollUntilVisible(find.text('Số lô'), 200, scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });
}
