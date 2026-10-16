import 'package:flutter/material.dart';

/// The standard row of action buttons of a screen / dialog / form (mirror of frontend/src/components/ActionBar.vue):
///
///     [ start: Xoá, Đặt lại mặc định ]  · note ·  [ Huỷ ]  [ Hành động chính ]
///
/// [start] is the secondary / dangerous side on the left, [children] the right side: Huỷ first, the primary action
/// ALWAYS last (outermost right). On narrow widths (< 520) the buttons stack with the primary one on top and fill the
/// row. [sticky] draws a top border and a surface background so the bar can be pinned at the bottom of a screen
/// (put it in `Scaffold.bottomNavigationBar` or the end of a Column below an Expanded list).
class ActionBar extends StatelessWidget {
  const ActionBar({super.key, this.start = const [], this.note, this.children = const [], this.sticky = false});

  final List<Widget> start;
  final String? note;
  final List<Widget> children;
  final bool sticky;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 520;
      final Widget bar;
      if (narrow) {
        // primary on top: children are given Huỷ → Primary, so the stack shows them reversed.
        final all = [...children.reversed, ...start];
        bar = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (note != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(note!, style: theme.textTheme.bodySmall)),
            for (var i = 0; i < all.length; i++) ...[if (i > 0) const SizedBox(height: 8), all[i]],
          ],
        );
      } else {
        bar = Row(
          children: [
            ...start.expand((w) => [w, const SizedBox(width: 8)]),
            Expanded(child: note == null ? const SizedBox.shrink() : Text(note!, style: theme.textTheme.bodySmall, overflow: TextOverflow.ellipsis)),
            ...children.expand((w) => [const SizedBox(width: 8), w]),
          ],
        );
      }
      final padded = Padding(padding: EdgeInsets.fromLTRB(sticky ? 16 : 0, 10, sticky ? 16 : 0, 10), child: bar);
      if (!sticky) return padded;
      return Material(
        color: theme.colorScheme.surface,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant))),
          child: SafeArea(top: false, child: padded),
        ),
      );
    });
  }
}
