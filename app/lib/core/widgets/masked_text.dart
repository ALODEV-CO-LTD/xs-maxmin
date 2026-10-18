import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mask_store.dart';

/// A figure that shows "••••" while [MaskStore.masked] (the real text is never built then).
class MaskedText extends StatelessWidget {
  const MaskedText(this.text, {super.key, this.style, this.textAlign});
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  @override
  Widget build(BuildContext context) {
    final masked = context.select<MaskStore, bool>((m) => m.masked);
    return Text(masked ? '••••' : text, style: style, textAlign: textAlign);
  }
}
