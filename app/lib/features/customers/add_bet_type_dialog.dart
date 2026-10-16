import 'package:flutter/material.dart';

import '../../core/scoring_config.dart';
import '../../core/theme.dart';

/// What the user typed in "Kiểu đánh khác".
class NewBetType {
  NewBetType({this.restore, required this.name, required this.symbol, required this.allTiers, required this.digits, required this.price, required this.payout});
  /// Not null = put back this removed standard kind (the other fields are unused).
  final String? restore;
  final String name;
  final String symbol;

  /// false = compared with the special prize only; true = with every prize.
  final bool allTiers;
  final int digits;
  final String price;
  final String payout;
}

/// "+ Thêm cách đánh" of a group: put back a removed standard cách đánh ([restorable]) or make a new one (tên, ký hiệu = the
/// key, so với giải đặc biệt / tất cả các giải, số cuối, giá tiền, giá trúng).
/// [onSubmit] adds it and returns an error text ('' = added); the dialog stays open and shows the error otherwise.
Future<void> showAddBetTypeDialog(
  BuildContext context, {
  required String groupLabel,
  required String regionName,
  List<TableKind> restorable = const [],
  required String Function(NewBetType) onSubmit,
}) {
  return showDialog<void>(context: context, builder: (_) => _AddBetTypeDialog(groupLabel: groupLabel, regionName: regionName, restorable: restorable, onSubmit: onSubmit));
}

class _AddBetTypeDialog extends StatefulWidget {
  const _AddBetTypeDialog({required this.groupLabel, required this.regionName, required this.restorable, required this.onSubmit});
  final String groupLabel;
  final String regionName;
  final List<TableKind> restorable;
  final String Function(NewBetType) onSubmit;
  @override
  State<_AddBetTypeDialog> createState() => _AddBetTypeDialogState();
}

class _AddBetTypeDialogState extends State<_AddBetTypeDialog> {
  final _name = TextEditingController();
  final _symbol = TextEditingController();
  final _price = TextEditingController(text: '12600');
  final _payout = TextEditingController(text: '70000');
  bool _allTiers = false;
  int _digits = 2;
  String _error = '';
  late String _pick = widget.restorable.isNotEmpty ? widget.restorable.first.kind : 'new';

  @override
  void dispose() {
    _name.dispose();
    _symbol.dispose();
    _price.dispose();
    _payout.dispose();
    super.dispose();
  }

  void _submit() {
    final err = widget.onSubmit(NewBetType(restore: _pick == 'new' ? null : _pick, name: _name.text, symbol: _symbol.text, allTiers: _allTiers, digits: _digits, price: _price.text, payout: _payout.text));
    if (err.isEmpty) {
      Navigator.pop(context);
    } else {
      setState(() => _error = err);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Thêm vào "${widget.groupLabel}" (${widget.regionName})'),
      scrollable: true,
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.restorable.isNotEmpty) ...[
          DropdownButtonFormField<String>(
            initialValue: _pick,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Chọn'),
            items: [
              for (final k in widget.restorable) DropdownMenuItem(value: k.kind, child: Text('Khôi phục: ${k.label}', overflow: TextOverflow.ellipsis)),
              const DropdownMenuItem(value: 'new', child: Text('Cách đánh mới (tự đặt tên, ký hiệu)', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _pick = v ?? 'new'),
          ),
          const SizedBox(height: 10),
        ],
        if (_pick == 'new') ..._newFields(),
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error, style: TextStyle(color: context.badColor, fontSize: 12.5))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
        FilledButton(onPressed: _submit, child: Text(_pick == 'new' ? 'Thêm' : 'Khôi phục')),
      ],
    );
  }

  List<Widget> _newFields() {
    const num = TextInputType.numberWithOptions(decimal: true);
    return [
        TextField(controller: _name, maxLength: 30, decoration: const InputDecoration(labelText: 'Tên', hintText: 'Ví dụ: Tài xỉu', counterText: '')),
        const SizedBox(height: 10),
        TextField(controller: _symbol, maxLength: 12, decoration: const InputDecoration(labelText: 'Ký hiệu', hintText: 'Ví dụ: tx', counterText: '')),
        const SizedBox(height: 10),
        DropdownButtonFormField<bool>(
          initialValue: _allTiers,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'So với'),
          items: const [DropdownMenuItem(value: false, child: Text('Giải đặc biệt')), DropdownMenuItem(value: true, child: Text('Tất cả các giải'))],
          onChanged: (v) => setState(() => _allTiers = v ?? false),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          initialValue: _digits,
          decoration: const InputDecoration(labelText: 'Số cuối'),
          items: const [DropdownMenuItem(value: 2, child: Text('2 số')), DropdownMenuItem(value: 3, child: Text('3 số')), DropdownMenuItem(value: 4, child: Text('4 số'))],
          onChanged: (v) => setState(() => _digits = v ?? 2),
        ),
        const SizedBox(height: 10),
        TextField(controller: _price, keyboardType: num, decoration: const InputDecoration(labelText: 'Giá tiền / 1 điểm')),
        const SizedBox(height: 10),
        TextField(controller: _payout, keyboardType: num, decoration: const InputDecoration(labelText: 'Giá trúng / 1 điểm')),
        const SizedBox(height: 6),
        Text('Cách đánh này chỉ dùng cho ${widget.regionName}. Bấm Lưu ở màn hình cấu hình để áp dụng.', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
    ];
  }
}
