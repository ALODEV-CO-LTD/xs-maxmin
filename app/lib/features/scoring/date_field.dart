import 'package:flutter/material.dart';
import '../../core/widgets/svg_icon.dart';

import '../../core/format.dart';

/// A tappable dd/mm/yyyy field that opens the date picker. [value] is ISO (YYYY-MM-DD) or '' (no date).
class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged, this.label, this.clearable = false, this.dense = false});
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;
  final bool clearable;
  final bool dense;

  DateTime? get _date {
    final p = value.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    return y == null || m == null || d == null ? null : DateTime(y, m, d);
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = _date ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: label,
      cancelText: 'Huỷ',
      confirmText: 'Chọn',
    );
    if (picked != null) onChanged(isoOf(picked));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: clearable && value.isNotEmpty
              ? IconButton(tooltip: 'Bỏ ngày', padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 32, height: 32), icon: const SvgIcon(AppSvg.closeCircle, size: 18), onPressed: () => onChanged(''))
              : const SvgIcon(AppSvg.calendar, size: 14),
        ),
        child: Text(value.isEmpty ? 'Chọn ngày' : viDate(value), style: TextStyle(fontSize: 15, color: value.isEmpty ? theme.hintColor : Colors.black)),
      ),
    );
  }
}
