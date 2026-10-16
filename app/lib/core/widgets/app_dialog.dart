import 'package:flutter/material.dart';

/// Shared shell of the input dialogs (web: components/ModalDialog.vue): a fixed title row with the ✕ close button in
/// the right corner (or a ← back button on the left for [back], used by the big forms), an optional description, a body
/// that scrolls, and a fixed footer for the buttons. [onClose] defaults to closing the dialog with no result (the same
/// as the old "Huỷ"); pass [closeEnabled] false while a request is running.
/// Yes/no confirmations stay plain AlertDialogs.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    this.description,
    this.actions = const [],
    this.back = false,
    this.wide = false,
    this.closeEnabled = true,
    this.onClose,
  });
  final String title;
  final String? description;
  final Widget body;
  final List<Widget> actions;
  final bool back;
  final bool wide;
  final bool closeEnabled;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    void close() => onClose != null ? onClose!() : Navigator.of(context).maybePop();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 720 : 440),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(back ? 4 : 20, 8, 8, 0),
            child: Row(children: [
              if (back) IconButton(tooltip: 'Quay lại', icon: const Icon(Icons.arrow_back), onPressed: closeEnabled ? close : null),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))),
              if (!back) IconButton(tooltip: 'Đóng', icon: const Icon(Icons.close), onPressed: closeEnabled ? close : null),
            ]),
          ),
          if (description != null) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 4), child: Text(description!, style: TextStyle(color: cs.onSurface.withValues(alpha: 0.62), fontSize: 13.5))),
          Flexible(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: body,
            ),
          ),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
            ),
        ]),
      ),
    );
  }
}
