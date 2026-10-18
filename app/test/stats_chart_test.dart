import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/account/stats_chart.dart';
import 'package:mamba_app/features/account/stats_logic.dart';

void main() {
  testWidgets('tap on a bar shows full period and full value; fits 360dp', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pts = buildSeries(
      const [StatEntry(customerName: 'A', entryDate: '2026-03-02', score: '1234567', result: '0')],
      StatUnit.day,
      StatMetric.vao,
      DateTime(2026, 3, 2),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: StatsBarChart(points: pts, metric: StatMetric.vao, primary: Colors.green, positive: Colors.green, negative: Colors.red))),
    ));
    expect(find.text('02/03/2026'), findsNothing);
    final box = tester.getRect(find.byType(StatsBarChart));
    await tester.tapAt(Offset(box.right - 8, box.center.dy));
    await tester.pump();
    expect(find.text('02/03/2026'), findsOneWidget);
    expect(find.text('1.234.567'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tapAt(Offset(box.right - 8, box.center.dy));
    await tester.pump();
    expect(find.text('02/03/2026'), findsNothing);
  });
}
