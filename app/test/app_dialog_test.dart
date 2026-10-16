import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/widgets/app_dialog.dart';

Future<void> _open(WidgetTester tester, Widget Function(BuildContext) build, {Size size = const Size(360, 640)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (c) => Scaffold(body: TextButton(onPressed: () => showDialog<String>(context: c, builder: (_) => build(c)), child: const Text('mo')))),
  ));
  await tester.tap(find.text('mo'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('title, X in the corner closes it, footer buttons stay', (tester) async {
    await _open(tester, (_) => const AppDialog(title: 'Thêm khách hàng', body: Text('thân'), actions: [Text('Lưu')]));
    expect(find.text('Thêm khách hàng'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.text('Lưu'), findsOneWidget);
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Thêm khách hàng'), findsNothing);
  });

  testWidgets('back variant shows the arrow instead of the X', (tester) async {
    await _open(tester, (_) => const AppDialog(title: 'Cấu hình', back: true, body: Text('thân')));
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.text('Cấu hình'), findsNothing);
  });

  testWidgets('close is disabled while busy', (tester) async {
    await _open(tester, (_) => const AppDialog(title: 'Đang lưu', closeEnabled: false, body: Text('thân')));
    await tester.tap(find.byTooltip('Đóng'));
    await tester.pumpAndSettle();
    expect(find.text('Đang lưu'), findsOneWidget);
  });

  testWidgets('a tall body scrolls while title and footer stay on screen', (tester) async {
    await _open(
      tester,
      (_) => AppDialog(title: 'Dài', body: Column(children: [for (var i = 0; i < 60; i++) Text('dòng $i')]), actions: const [Text('Xong')]),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Dài'), findsOneWidget);
    expect(find.text('Xong'), findsOneWidget);
    expect(tester.getTopLeft(find.text('dòng 59')).dy, greaterThan(640)); // below the fold, reachable by scrolling
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('dòng 59')).dy, lessThan(640));
    expect(find.text('Xong'), findsOneWidget);
  });
}
