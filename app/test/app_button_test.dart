import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/theme.dart';
import 'package:mamba_app/core/widgets/action_bar.dart';
import 'package:mamba_app/core/widgets/app_button.dart';

Widget _wrap(Widget child, {double width = 800}) => MaterialApp(
      theme: lightTheme,
      home: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
    );

void main() {
  testWidgets('AppButton: variants render and fire onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(Column(children: [
      AppButton(label: 'Lưu', variant: AppButtonVariant.primary, onPressed: () => taps++),
      AppButton(label: 'Xoá', variant: AppButtonVariant.danger, onPressed: () => taps++),
      AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => taps++),
      AppButton(label: 'Sửa', onPressed: () => taps++),
    ])));
    for (final t in ['Lưu', 'Xoá', 'Huỷ', 'Sửa']) {
      await tester.tap(find.text(t));
    }
    expect(taps, 4);
  });

  testWidgets('AppButton: loading disables the button and shows a spinner', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(AppButton(label: 'Lưu', variant: AppButtonVariant.primary, loading: true, onPressed: () => taps++)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Lưu'), findsNothing);
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);
  });

  testWidgets('AppButton.icon: tooltip + semantics label, 44dp target', (tester) async {
    await tester.pumpWidget(_wrap(AppButton.icon(label: 'Đóng', icon: Icons.close, onPressed: () {})));
    expect(find.byTooltip('Đóng'), findsOneWidget);
    expect(tester.getSize(find.byType(TextButton)).height, greaterThanOrEqualTo(44));
  });

  testWidgets('ActionBar (wide): start left, children right with the primary last', (tester) async {
    await tester.pumpWidget(_wrap(ActionBar(
      start: [AppButton(label: 'Đặt lại', onPressed: () {})],
      note: '3 mục riêng',
      children: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () {}),
        AppButton(label: 'Lưu', variant: AppButtonVariant.primary, onPressed: () {}),
      ],
    )));
    final reset = tester.getTopLeft(find.text('Đặt lại')).dx;
    final cancel = tester.getTopLeft(find.text('Huỷ')).dx;
    final save = tester.getTopLeft(find.text('Lưu')).dx;
    expect(reset, lessThan(cancel));
    expect(cancel, lessThan(save));
    expect(find.text('3 mục riêng'), findsOneWidget);
  });

  testWidgets('ActionBar (narrow): stacks with the primary action on top', (tester) async {
    await tester.pumpWidget(_wrap(
      ActionBar(children: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () {}),
        AppButton(label: 'Lưu', variant: AppButtonVariant.primary, onPressed: () {}),
      ]),
      width: 360,
    ));
    expect(tester.getTopLeft(find.text('Lưu')).dy, lessThan(tester.getTopLeft(find.text('Huỷ')).dy));
  });
}
