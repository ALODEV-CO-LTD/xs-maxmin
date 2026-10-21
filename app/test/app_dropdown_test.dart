import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/theme.dart';
import 'package:mamba_app/core/widgets/app_dropdown.dart';

void main() {
  Future<void> open(WidgetTester t, String initial, List<String> picked) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: lightTheme, // the app theme is compact: rows used to come out 8 narrower than the field
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 300, 100, 0),
          child: AppDropdown<String>(
            key: ValueKey(initial),
            initialValue: initial,
            decoration: const InputDecoration(labelText: 'Trạng thái'),
            items: [for (final s in ['Chờ duyệt', 'Đã duyệt', 'Đã từ chối', 'Đã huỷ', 'Tất cả']) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (v) => picked.add(v!),
          ),
        ),
      ),
    ));
    await t.tap(find.byType(AppDropdown<String>));
    await t.pumpAndSettle();
  }

  // The bug: with the LAST row chosen the Material list went upwards and covered the field.
  for (final initial in ['Chờ duyệt', 'Đã huỷ', 'Tất cả']) {
    testWidgets('menu opens right under the field and is as wide as the field (chosen: $initial)', (t) async {
      await open(t, initial, []);
      final field = t.getRect(find.byType(InputDecorator));
      final first = t.getRect(find.widgetWithText(MenuItemButton, 'Chờ duyệt'));
      final last = t.getRect(find.widgetWithText(MenuItemButton, 'Tất cả'));
      expect(first.top, greaterThanOrEqualTo(field.bottom), reason: 'the list must not cover the field');
      expect(last.top, greaterThan(first.top));
      expect(first.width, closeTo(field.width, 1));
      expect(first.left, closeTo(field.left, 1));
    });
  }

  testWidgets('picking a row reports it and shows it in the field', (t) async {
    final picked = <String>[];
    await open(t, 'Tất cả', picked);
    await t.tap(find.widgetWithText(MenuItemButton, 'Đã duyệt'));
    await t.pumpAndSettle();
    expect(picked, ['Đã duyệt']);
    expect(find.descendant(of: find.byType(InputDecorator), matching: find.text('Đã duyệt')), findsOneWidget);
  });
}
