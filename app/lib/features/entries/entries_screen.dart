import 'package:flutter/material.dart';
import '../../core/widgets/svg_icon.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/bet_types.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/mask_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/masked_text.dart';
import '../chat_calc/chat_prefill.dart';
import '../customers/add_customer_dialog.dart';
import 'dialogs.dart';
import 'edit_entry_sheet.dart';
import 'entries_controller.dart';
import 'entry_form.dart';
import 'entry_model.dart';
import '../calc/calc_sync.dart';
import 'offline_store.dart';
import '../../core/widgets/app_button.dart';

/// Nhập số: pick a customer, add numbers (by hand, from a pasted message or from a photo), review the list.
class EntriesScreen extends StatelessWidget {
  const EntriesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<EntriesController>(
      create: (c) => EntriesController(api: c.read<ApiClient>(), auth: c.read<AuthStore>(), stations: c.read<LotteryStations>())..init(),
      child: const _EntriesBody(),
    );
  }
}

class _EntriesBody extends StatefulWidget {
  const _EntriesBody();
  @override
  State<_EntriesBody> createState() => _EntriesBodyState();
}

class _EntriesBodyState extends State<_EntriesBody> {
  bool _selecting = false;
  final Set<String> _selected = {};
  final Map<String, String> _rowErrors = {};

  @override
  void initState() {
    super.initState();
    ChatPrefillHub.instance.addListener(_takePrefill);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _takePrefill();
      if (!mounted) return;
      _ctrl = context.read<EntriesController>()..addListener(_shareSelection);
      _shareSelection();
    });
  }

  EntriesController? _ctrl;

  /// Tính điểm opens on the customer and day chosen here.
  void _shareSelection() {
    final c = _ctrl;
    if (c == null || !mounted) return;
    CalcSync.maybeOf(context)?.select(customer: c.selectedName, date: c.entryDate);
  }

  /// "Dùng cho Nhập số" from the chat: hand the text, customer, date and đài to the form.
  void _takePrefill() {
    final p = ChatPrefillHub.instance.take();
    if (p == null || !mounted) return;
    context.read<EntriesController>().applyChatPrefill(p);
  }

  @override
  void dispose() {
    ChatPrefillHub.instance.removeListener(_takePrefill);
    _ctrl?.removeListener(_shareSelection);
    super.dispose();
  }

  Future<void> _pickCustomer(EntriesController c) async {
    final masked = context.read<MaskStore>().masked;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CustomerPicker(c: c, masked: masked),
    );
    if (picked == null || !mounted) return;
    if (picked == '\u0000add') {
      final created = await showAddCustomerDialog(context);
      if (created != null) c.addCustomerLocal(created);
    } else {
      c.selectCustomer(picked);
    }
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  Future<void> _delete(EntriesController c, Entry e, bool masked) async {
    final ok = await confirmDialog(context, title: 'Xoá số liệu', message: 'Xoá số liệu ${masked ? 'này' : '"${e.value}"'} (${e.customerName})? Không thể hoàn tác.', confirmText: 'Xoá', danger: true);
    if (!ok) return;
    final err = await c.deleteEntry(e);
    if (mounted) setState(() => _rowErrors[e.id] = err);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<EntriesController>();
    final mask = context.watch<MaskStore>();
    final masked = mask.masked;
    final shown = c.selectedName.isEmpty && !c.filter.all ? <Entry>[] : c.filtered(masked: masked);
    final showList = !c.loading && c.loadError.isEmpty && (c.selectedName.isNotEmpty || c.filter.all);
    final totals = totalsOf(c.customerEntries);

    return Listener(
      onPointerDown: (_) => mask.touch(),
      child: RefreshIndicator(
        onRefresh: c.reload,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: _header(context, c, masked, shown)),
            ),
            if (c.loading)
              const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))
            else if (c.loadError.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(children: [InfoBox(c.loadError), AppButton(label: 'Thử lại', variant: AppButtonVariant.primary, onPressed: c.reload)]),
                ),
              )
            else if (!showList)
              SliverPadding(padding: const EdgeInsets.all(24), sliver: SliverToBoxAdapter(child: Center(child: Text('Chọn khách hàng để xem và nhập số liệu.', style: TextStyle(color: context.mutedColor)))))
            else if (shown.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.all(24),
                sliver: SliverToBoxAdapter(child: Center(child: Text(c.followsForm && c.entries.any((e) => c.filter.all || e.customerName == c.selectedName) ? 'Chưa có số liệu ngày ${viDate(c.listDate)}${c.filter.all ? '' : ' (đài này)'}.' : c.filter.active ? 'Không có số liệu nào khớp bộ lọc.' : 'Khách hàng này chưa có số liệu nào.', style: TextStyle(color: context.mutedColor)))),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _EntryTile(
                    key: ValueKey(shown[i].id),
                    entry: shown[i],
                    withCustomer: c.filter.all,
                    selecting: _selecting,
                    selected: _selected.contains(shown[i].id),
                    error: _rowErrors[shown[i].id] ?? '',
                    onToggle: () => setState(() => _selected.contains(shown[i].id) ? _selected.remove(shown[i].id) : _selected.add(shown[i].id)),
                    onEdit: () => showEditEntry(context, c, shown[i]),
                    onDelete: () => _delete(c, shown[i], masked),
                  ),
                ),
              ),
            if (showList && !c.filter.all)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                sliver: SliverToBoxAdapter(child: _totalsCard(context, c, totals)),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, EntriesController c, bool masked, List<Entry> shown) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (c.packageActive == false) const InfoBox('Gói của bạn đã hết hạn. Vui lòng gia hạn ở mục Gói dịch vụ để tiếp tục nhập số liệu.', kind: InfoKind.warning),
      if (c.fromCache) const InfoBox('Đang offline: hiển thị số liệu đã lưu trên máy. Số liệu bạn nhập sẽ được gửi lên khi có mạng.', kind: InfoKind.warning),
      if (c.pending > 0)
        InfoBox(
          '${c.pending} thay đổi đang chờ đồng bộ.',
          kind: InfoKind.warning,
          action: AppButton(label: 'Đồng bộ ngay', variant: AppButtonVariant.ghost, onPressed: () => c.sync()),
        ),
      if (c.notice.isNotEmpty) InfoBox(c.notice, kind: InfoKind.success, onClose: c.clearNotice),
      for (final f in c.failures.toList()) InfoBox(f.message, onClose: () => c.dismissFailure(f)),
      for (final k in c.conflicts.toList()) _conflictBox(context, c, k),
      // customer picker
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _pickCustomer(c),
        child: InputDecorator(
          decoration: const InputDecoration(labelText: 'Khách hàng', suffixIcon: SvgIcon(AppSvg.chevronDown, size: 8)),
          child: Text(c.selectedName.isEmpty ? '-- Chọn khách hàng --' : c.selectedName, overflow: TextOverflow.ellipsis),
        ),
      ),
      const SizedBox(height: 12),
      if (c.selectedName.isNotEmpty) ...[EntryFormCard(controller: c), const SizedBox(height: 16)],
      // list header
      Text('Danh sách số liệu${c.selectedName.isNotEmpty && !c.filter.all ? ': ${c.selectedName}' : ''}', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const SizedBox(height: 4),
    ]);
  }

  Widget _conflictBox(BuildContext context, EntriesController c, SyncConflict k) {
    return InfoBox(
      'Số liệu "${k.mine['value'] ?? ''}" đã được sửa ở nơi khác. Giữ bản nào?',
      kind: InfoKind.warning,
      action: Wrap(children: [
        AppButton(label: 'Bản của tôi', variant: AppButtonVariant.ghost, onPressed: () => _resolve(c, k, true)),
        AppButton(label: 'Bản máy chủ', variant: AppButtonVariant.ghost, onPressed: () => _resolve(c, k, false)),
      ]),
    );
  }

  Future<void> _resolve(EntriesController c, SyncConflict k, bool mine) async {
    try {
      await c.resolveConflict(k, keepMine: mine);
    } on ApiError catch (e) {
      if (mounted) showSnack(context, e.message);
    }
  }

  Widget _totalsCard(BuildContext context, EntriesController c, EntryTotals t) {
    Widget cell(String label, double v, Color? color) => Expanded(
          child: Column(children: [
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.mutedColor)),
            const SizedBox(height: 4),
            MaskedText(formatNumber(v), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Thống kê: ${c.selectedName}', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          MaskedText('Tính trên ${c.customerEntries.length} số liệu (điểm trống = 0)', style: TextStyle(fontSize: 12, color: context.mutedColor)),
          const SizedBox(height: 12),
          Row(children: [
            cell('Tổng điểm vào', t.vao, context.okColor),
            cell('Tổng điểm ra', t.ra, context.badColor),
            cell('Chênh lệch (vào − ra)', t.chenhLech, t.chenhLech >= 0 ? context.okColor : context.badColor),
          ]),
        ]),
      ),
    );
  }
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({required this.c, required this.masked});
  final EntriesController c;
  final bool masked;
  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final q = foldQuery(_q);
    final list = [for (final cu in widget.c.customers) if (q.isEmpty || foldQuery(cu.name).contains(q)) cu];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(decoration: const InputDecoration(hintText: 'Tìm khách hàng...', prefixIcon: SvgIcon(AppSvg.search, size: 8)), onChanged: (v) => setState(() => _q = v)),
          ),
          ListTile(
            leading: const SvgIcon(AppSvg.addUser),
            title: const Text('Thêm khách hàng mới'),
            onTap: () => Navigator.pop(context, '\u0000add'),
          ),
          const Divider(height: 1),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(widget.c.customers.isEmpty ? 'Chưa có khách hàng nào.' : 'Không tìm thấy khách hàng.', style: TextStyle(color: context.mutedColor)))
                : ListView.builder(
                    controller: scroll,
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final cu = list[i];
                      return ListTile(
                        title: Text(cu.name),
                        trailing: widget.masked ? const Text('••••') : Text('${widget.c.entryCount(cu.name)}'),
                        selected: cu.name == widget.c.selectedName,
                        onTap: () => Navigator.pop(context, cu.name),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

String foldQuery(String s) => s.trim().toLowerCase();

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    super.key,
    required this.entry,
    required this.withCustomer,
    required this.selecting,
    required this.selected,
    required this.error,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });
  final Entry entry;
  final bool withCustomer;
  final bool selecting;
  final bool selected;
  final String error;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final stations = context.read<LotteryStations>();
    final station = e.station;
    final stationText = station == null || station.isEmpty || station == 'mb'
        ? null
        : (stations.isRegionCode(station) ? stations.regionOf(station).name : stations.stationName(station));
    final muted = TextStyle(fontSize: 12.5, color: context.mutedColor);
    const num = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: selecting ? onToggle : null,
        onLongPress: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 2, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              if (selecting) Padding(padding: const EdgeInsets.only(right: 8), child: SvgIcon(selected ? AppSvg.checkboxOn : AppSvg.checkboxOff, color: selected ? Theme.of(context).colorScheme.primary : null)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (withCustomer) Text(e.customerName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  // One line, one number size: kind, number, Vào, Ra; the date and station (least important) take what is left and are cut with "…".
                  LayoutBuilder(builder: (context, box) => Row(children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: box.maxWidth * 0.85),
                      child: FittedBox(
                        fit: BoxFit.scaleDown, // only when the figures alone take more than 85% of the line
                        alignment: Alignment.centerLeft,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          _Tag(betTypeLabel(e.type)),
                          const SizedBox(width: 8),
                          MaskedText(e.value, style: num.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(width: 10),
                          Text('Vào ', style: muted),
                          MaskedText(fmtPoints(e.score), style: num.copyWith(color: context.okColor)),
                          const SizedBox(width: 8),
                          Text('Ra ', style: muted),
                          MaskedText(fmtPoints(e.result), style: num.copyWith(color: context.badColor)),
                          if (e.pending) Padding(padding: const EdgeInsets.only(left: 6), child: SvgIcon(AppSvg.sync, size: 15, color: Brand.warning)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Tooltip(
                        message: stationText == null ? '' : stations.stationLabel(station),
                        child: Text([_shortDate(e.entryDate), ?stationText].join(' · '), style: muted, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
                      ),
                    ),
                  ])),
                  if ((e.note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: MaskedText(e.note!, style: muted)),
                ]),
              ),
              if (!selecting) ...[
                IconButton(tooltip: 'Sửa', padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 34, height: 34), icon: const SvgIcon(AppSvg.editText, size: 19), onPressed: onEdit),
                IconButton(tooltip: 'Xoá', padding: EdgeInsets.zero, constraints: const BoxConstraints.tightFor(width: 34, height: 34), icon: SvgIcon(AppSvg.delete, size: 19, color: context.badColor), onPressed: onDelete),
              ],
            ]),
            if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: Text(error, style: TextStyle(fontSize: 12.5, color: context.badColor))),
          ]),
        ),
      ),
    );
  }
}

/// dd/MM/yy of a yyyy-MM-dd date (short enough for the one-line entry row).
String _shortDate(String d) {
  final p = d.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0].substring(p[0].length > 2 ? p[0].length - 2 : 0)}' : d;
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}
