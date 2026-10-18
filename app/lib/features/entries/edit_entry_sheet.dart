import 'package:flutter/material.dart';

import '../../core/bet_types.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/masked_text.dart';
import 'dialogs.dart';
import 'entries_controller.dart';
import 'entry_model.dart';
import '../../core/widgets/app_button.dart';
import '../../core/keyboard.dart';

/// "Chỉnh sửa số liệu": customer / hạng mục / ngày are read-only info; số, điểm vào and ghi chú can change.
Future<void> showEditEntry(BuildContext context, EntriesController c, Entry entry) {
  return showDialog<void>(context: context, builder: (_) => _EditEntry(controller: c, entry: entry));
}

class _EditEntry extends StatefulWidget {
  const _EditEntry({required this.controller, required this.entry});
  final EntriesController controller;
  final Entry entry;
  @override
  State<_EditEntry> createState() => _EditEntryState();
}

class _EditEntryState extends State<_EditEntry> {
  late final _value = TextEditingController(text: widget.entry.value);
  late final _score = TextEditingController(text: widget.entry.score ?? '');
  late final _note = TextEditingController(text: widget.entry.note ?? '');
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _value.dispose();
    _score.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final err = await widget.controller.saveEdit(widget.entry, value: _value.text, score: _score.text, note: _note.text);
    if (!mounted) return;
    if (err.isEmpty) {
      Navigator.pop(context);
    } else {
      setState(() {
        _busy = false;
        _error = err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    return AppDialog(
      title: 'Chỉnh sửa số liệu',
      closeEnabled: !_busy,
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(e.customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
          Chip(label: Text(betTypeLabel(e.type)), visualDensity: VisualDensity.compact),
          Chip(label: Text(viDate(e.entryDate)), visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 8),
        if (_error.isNotEmpty) InfoBox(_error),
        TextField(controller: _value, autofocus: true, enabled: !_busy, decoration: const InputDecoration(labelText: 'Số liệu')),
        const SizedBox(height: 12),
        TextField(controller: _score, enabled: !_busy, keyboardType: kNumbersKeyboard, inputFormatters: kNumberCharsOnly, decoration: const InputDecoration(labelText: 'Điểm vào')),
        if ((e.result ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(children: [
              Text('Điểm ra: ', style: TextStyle(color: context.mutedColor)),
              MaskedText(e.result!),
              Text(' (sửa ở trang Nhập kết quả)', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
            ]),
          ),
        const SizedBox(height: 12),
        TextField(controller: _note, enabled: !_busy, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Ghi chú')),
      ]),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: _busy ? null : () => Navigator.pop(context)),
        AppButton(label: 'Lưu thay đổi', variant: AppButtonVariant.primary, loading: _busy, onPressed: _busy ? null : _save),
      ],
    );
  }
}
