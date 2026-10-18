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
import '../scoring/scoring_data.dart';
import '../entries/dialogs.dart';
import 'results_controller.dart';
import '../../core/widgets/app_button.dart';
import '../../core/keyboard.dart';

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
            _SyncNotices(),
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
              AppButton(label: action!, variant: AppButtonVariant.ghost, onPressed: onAction),
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
          child: AppButton(
            label: north ? 'Đọc kết quả từ ảnh' : 'Đọc kết quả từ ảnh (nhiều đài)',
            variant: AppButtonVariant.secondary,
            icon: Icons.photo_camera_outlined,
            loading: c.ocrRunning,
            onPressed: c.ocrRunning ? null : () => _choose(context, c),
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
    // One row: one delete button (the saved result of this đài, or just the form while nothing is saved), Sửa, Lưu kết quả.
    final saved = c.savedOf(cur);
    children.add(Row(children: [
      AppButton.icon(
        label: saved ? 'Xoá kết quả này' : 'Xoá form',
        variant: saved ? AppButtonVariant.danger : AppButtonVariant.secondary,
        icon: Icons.delete_outline,
        loading: saved && c.deleting == cur,
        onPressed: saved ? (c.deleting.isNotEmpty ? null : () => _confirmDelete(context, c, cur)) : c.clearForm,
      ),
      const SizedBox(width: 8),
      Expanded(child: AppButton(label: 'Sửa', variant: AppButtonVariant.secondary, onPressed: locked ? (north ? c.unlockMb : () => c.unlockColumn(cur)) : null)),
      const SizedBox(width: 8),
      Expanded(flex: 2, child: _SaveButton(c)),
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
  Widget build(BuildContext context) => AppButton(label: 'Lưu kết quả', variant: AppButtonVariant.primary, loading: c.saving, onPressed: c.saving ? null : c.save);
}

Future<void> _confirmDelete(BuildContext context, ResultsController c, String station) async {
  final name = context.read<LotteryStations>().stationName(station);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Xoá kết quả'),
      content: Text('Xoá kết quả xổ số $name ngày ${viDate(c.date)}? Không thể hoàn tác.'),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(ctx, false)),
        AppButton(label: 'Xoá', variant: AppButtonVariant.danger, onPressed: () => Navigator.pop(ctx, true)),
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
          keyboardType: kNumbersKeyboard,
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

// ---- Notices of the last save (the list of customers' Điểm ra is no longer shown on this tab) ----------------------------

class _SyncNotices extends StatelessWidget {
  const _SyncNotices();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ResultsController>();
    final offline = DataSource.fromCache;
    if (c.syncMsg == null && c.syncError == null && !offline) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c.syncMsg != null) _Msg(c.syncMsg!, error: false, action: c.undoItems == null ? null : (c.undoing ? 'Đang hoàn tác...' : 'Hoàn tác'), onAction: c.undoing ? null : c.undoScores),
        if (c.syncError != null) _Msg(c.syncError!, error: true),
        if (offline) const _Msg('Đang offline: lưu kết quả cần có mạng.', error: false),
      ]),
    );
  }
}
