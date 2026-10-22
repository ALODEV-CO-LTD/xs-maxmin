import 'package:flutter/material.dart';

import 'svg_icon.dart';

/// The app's single button kit (mirror of frontend/src/components/AppButton.vue): one place decides shape, colour,
/// size, icon and the "busy" state of every action button.
///
/// - [AppButtonVariant.primary]  the main action of a row (at most one per [ActionBar])
/// - [AppButtonVariant.secondary] green outline
/// - [AppButtonVariant.ghost]    Huỷ / Đóng / Quay lại (text only)
/// - [AppButtonVariant.danger]   xoá / hành động không hoàn tác được
/// [loading] shows a spinner and disables the button without changing its width. Compact height 34 dp
/// (28 dp for [AppButtonSize.small], used inside lists and table-like rows).
enum AppButtonVariant { primary, secondary, ghost, danger }

enum AppButtonSize { medium, small }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.secondary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.svg,
    this.loading = false,
    this.block = false,
  }) : _iconOnly = false;

  /// Icon-only button: [label] is read by screen readers and shown as a tooltip.
  const AppButton.icon({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.svg,
    this.variant = AppButtonVariant.ghost,
    this.size = AppButtonSize.medium,
    this.loading = false,
  })  : assert(icon != null || svg != null),
        block = false,
        _iconOnly = true;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;

  /// An icon from the owner's SVG set (wins over [icon]).
  final AppSvg? svg;
  final bool loading;
  final bool block;
  final bool _iconOnly;

  bool get _disabled => loading || onPressed == null;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = size == AppButtonSize.small ? 28.0 : 34.0;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    const pad = EdgeInsets.symmetric(horizontal: 12);
    const text = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    final minSize = Size(_iconOnly ? h : 0, h);
    final spinnerColor = switch (variant) {
      AppButtonVariant.primary => scheme.onPrimary,
      AppButtonVariant.danger => scheme.onError,
      _ => scheme.primary,
    };
    final Widget child = loading
        ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor))
        : _iconOnly
            ? (svg != null ? SvgIcon(svg!, size: 7) : Icon(icon, size: 18))
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (svg != null || icon != null) ...[svg != null ? SvgIcon(svg!, size: 6) : Icon(icon, size: 16), const SizedBox(width: 6)],
                  Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
                ],
              );
    final cb = _disabled ? null : onPressed;
    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(style: FilledButton.styleFrom(minimumSize: minSize, shape: shape, padding: pad, textStyle: text, tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.standard), onPressed: cb, child: child),
      AppButtonVariant.danger => FilledButton(
          style: FilledButton.styleFrom(minimumSize: minSize, shape: shape, padding: pad, textStyle: text, tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.standard, backgroundColor: scheme.error, foregroundColor: scheme.onError),
          onPressed: cb,
          child: child,
        ),
      AppButtonVariant.secondary => OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: minSize, shape: shape, padding: pad, textStyle: text, tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.standard), onPressed: cb, child: child),
      AppButtonVariant.ghost => TextButton(style: TextButton.styleFrom(minimumSize: minSize, shape: shape, padding: pad, textStyle: text, tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.standard), onPressed: cb, child: child),
    };
    final sized = block ? SizedBox(width: double.infinity, child: button) : button;
    return Semantics(
      button: true,
      enabled: !_disabled,
      label: label,
      excludeSemantics: true,
      child: _iconOnly ? Tooltip(message: label, child: sized) : sized,
    );
  }
}
