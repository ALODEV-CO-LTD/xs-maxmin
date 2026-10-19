import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bet_types.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/theme.dart';
import 'dialogs.dart';
import 'entries_controller.dart';
import 'quick_entry_box.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_dropdown.dart';
import '../../core/keyboard.dart';

/// "Thêm số liệu mới": đài, ngày, the quick-entry box (message or photo), several rows (hạng mục / số / điểm vào) and a note.
class EntryFormCard extends StatefulWidget {
  const EntryFormCard({super.key, required this.controller});
  final EntriesController controller;
  @override
  State<EntryFormCard> createState() => _EntryFormCardState();
}

class _EntryFormCardState extends State<EntryFormCard> {
  bool _deletingAll = false;
  String _deleteAllError = '';

  EntriesController get c => widget.controller;

  Future<void> _deleteAll() async {
    final list = c.customerEntries.where((e) => !e.pending).toList();
    if (list.isEmpty) return;
    final ok = await confirmDialog(context, title: 'Xoá tất cả số liệu', message: 'Xoá toàn bộ ${list.length} số liệu của khách hàng "${c.selectedName}"? Không thể hoàn tác.', confirmText: 'Xoá tất cả', danger: true);
    if (!ok || !mounted) return;
    setState(() {
      _deletingAll = true;
      _deleteAllError = '';
    });
    final failed = await c.deleteMany(list);
    if (!mounted) return;
    setState(() {
      _deletingAll = false;
      if (failed > 0) _deleteAllError = '$failed số liệu không xoá được, thử lại.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final stations = context.watch<LotteryStations>();
    final options = stations.stationOptions(c.entryDate);
    final stationValue = options.any((o) => o.value == c.station) ? c.station : null;
    final types = c.betTypes;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Thêm số liệu mới', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          if (c.formError.isNotEmpty) InfoBox(c.formError),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              flex: 5,
              child: AppDropdown<String>(
                key: ValueKey('station-${c.entryDate}-${c.selectedName}-${c.station}-${stations.loaded}'),
                initialValue: stationValue,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Đài'),
                items: [for (final o in options) DropdownMenuItem(value: o.value, child: Text(o.label.trim(), overflow: TextOverflow.ellipsis))],
                onChanged: (v) => c.setStation(v ?? 'mb'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              // Always the day the numbers are entered; it cannot be changed.
              child: InputDecorator(decoration: const InputDecoration(labelText: 'Ngày'), child: Text(viDate(todayIso()))),
            ),
          ]),
          const SizedBox(height: 12),
          QuickEntryBox(controller: c),
          const SizedBox(height: 10),
          _rowsHeader(context),
          for (var i = 0; i < c.rows.length; i++) _rowTile(context, i, types),
          const SizedBox(height: 4),
          if (_deleteAllError.isNotEmpty) InfoBox(_deleteAllError),
          if (!c.canAdd) const InfoBox('Gói của bạn đã hết hạn. Vui lòng gia hạn để tiếp tục nhập số liệu.', kind: InfoKind.warning),
          if (c.addedMessage.isNotEmpty) InfoBox(c.addedMessage, kind: InfoKind.success),
          // One row: add a line (+), save (Thêm số liệu), delete all.
          Row(children: [
            AppButton.icon(label: 'Thêm số', variant: AppButtonVariant.secondary, icon: Icons.add, onPressed: c.addRow),
            const SizedBox(width: 8),
            Expanded(child: AppButton(label: 'Thêm số liệu', variant: AppButtonVariant.primary, loading: c.submitting, onPressed: c.submitting || !c.canAdd ? null : c.submit)),
            const SizedBox(width: 8),
            AppButton(label: 'Xoá tất cả', variant: AppButtonVariant.danger, loading: _deletingAll, onPressed: _deletingAll || c.customerEntries.isEmpty ? null : _deleteAll),
          ]),
        ]),
      ),
    );
  }

  Widget _rowsHeader(BuildContext context) {
    return Row(children: [
      Expanded(flex: 3, child: Text('Hạng mục', style: TextStyle(fontSize: 12.5, color: context.mutedColor))),
      Expanded(flex: 2, child: Text('Số', style: TextStyle(fontSize: 12.5, color: context.mutedColor))),
      Expanded(flex: 2, child: Text('Điểm vào', style: TextStyle(fontSize: 12.5, color: context.mutedColor))),
      const SizedBox(width: 40),
    ]);
  }

  // keeps the "Số" field (and its focus) when a row switches between the one-line and the stacked layout while typing
  final Map<Object, GlobalKey> _valueKeys = {};

  Widget _rowTile(BuildContext context, int i, List<String> types) {
    final r = c.rows[i];
    final typeList = types.contains(r.type) ? types : [...types, r.type];
    const pad = EdgeInsets.symmetric(horizontal: 8, vertical: 12);
    // A xiên with 3+ numbers: "Số" gets its own full-width line under the row so every number shows.
    final stacked = valueFieldFlex(r.value.text) > 3;
    final type = AppDropdown<String>(
      initialValue: r.type,
      isExpanded: true,
      decoration: const InputDecoration(isDense: true, contentPadding: pad),
      items: [for (final t in typeList) DropdownMenuItem(value: t, child: Text(betTypeLabel(t), overflow: TextOverflow.ellipsis))],
      onChanged: (v) {
        r.type = v ?? r.type;
        c.touchRows();
      },
    );
    final value = TextField(key: _valueKeys.putIfAbsent(r.uid, () => GlobalKey()), controller: r.value, keyboardType: kNumbersKeyboard, inputFormatters: kNumberCharsOnly, onChanged: (_) => c.touchRows(), decoration: const InputDecoration(isDense: true, hintText: 'Số', contentPadding: pad));
    final score = TextField(controller: r.score, keyboardType: kNumbersKeyboard, inputFormatters: kNumberCharsOnly, decoration: const InputDecoration(isDense: true, hintText: 'Điểm', contentPadding: pad));
    final remove = SizedBox(
      width: 40,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: 'Xoá dòng',
        icon: const Icon(Icons.close, size: 20),
        onPressed: c.rows.length == 1 && r.isBlank ? null : () => c.removeRow(r),
      ),
    );
    return Padding(
      key: ValueKey(r.uid),
      padding: const EdgeInsets.only(bottom: 6),
      child: stacked
          ? Column(children: [
              Row(children: [Expanded(flex: 3, child: type), const SizedBox(width: 6), Expanded(flex: 2, child: score), remove]),
              Padding(padding: const EdgeInsets.fromLTRB(0, 6, 40, 0), child: value),
            ])
          : Row(children: [
              Expanded(flex: 3, child: type),
              const SizedBox(width: 6),
              Expanded(flex: valueFieldFlex(r.value.text), child: value),
              const SizedBox(width: 6),
              Expanded(flex: 2, child: score),
              remove,
            ]),
    );
  }
}
