import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/widgets/dismiss_keyboard.dart';

void main() {
  testWidgets('tapping empty space or plain text puts the keyboard away; a button and the field itself keep working', (tester) async {
    var pressed = 0;
    final node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(MaterialApp(
      home: DismissKeyboard(
        child: Scaffold(
          body: Column(children: [
            TextField(focusNode: node, key: const ValueKey('f')),
            const SizedBox(height: 200),
            const Text('Chữ thường'),
            ElevatedButton(onPressed: () => pressed++, child: const Text('Nút')),
            const Expanded(child: SizedBox.expand()),
          ]),
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('f')));
    await tester.pump();
    expect(node.hasFocus, isTrue);

    await tester.tapAt(const Offset(200, 560)); // empty space under everything
    await tester.pump();
    expect(node.hasFocus, isFalse);

    await tester.tap(find.byKey(const ValueKey('f')));
    await tester.pump();
    expect(node.hasFocus, isTrue);
    await tester.tap(find.text('Chữ thường'));
    await tester.pump();
    expect(node.hasFocus, isFalse);

    await tester.tap(find.byKey(const ValueKey('f')));
    await tester.pump();
    await tester.tap(find.text('Nút'));
    await tester.pump();
    expect(pressed, 1); // the button still works while the keyboard is up
    await tester.tap(find.byKey(const ValueKey('f')));
    await tester.pump();
    expect(node.hasFocus, isTrue); // tapping the field itself does not close it
  });
}
