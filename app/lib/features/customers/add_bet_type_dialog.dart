import 'package:flutter/material.dart';

import '../../core/bet_types.dart';
import '../../core/scoring_config.dart';
import '../../core/theme.dart';
import 'scoring_editor_model.dart';

class NewBetType {
  NewBetType(this.key, this.rate, this.digits, this.tiers, this.unit, this.pointValue);
  final String key;
  final num rate;
  final int digits;
  final List<String> tiers;
  final String unit;
  final num pointValue;
}

/// What is stored as the type's key: lower case, spaces become dashes.
String betTypeKeyOf(String name) => name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-');

/// "Thêm loại đánh": tên, tỉ lệ ăn, so khớp N số cuối, cách tính tiền and the prize groups to compare with.
/// Resolves the new type, or null when cancelled. [existingKeys] are the types already in this region.
Future<NewBetType?> showAddBetTypeDialog(BuildContext context, {required List<String> existingKeys, required String regionName}) {
  return showDialog<NewBetType>(context: context, builder: (_) => _AddBetTypeDialog(existingKeys: existingKeys, regionName: regionName));
}

class _AddBetTypeDialog extends StatefulWidget {
  const _AddBetTypeDialog({required this.existingKeys, required this.regionName});
  final List<String> existingKeys;
  final String regionName;
  @override
  State<_AddBetTypeDialog> createState() => _AddBetTypeDialogState();
}

class _AddBetTypeDialogState extends State<_AddBetTypeDialog> {
  final _name = TextEditingController();
  final _rate = TextEditingController();
  final _pointValue = TextEditingController(text: '$defaultPointValue');
  int _digits = 2;
  String _unit = 'money';
  late final Set<String> _picked = {for (final t in prizeTiers) t.key};
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    _pointValue.dispose();
    super.dispose();
  }

  String get _key => betTypeKeyOf(_name.text);

  String get _nameError {
    if (_key.isEmpty) return 'Nhập tên loại đánh';
    if (_key.contains('@')) return 'Tên không được chứa ký tự @';
    if (widget.existingKeys.contains(_key)) return 'Loại "$_key" đã có trong danh sách';
    return '';
  }

  String get _rateError {
    final n = parseNum(_rate.text);
    return n == null || n <= 0 ? 'Nhập tỉ lệ ăn lớn hơn 0' : '';
  }

  void _submit() {
    setState(() => _submitted = true);
    if (_nameError.isNotEmpty || _rateError.isNotEmpty || _picked.isEmpty) return;
    Navigator.pop(
      context,
      NewBetType(_key, parseNum(_rate.text)!, _digits, [for (final t in prizeTiers) if (_picked.contains(t.key)) t.key], _unit, (parseNum(_pointValue.text) ?? 0).clamp(0, double.infinity)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(fontSize: 12.5, color: context.mutedColor);
    return AlertDialog(
      title: Text('Thêm loại đánh (${widget.regionName})'),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _name,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: '1. Tên loại đánh', hintText: 'Ví dụ: xiên 2, 3 càng, bao lô 4', errorText: _submitted && _nameError.isNotEmpty ? _nameError : null, helperText: _key.isNotEmpty && _nameError.isEmpty ? 'Mã lưu: $_key' : null),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _rate,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: '2. Tỉ lệ ăn', hintText: 'Ví dụ: 70', helperText: 'Điểm ra = điểm vào × tỉ lệ', errorText: _submitted && _rateError.isNotEmpty ? _rateError : null),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          initialValue: _digits,
          decoration: const InputDecoration(labelText: '3. So khớp', helperText: 'Số khách đánh khớp với bấy nhiêu chữ số cuối của giải'),
          items: [for (final d in digitOptions) DropdownMenuItem(value: d, child: Text('$d số cuối'))],
          onChanged: (v) => setState(() => _digits = v ?? 2),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _unit,
          isExpanded: true,
          decoration: const InputDecoration(labelText: '4. Cách tính tiền'),
          items: const [
            DropdownMenuItem(value: 'money', child: Text('Đánh theo tiền (số khách gửi đã là đồng)', overflow: TextOverflow.ellipsis)),
            DropdownMenuItem(value: 'point', child: Text('Đánh theo điểm (quy đổi ra đồng)', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _unit = v ?? 'money'),
        ),
        if (_unit == 'point') ...[
          const SizedBox(height: 8),
          TextField(controller: _pointValue, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: '1 điểm = bao nhiêu đồng')),
        ],
        const SizedBox(height: 14),
        Text('5. Đối chiếu với', style: Theme.of(context).textTheme.labelLarge),
        Wrap(spacing: 4, children: [
          TextButton(onPressed: () => setState(() => _picked..clear()..addAll(prizeTiers.map((t) => t.key))), child: const Text('Tất cả')),
          TextButton(onPressed: () => setState(() => _picked..clear()..add('dacBiet')), child: const Text('Chỉ Đặc biệt')),
          TextButton(onPressed: () => setState(_picked.clear), child: const Text('Bỏ chọn')),
        ]),
        Wrap(spacing: 6, runSpacing: 0, children: [
          for (final t in prizeTiers)
            FilterChip(
              label: Text(t.key == 'giaiTam' ? 'Giải tám' : t.label),
              selected: _picked.contains(t.key),
              onSelected: (v) => setState(() => v ? _picked.add(t.key) : _picked.remove(t.key)),
            ),
        ]),
        if (_submitted && _picked.isEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Chọn ít nhất một giải để đối chiếu', style: TextStyle(color: context.badColor, fontSize: 12.5))),
        const SizedBox(height: 6),
        Text('Loại đánh này chỉ dùng cho ${widget.regionName}. Bấm Lưu ở màn hình cấu hình để áp dụng.', style: muted),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(onPressed: _submit, child: const Text('Thêm loại đánh')),
      ],
    );
  }
}
