import 'package:flutter/material.dart';
import 'svg_icon.dart';

/// The one dropdown field of the app. The field looks like any other input (same [InputDecoration]); tapping it opens a
/// rounded white list that is ALWAYS right under the field and exactly as wide as the field, at most 320 high (it scrolls).
///
/// (A Material [DropdownButton] puts the list over the field so that the chosen row sits on it: with the last row chosen
/// the list went upwards and covered the field, with the first row chosen it went downwards. This one does not move.)
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    this.initialValue,
    required this.items,
    required this.onChanged,
    this.decoration,
    this.isExpanded = true,
    this.hint,
  });

  /// The value shown first; like the Material field it is only read once, a new value needs a new [key].
  final T? initialValue;
  final List<DropdownMenuItem<T>> items;

  /// null disables the field.
  final ValueChanged<T?>? onChanged;
  final InputDecoration? decoration;
  final bool isExpanded;
  final Widget? hint;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  late T? _value = widget.initialValue;
  final _menu = MenuController();

  DropdownMenuItem<T>? get _selected {
    for (final i in widget.items) {
      if (i.value == _value) return i;
    }
    return null;
  }

  void _pick(DropdownMenuItem<T> item) {
    setState(() => _value = item.value);
    widget.onChanged?.call(item.value);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.onChanged != null;
    const textStyle = TextStyle(fontSize: 15, fontWeight: FontWeight.w400, color: Colors.black);
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.hasBoundedWidth ? box.maxWidth : 280.0;
        final shown = _selected;
        return MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(0, 4),
          style: MenuStyle(
            backgroundColor: const WidgetStatePropertyAll(Colors.white),
            surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 4)),
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(Size(width, 320)),
          ),
          menuChildren: [
            for (final item in widget.items)
              MenuItemButton(
                onPressed: item.enabled ? () => _pick(item) : null,
                style: ButtonStyle(
                  // The app theme is compact: that would shrink every row by 8 (narrower than the field), so use the standard density.
                  visualDensity: VisualDensity.standard,
                  minimumSize: WidgetStatePropertyAll(Size(width, 48)),
                  maximumSize: WidgetStatePropertyAll(Size(width, double.infinity)),
                  alignment: Alignment.centerLeft,
                  textStyle: const WidgetStatePropertyAll(textStyle),
                  foregroundColor: const WidgetStatePropertyAll(Colors.black),
                  backgroundColor: WidgetStatePropertyAll(item.value == _value ? cs.primary.withValues(alpha: 0.12) : null),
                  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
                ),
                child: SizedBox(width: double.infinity, child: item.child),
              ),
          ],
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? () => (_menu.isOpen ? _menu.close() : _menu.open()) : null,
            child: InputDecorator(
              decoration: (widget.decoration ?? const InputDecoration()).copyWith(enabled: enabled),
              isEmpty: shown == null && widget.hint == null,
              isFocused: _menu.isOpen,
              child: Row(
                children: [
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: textStyle,
                      overflow: TextOverflow.ellipsis,
                      child: shown?.child ?? widget.hint ?? const SizedBox.shrink(),
                    ),
                  ),
                  SvgIcon(AppSvg.chevronDown, size: 14, color: enabled ? Colors.black54 : Colors.black26),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
