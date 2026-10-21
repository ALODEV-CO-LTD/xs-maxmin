import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/app_button.dart';

/// Yes/no confirmation. Resolves true only when the user presses the confirm button.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Đồng ý',
  bool danger = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(ctx, false)),
        AppButton(label: confirmText, variant: danger ? AppButtonVariant.danger : AppButtonVariant.primary, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return res == true;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// A red/green coloured inline message box.
class InfoBox extends StatelessWidget {
  const InfoBox(this.text, {super.key, this.kind = InfoKind.error, this.onClose, this.action});
  final String text;
  final InfoKind kind;
  final VoidCallback? onClose;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      InfoKind.error => context.badColor,
      InfoKind.success => context.okColor,
      InfoKind.warning => Brand.warning,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), border: Border.all(color: color.withValues(alpha: 0.6)), borderRadius: BorderRadius.circular(10)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Padding(padding: const EdgeInsets.only(top: 2, right: 8), child: Text(text))),
        ?action,
        if (onClose != null) IconButton(visualDensity: VisualDensity.compact, tooltip: 'Đóng', icon: const Icon(Icons.close, size: 18), onPressed: onClose),
      ]),
    );
  }
}

enum InfoKind { error, success, warning }

/// Scrolls its child into view once it appears, so a notice next to the save button is never left off screen.
class ScrollIntoView extends StatefulWidget {
  const ScrollIntoView({super.key, required this.child});
  final Widget child;
  @override
  State<ScrollIntoView> createState() => _ScrollIntoViewState();
}

class _ScrollIntoViewState extends State<ScrollIntoView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Scrollable.ensureVisible(context, duration: const Duration(milliseconds: 250), alignment: 0.5, curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
