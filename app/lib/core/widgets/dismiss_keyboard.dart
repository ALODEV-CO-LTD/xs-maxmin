import 'package:flutter/material.dart';

/// Tapping anywhere that is not a text field (empty space, plain text, a card) puts the on-screen keyboard away.
/// Buttons, fields and other tappable widgets keep handling their own taps (they win the gesture), so only a tap that
/// nothing else wanted reaches this.
class DismissKeyboard extends StatelessWidget {
  const DismissKeyboard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      );
}
