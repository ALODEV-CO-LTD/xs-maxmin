import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/bet_types.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/theme.dart';
import 'dialogs.dart';
import 'entries_controller.dart';
import 'import_sheets.dart';

/// "Thêm số liệu mới": đài, ngày, importers, several rows (hạng mục / số / điểm vào) and a note.
class EntryFormCard extends StatefulWidget {
  const EntryFormCard({super.key, required this.controller});
  final EntriesController controller;
  @override
  State<EntryFormCard> createState() => _EntryFormCardState();
}

class _EntryFormCardState extends State<EntryFormCard> {
  String _bulkType = '';
  final _bulkScore = TextEditingController();
  bool _deletingAll = false;
  String _deleteAllError = '';

  EntriesController get c => widget.controller;

  @override
  void dispose() {
    _bulkScore.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final cur = DateTime.tryParse(c.entryDate) ?? now;
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 2));
    if (d != null) c.setDate(isoOf(d));
  }

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
              child: DropdownButtonFormField<String>(
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
              child: InkWell(
                onTap: _pickDate,
                child: InputDecorator(decoration: const InputDecoration(labelText: 'Ngày', suffixIcon: Icon(Icons.event, size: 20)), child: Text(viDate(c.entryDate))),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => showImportSheet(context, c, ImportMode.photo), icon: const Icon(Icons.photo_camera_outlined, size: 20), label: const Text('Nhập từ ảnh'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => showImportSheet(context, c, ImportMode.paste), icon: const Icon(Icons.content_paste, size: 20), label: const Text('Từ tin nhắn'))),
          ]),
          const SizedBox(height: 14),
          _rowsHeader(context),
          if (c.selectedRowCount > 0) _bulkBar(types),
          for (var i = 0; i < c.rows.length; i++) _rowTile(context, i, types),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: c.addRow, icon: const Icon(Icons.add), label: const Text('Thêm số'))),
          const SizedBox(height: 4),
          TextField(controller: c.note, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Ghi chú', hintText: 'Tuỳ chọn')),
          const SizedBox(height: 12),
          if (_deleteAllError.isNotEmpty) InfoBox(_deleteAllError),
          if (!c.canAdd) const InfoBox('Gói của bạn đã hết hạn. Vui lòng gia hạn để tiếp tục nhập số liệu.', kind: InfoKind.warning),
          FilledButton(onPressed: c.submitting || !c.canAdd ? null : c.submit, child: Text(c.submitting ? 'Đang thêm...' : 'Thêm số liệu')),
          const SizedBox(height: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: context.badColor, side: BorderSide(color: context.badColor.withValues(alpha: 0.7))),
            onPressed: _deletingAll || c.customerEntries.isEmpty ? null : _deleteAll,
            child: Text(_deletingAll ? 'Đang xoá...' : 'Xoá tất cả số liệu của khách này'),
          ),
        ]),
      ),
    );
  }

  Widget _rowsHeader(BuildContext context) {
    return Row(children: [
      Checkbox(value: c.allRowsSelected, onChanged: (_) => c.toggleAllRows(), visualDensity: VisualDensity.compact),
      Expanded(flex: 3, child: Text('Hạng mục', style: TextStyle(fontSize: 12.5, color: context.mutedColor))),
      Expanded(flex: 2, child: Text('Số', style: TextStyle(fontSize: 12.5, color: context.mutedColor))),
      Expanded(flex: 2, child: Text('Điểm vào', style: TextStyle(fontSize: 12.5, color: context.mutedColor))),
      const SizedBox(width: 40),
    ]);
  }

  Widget _bulkBar(List<String> types) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<String>(
            initialValue: _bulkType.isEmpty ? null : _bulkType,
            isExpanded: true,
            hint: const Text('Đổi hạng mục'),
            decoration: const InputDecoration(isDense: true),
            items: [for (final t in types) DropdownMenuItem(value: t, child: Text(betTypeLabel(t), overflow: TextOverflow.ellipsis))],
            onChanged: (v) => setState(() => _bulkType = v ?? ''),
          ),
        ),
        SizedBox(width: 110, child: TextField(controller: _bulkScore, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(isDense: true, hintText: 'Đổi điểm vào'), onChanged: (_) => setState(() {}))),
        FilledButton.tonal(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _bulkType.isEmpty && _bulkScore.text.trim().isEmpty
              ? null
              : () {
                  c.applyBulk(type: _bulkType, score: _bulkScore.text);
                  setState(() {
                    _bulkType = '';
                    _bulkScore.clear();
                  });
                },
          child: const Text('Áp dụng'),
        ),
        TextButton(style: TextButton.styleFrom(foregroundColor: context.badColor), onPressed: c.deleteSelectedRows, child: Text('Xoá ${c.selectedRowCount} dòng')),
      ]),
    );
  }

  Widget _rowTile(BuildContext context, int i, List<String> types) {
    final r = c.rows[i];
    final typeList = types.contains(r.type) ? types : [...types, r.type];
    return Padding(
      key: ValueKey(r.uid),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Checkbox(value: r.selected, visualDensity: VisualDensity.compact, onChanged: (v) {
          r.selected = v ?? false;
          c.touchRows();
        }),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            initialValue: r.type,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12)),
            items: [for (final t in typeList) DropdownMenuItem(value: t, child: Text(betTypeLabel(t), overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              r.type = v ?? r.type;
              c.touchRows();
            },
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextField(controller: r.value, keyboardType: TextInputType.number, decoration: const InputDecoration(isDense: true, hintText: 'Số', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12))),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextField(controller: r.score, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(isDense: true, hintText: 'Điểm', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12))),
        ),
        SizedBox(
          width: 40,
          child: IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Xoá dòng',
            icon: const Icon(Icons.close, size: 20),
            onPressed: c.rows.length == 1 && r.isBlank ? null : () => c.removeRow(r),
          ),
        ),
      ]),
    );
  }
}
