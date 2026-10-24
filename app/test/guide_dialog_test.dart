import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/overview/guide_dialog.dart';

void main() {
  testWidgets(
    'the guide opens as a popup with every tab explained and closes with the X',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => showGuideDialog(c),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
      expect(find.text('Hướng dẫn sử dụng'), findsOneWidget);
      expect(find.text('Tổng quan'), findsOneWidget);
      expect(find.textContaining('Lưu kết quả'), findsOneWidget);
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();
      expect(find.text('Hướng dẫn sử dụng'), findsNothing);
    },
  );
}
