import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/theme.dart';
import '../scoring/date_field.dart';
import '../scoring/entry_model.dart';
import '../scoring/scoring_data.dart';
import '../scoring/scoring_logic.dart';
import '../entries/dialogs.dart';
import 'results_controller.dart';

/// Nhập kết quả: lottery results per day (one form for every region, station chosen by chip), reading them from a photo, and the
/// calculated "Điểm ra" list of the chosen day (frontend/src/views/ResultsView.vue).
class ResultsScreen extends StatefulWidget {
  const ResultsScreen({super.key});
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late final ResultsController _c;
  String? _routeDate;

  @override
  void initState() {
    super.initState();
    _c = ResultsController(context.read<ApiClient>(), context.read<LotteryStations>(), initialDate: _queryDate());
    _routeDate = _queryDate();
    _c.confirmOverwrite = (total, overwrites) async {
      if (!mounted) return false;
      return confirmDialog(
        context,
        title: 'Cập nhật Điểm ra',
        message: 'Kết quả vừa lưu sẽ cập nhật Điểm ra của $total số liệu, trong đó $overwrites số liệu đã có Điểm ra khác sẽ bị ghi đè. '
            'Bạn có thể bấm "Hoàn tác" ngay sau đó. Tiếp tục?',
        confirmText: 'Cập nhật',
      );
    };
    _c.init();
  }

  String? _queryDate() {
    try {
      return GoRouterState.of(context).uri.queryParameters['date'];
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Nhập kết quả" link of a day in Tính điểm: ?date=YYYY-MM-DD opens that day.
    final q = _queryDate();
    if (q != _routeDate) {
      _routeDate = q;
      if (q != null && q.isNotEmpty) _c.setDate(q);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ResultsController>.value(
      value: _c,
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_c.loadEntryData(), _c.loadDay()]);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: const [
            _Header(),
            SizedBox(height: 12),
            _ResultCard(),
            SizedBox(height: 12),
            _ScoreList(),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        'Nhập kết quả xổ số rồi bấm "Lưu kết quả": điểm ra của khách hàng tự được tính và lưu. Kết quả đã lưu chỉ hiển thị; bấm "Sửa" để chỉnh.',
        style: t.bodySmall?.copyWith(color: context.mutedColor),
      ),
    ]);
  }
}

class _Msg extends StatelessWidget {
  const _Msg(this.text, {required this.error, this.action, this.onAction});
  final String text;
  final bool error;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    final color = error ? context.badColor : context.okColor;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: action == null
          ? Text(text, style: TextStyle(color: color, fontSize: 13.5))
          : Row(children: [
              Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13.5))),
              TextButton(onPressed: onAction, child: Text(action!)),
            ]),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------

class _ResultCard extends StatelessWidget {
  const _ResultCard();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ResultsController>();
    final st = context.watch<LotteryStations>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Kết quả xổ số ${c.regionName}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Row(children: [
            IconButton.outlined(tooltip: 'Ngày trước', icon: const Icon(Icons.chevron_left), onPressed: () => c.shiftDay(-1)),
            const SizedBox(width: 8),
            Expanded(child: DateField(value: c.date, onChanged: c.setDate, label: 'Ngày quay', dense: true)),
            const SizedBox(width: 8),
            IconButton.outlined(tooltip: 'Ngày sau', icon: const Icon(Icons.chevron_right), onPressed: () => c.shiftDay(1)),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact, padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4))),
              segments: [for (final r in st.regionList) ButtonSegment(value: r.id, label: Text(r.name, maxLines: 1, overflow: TextOverflow.fade, softWrap: false))],
              selected: {c.region},
              onSelectionChanged: (s) => c.setRegion(s.first),
            ),
          ),
          const _PhotoBox(),
          if (c.dayLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator())),
          if (!c.dayLoading) ...[
            if (c.error != null) _Msg(c.error!, error: true),
            if (c.saveMsg != null) _Msg(c.saveMsg!, error: false),
            const SizedBox(height: 12),
            const _ResultForm(),
          ],
        ]),
      ),
    );
  }
}

class _PhotoBox extends StatelessWidget {
  const _PhotoBox();

  Future<void> _choose(BuildContext context, ResultsController c) async {
    final camera = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Chụp ảnh'), onTap: () => Navigator.pop(ctx, true)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Chọn ảnh từ thư viện'), onTap: () => Navigator.pop(ctx, false)),
        ]),
      ),
    );
    if (camera != null) c.readPhoto(camera: camera);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ResultsController>();
    final north = c.region == 'mb';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: c.ocrRunning ? null : () => _choose(context, c),
            icon: c.ocrRunning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.photo_camera_outlined),
            label: Text(c.ocrRunning ? 'Đang đọc ảnh...' : (north ? 'Đọc kết quả từ ảnh' : 'Đọc kết quả từ ảnh (nhiều đài)')),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          north
              ? 'Ảnh được đọc ngay trên máy. Đọc ảnh có thể sai (đặc biệt số có số 0 ở đầu), luôn kiểm tra lại trước khi lưu.'
              : 'Chụp hoặc chọn ảnh bảng kết quả Miền Nam / Miền Trung (mỗi đài một cột). Kết quả chỉ là gợi ý để bạn kiểm tra, chưa lưu cho tới khi bạn bấm "Lưu kết quả".',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.mutedColor),
        ),
        if (c.photoPath != null && !c.ocrRunning)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(c.photoPath!), height: 150, width: double.infinity, fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          ),
        if (c.ocrError != null) _Msg(c.ocrError!, error: true),
        if (c.ocrNote != null) _Msg(c.ocrNote!, error: false),
        if (c.ocrWarnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final w in c.ocrWarnings) Text('• $w', style: TextStyle(color: context.badColor, fontSize: 13)),
            ]),
          ),
      ]),
    );
  }
}

// ---- The form of one result: Miền Bắc, or the chosen station of Miền Trung / Miền Nam --------------------------------

class _ResultForm extends StatelessWidget {
  const _ResultForm();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ResultsController>();
    final st = context.watch<LotteryStations>();
    final north = c.region == 'mb';
    final cur = c.curStation;
    final children = <Widget>[];
    if (!north) {
      children.add(_StationChips(c, st));
      if (cur.isEmpty) {
        children.add(Padding(padding: const EdgeInsets.only(top: 10), child: Text('Ngày này không có đài nào của miền này.', style: TextStyle(color: context.mutedColor))));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
      }
      children.add(const SizedBox(height: 10));
    }
    final name = north ? 'Miền Bắc' : st.stationName(cur);
    final locked = c.lockedOf(cur);
    final form = c.formOf(cur) ?? const <String, List<String>>{};
    final t = Theme.of(context).textTheme;
    children.add(InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: c.toggleGrid,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Expanded(child: Text(north ? 'Nhập tay các giải' : 'Nhập tay các giải · $name', style: t.labelLarge, overflow: TextOverflow.ellipsis)),
          Text('${c.filledOf(cur)}/${c.totalBoxes}', style: TextStyle(color: context.mutedColor, fontSize: 13)),
          const SizedBox(width: 6),
          Icon(c.gridOpen ? Icons.expand_less : Icons.expand_more, size: 22),
        ]),
      ),
    ));
    if (c.gridOpen) {
      children.add(const SizedBox(height: 10));
      for (final p in c.structure) {
        final cells = form[p.tier] ?? const <String>[];
        final single = singleTiers.contains(p.tier);
        children.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: p.label.replaceAll(' (MN, MT)', ''), style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: '  ${p.count} ô · ${p.digits} số', style: t.bodySmall?.copyWith(color: context.mutedColor)),
          ])),
        ));
        children.add(Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (var k = 0; k < cells.length; k++)
            DigitCell(
              key: ValueKey('$cur-${p.tier}-$k'),
              value: cells[k],
              digits: p.digits,
              readOnly: locked,
              bad: north ? (cells[k].trim().isNotEmpty && cells[k].trim().length != p.digits) : c.cellBad(cur, p, cells[k], k),
              big: p.tier == 'dacBiet',
              onChanged: (v) => c.setCell(north ? null : cur, p, k, v),
              semantic: '${p.label} $name số ${k + 1}',
            ),
          if (!locked && !single) ...[
            _CellButton(icon: Icons.add, tooltip: 'Thêm ô ${p.label}', onPressed: cells.length >= p.count + maxExtraCells ? null : () => c.addCell(north ? null : cur, p)),
            if (cells.length > p.count) _CellButton(icon: Icons.remove, tooltip: 'Bớt ô ${p.label}', onPressed: () => c.removeCell(north ? null : cur, p)),
          ],
        ]));
        children.add(const SizedBox(height: 10));
      }
    }
    children.add(const SizedBox(height: 12));
    children.add(Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
      if (c.savedOf(cur))
        OutlinedButton(
          style: OutlinedButton.styleFrom(foregroundColor: context.badColor, minimumSize: const Size(0, 44)),
          onPressed: c.deleting.isNotEmpty ? null : () => _confirmDelete(context, c, cur),
          child: Text(c.deleting == cur ? 'Đang xoá...' : 'Xoá kết quả này'),
        ),
      OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        onPressed: locked ? (north ? c.unlockMb : () => c.unlockColumn(cur)) : null,
        child: const Text('Sửa'),
      ),
      TextButton(onPressed: c.clearForm, child: const Text('Xoá form')),
      _SaveButton(c),
    ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _CellButton extends StatelessWidget {
  const _CellButton({required this.icon, required this.tooltip, required this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 40,
        height: 40,
        child: IconButton.outlined(tooltip: tooltip, padding: EdgeInsets.zero, iconSize: 20, icon: Icon(icon), onPressed: onPressed),
      );
}

/// One chip per station of the day (the schedule plus the ones added), and "+ Đài khác (N)" for the rest of the region.
class _StationChips extends StatelessWidget {
  const _StationChips(this.c, this.st);
  final ResultsController c;
  final LotteryStations st;
  @override
  Widget build(BuildContext context) {
    final others = c.otherStations;
    return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (final s in c.boardStations)
        ChoiceChip(
          selected: c.curStation == s,
          showCheckmark: false,
          label: Text('${st.stationName(s)}${c.boardSaved.contains(s) ? ' ✓' : ''}'),
          onSelected: (_) => c.selectStation(s),
        ),
      if (others.isNotEmpty)
        PopupMenuButton<String>(
          tooltip: 'Thêm đài khác',
          onSelected: c.addStation,
          itemBuilder: (_) => [for (final o in others) PopupMenuItem(value: o.value, child: Text(o.label))],
          child: IgnorePointer(child: ActionChip(label: Text('+ Đài khác (${others.length})'), onPressed: () {})),
        ),
    ]);
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton(this.c);
  final ResultsController c;
  @override
  Widget build(BuildContext context) => FilledButton(onPressed: c.saving ? null : c.save, child: Text(c.saving ? 'Đang lưu...' : 'Lưu kết quả'));
}

Future<void> _confirmDelete(BuildContext context, ResultsController c, String station) async {
  final name = context.read<LotteryStations>().stationName(station);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Xoá kết quả'),
      content: Text('Xoá kết quả xổ số $name ngày ${viDate(c.date)}? Không thể hoàn tác.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Huỷ')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: ctx.badColor), onPressed: () => Navigator.pop(ctx, true), child: const Text('Xoá')),
      ],
    ),
  );
  if (ok == true) await c.deleteResult(station);
}

/// One box of a prize: digits only, never longer than the prize has.
class DigitCell extends StatefulWidget {
  const DigitCell({super.key, required this.value, required this.digits, required this.readOnly, required this.onChanged, this.bad = false, this.semantic, this.big = false, this.maxWidth});
  final String value;
  final int digits;
  final bool readOnly;
  final bool bad;
  final bool big;
  final double? maxWidth; // narrower than the natural width when the columns share a small screen
  final String? semantic;
  final ValueChanged<String> onChanged;
  @override
  State<DigitCell> createState() => _DigitCellState();
}

class _DigitCellState extends State<DigitCell> {
  late final TextEditingController _ctrl = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(DigitCell old) {
    super.didUpdateWidget(old);
    if (_ctrl.text != widget.value) {
      _ctrl.value = TextEditingValue(text: widget.value, selection: TextSelection.collapsed(offset: widget.value.length));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bad = widget.bad;
    final color = bad ? context.badColor : null;
    OutlineInputBorder border(Color? c, double w) => OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c ?? Theme.of(context).colorScheme.outline, width: w));
    final width = (widget.digits * 11.0 + 26).clamp(52.0, 96.0).clamp(0.0, widget.maxWidth ?? 96.0);
    return SizedBox(
      width: width,
      child: Semantics(
        label: widget.semantic,
        child: TextField(
          controller: _ctrl,
          readOnly: widget.readOnly,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(widget.digits)],
          style: TextStyle(fontWeight: widget.big ? FontWeight.w800 : FontWeight.w600, fontSize: (widget.maxWidth != null && widget.maxWidth! < 80) ? 13 : (widget.big ? 16 : 14), color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            isDense: true,
            hintText: '0' * widget.digits,
            hintStyle: TextStyle(color: Theme.of(context).hintColor.withValues(alpha: 0.4), fontWeight: FontWeight.w400),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            counterText: '',
            border: border(color, 1),
            enabledBorder: border(color, bad ? 1.5 : 1),
            focusedBorder: border(color ?? Theme.of(context).colorScheme.primary, 2),
          ),
        ),
      ),
    );
  }
}

// ---- Điểm ra của ngày ---------------------------------------------------------------------------------------------

class _ScoreList extends StatelessWidget {
  const _ScoreList();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ResultsController>();
    final t = Theme.of(context).textTheme;
    final names = <String>{for (final x in c.customers) x.name, for (final e in c.entries) if (e.entryDate == c.date) (e.customerName.isEmpty ? noCustomerName : e.customerName)}.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final filter = names.contains(c.customerFilter) ? c.customerFilter : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Điểm ra ngày ${viDate(c.date)}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Tự tính theo kết quả đã lưu và công thức của từng khách. Không nhập tay.', style: t.bodySmall?.copyWith(color: context.mutedColor)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            key: ValueKey('cf$filter${names.length}'),
            initialValue: filter,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Khách hàng', isDense: true),
            items: [
              const DropdownMenuItem(value: '', child: Text('Tất cả khách hàng')),
              for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => c.setCustomerFilter(v ?? ''),
          ),
          if (c.syncMsg != null) _Msg(c.syncMsg!, error: false, action: c.undoItems == null ? null : (c.undoing ? 'Đang hoàn tác...' : 'Hoàn tác'), onAction: c.undoing ? null : c.undoScores),
          if (c.syncError != null) _Msg(c.syncError!, error: true),
          if (DataSource.fromCache) const _Msg('Đang offline: đang dùng số liệu đã lưu trên máy. Lưu kết quả và lưu điểm ra cần có mạng.', error: false),
          const SizedBox(height: 10),
          if (c.entriesLoading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Center(child: CircularProgressIndicator()))
          else if (c.entriesError != null)
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Msg(c.entriesError!, error: true),
              TextButton.icon(onPressed: c.loadEntryData, icon: const Icon(Icons.refresh), label: const Text('Thử lại')),
            ])
          else if (c.groups.isEmpty)
            Text('Không có số liệu nào của ngày này.', style: TextStyle(color: context.mutedColor))
          else
            for (final g in c.groups) _CustomerGroup(g.name, g.entries),
        ]),
      ),
    );
  }
}

class _CustomerGroup extends StatelessWidget {
  const _CustomerGroup(this.name, this.entries);
  final String name;
  final List<Entry> entries;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ResultsController>();
    final st = context.watch<LotteryStations>();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Row(children: [
            Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
            Text('${entries.length} số', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
          ]),
        ),
        for (final e in entries)
          Builder(builder: (context) {
            final v = c.scoreOf(e);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 5,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(
                      [
                        if (e.betType != null && e.betType!.isNotEmpty) e.betType == 'de' ? 'Đề' : (e.betType == 'lo' ? 'Lô' : e.betType!),
                        if (e.station != null && e.station!.isNotEmpty && e.station != 'mb') st.stationLabel(e.station),
                        if ((e.score ?? '').isNotEmpty) 'Điểm vào: ${formatNumber(toNumber(e.score))}',
                      ].join(' · '),
                      style: TextStyle(color: context.mutedColor, fontSize: 12),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: v == null
                      ? Text('Chưa có kết quả xổ số', textAlign: TextAlign.end, style: TextStyle(color: context.mutedColor, fontSize: 12.5))
                      : Text.rich(
                          textAlign: TextAlign.end,
                          TextSpan(children: [
                            TextSpan(text: 'Điểm ra: ', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
                            TextSpan(text: formatNumber(v), style: TextStyle(fontWeight: FontWeight.w800, color: v > 0 ? context.okColor : null)),
                          ]),
                        ),
                ),
              ]),
            );
          }),
      ]),
    );
  }
}
