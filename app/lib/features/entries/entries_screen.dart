import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _search = TextEditingController();
  bool _selecting = false;
  final Set<String> _selected = {};
  String _copyMessage = '';
  final Map<String, String> _rowErrors = {};
  String _bulkError = '';
  bool _bulkBusy = false;

  @override
  void initState() {
    super.initState();
    ChatPrefillHub.instance.addListener(_takePrefill);
    WidgetsBinding.instance.addPostFrameCallback((_) => _takePrefill());
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
    _search.dispose();
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

  Future<void> _pickDate(EntriesController c) async {
    final now = DateTime.now();
    final cur = DateTime.tryParse(c.filter.date) ?? now;
    final d = await showDatePicker(context: context, initialDate: cur, firstDate: DateTime(now.year - 5), lastDate: DateTime(now.year + 2));
    if (d != null) {
      c.filter.date = isoOf(d);
      c.touchFilter();
    }
  }

  Future<void> _copy(EntriesController c, List<Entry> shown) async {
    if (shown.isEmpty) return;
    final label = [c.filter.all ? 'tất cả khách' : c.selectedName, c.filter.date].where((s) => s.isNotEmpty).join(', ');
    if (c.confirmCopy) {
      final ok = await confirmDialog(
        context,
        title: 'Sao chép số liệu',
        message: 'Sao chép ${shown.length} số liệu${label.isEmpty ? '' : ' ($label)'} vào bộ nhớ tạm? Dữ liệu này nhạy cảm, chỉ dán ở nơi bạn tin tưởng.',
        confirmText: 'Sao chép',
      );
      if (!ok) return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: entriesToText(shown, withCustomer: c.filter.all)));
      setState(() => _copyMessage = 'Đã sao chép ${shown.length} số liệu');
    } catch (_) {
      setState(() => _copyMessage = 'Không sao chép được');
    }
  }

  Future<void> _delete(EntriesController c, Entry e, bool masked) async {
    if (e.pending) {
      setState(() => _rowErrors[e.id] = 'Số liệu đang chờ đồng bộ, hãy đợi đồng bộ xong rồi xoá.');
      return;
    }
    final ok = await confirmDialog(context, title: 'Xoá số liệu', message: 'Xoá số liệu ${masked ? 'này' : '"${e.value}"'} (${e.customerName})? Không thể hoàn tác.', confirmText: 'Xoá', danger: true);
    if (!ok) return;
    final err = await c.deleteEntry(e);
    if (mounted) setState(() => _rowErrors[e.id] = err);
  }

  Future<void> _deleteSelected(EntriesController c) async {
    final list = c.entries.where((e) => _selected.contains(e.id)).toList();
    if (list.isEmpty) return;
    final ok = await confirmDialog(context, title: 'Xoá số liệu đã chọn', message: 'Xoá ${list.length} số liệu đã chọn? Không thể hoàn tác.', confirmText: 'Xoá', danger: true);
    if (!ok || !mounted) return;
    setState(() {
      _bulkBusy = true;
      _bulkError = '';
    });
    final failed = await c.deleteMany(list);
    if (!mounted) return;
    setState(() {
      _bulkBusy = false;
      _selected.removeWhere((id) => !c.entries.any((e) => e.id == id));
      if (failed > 0) _bulkError = '$failed số liệu không xoá được (đang chờ đồng bộ hoặc lỗi mạng), thử lại.';
      if (_selected.isEmpty) _selecting = false;
    });
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
                sliver: SliverToBoxAdapter(child: Center(child: Text(c.filter.active ? 'Không có số liệu nào khớp bộ lọc.' : 'Khách hàng này chưa có số liệu nào.', style: TextStyle(color: context.mutedColor)))),
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
      const Align(alignment: Alignment.centerLeft, child: MaskBar()),
      const SizedBox(height: 10),
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
          decoration: const InputDecoration(labelText: 'Khách hàng', suffixIcon: Icon(Icons.arrow_drop_down)),
          child: Text(c.selectedName.isEmpty ? '-- Chọn khách hàng --' : c.selectedName, overflow: TextOverflow.ellipsis),
        ),
      ),
      const SizedBox(height: 12),
      if (c.selectedName.isNotEmpty) ...[EntryFormCard(controller: c), const SizedBox(height: 16)],
      // list header
      Text('Danh sách số liệu${c.selectedName.isNotEmpty && !c.filter.all ? ': ${c.selectedName}' : ''}', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      _filterBar(context, c),
      _copyBar(context, c, shown, masked),
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

  Widget _filterBar(BuildContext context, EntriesController c) {
    final f = c.filter;
    final types = c.betTypes;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      TextField(
        controller: _search,
        decoration: InputDecoration(
          hintText: 'Tìm số, ghi chú, điểm',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: f.q.isEmpty ? null : IconButton(icon: const Icon(Icons.close), onPressed: () { _search.clear(); f.q = ''; c.touchFilter(); }),
        ),
        onChanged: (v) {
          f.q = v;
          c.touchFilter();
        },
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: AppButton(label: f.date.isEmpty ? 'Mọi ngày' : viDate(f.date), variant: AppButtonVariant.secondary, icon: Icons.event, onPressed: () => _pickDate(c)),
        ),
        if (f.date.isNotEmpty) IconButton(tooltip: 'Bỏ lọc ngày', icon: const Icon(Icons.close, size: 18), onPressed: () { f.date = ''; c.touchFilter(); }),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: f.type.isEmpty || !types.contains(f.type) ? '' : f.type,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true),
            items: [const DropdownMenuItem(value: '', child: Text('Mọi hạng mục')), for (final t in types) DropdownMenuItem(value: t, child: Text(betTypeLabel(t), overflow: TextOverflow.ellipsis))],
            onChanged: (v) {
              f.type = v ?? '';
              c.touchFilter();
            },
          ),
        ),
      ]),
      Row(children: [
        Expanded(
          child: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Tất cả khách hàng'),
            value: f.all,
            onChanged: (v) {
              f.all = v ?? false;
              c.touchFilter();
            },
          ),
        ),
        if (f.active) AppButton(label: 'Xoá lọc', variant: AppButtonVariant.ghost, onPressed: () { _search.clear(); f.clear(); c.touchFilter(); }),
      ]),
    ]);
  }

  Widget _copyBar(BuildContext context, EntriesController c, List<Entry> shown, bool masked) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        AppButton(label: 'Sao chép ${masked ? '•••' : shown.length} số liệu', variant: AppButtonVariant.secondary, icon: Icons.copy, onPressed: shown.isEmpty || masked ? null : () => _copy(c, shown)),
        AppButton(label: _selecting ? 'Thôi chọn' : 'Chọn để xoá', variant: AppButtonVariant.secondary, icon: _selecting ? Icons.close : Icons.checklist, onPressed: shown.isEmpty ? null : () => setState(() { _selecting = !_selecting; _selected.clear(); _bulkError = ''; })),
      ]),
      if (masked) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Đang ẩn số liệu: bấm Hiện số liệu để sao chép.', style: TextStyle(fontSize: 12.5, color: context.mutedColor))),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('Hỏi xác nhận trước khi sao chép'),
        value: c.confirmCopy,
        onChanged: (v) => c.setConfirmCopy(v ?? false),
      ),
      if (_copyMessage.isNotEmpty) Text(_copyMessage, style: const TextStyle(fontWeight: FontWeight.w700), semanticsLabel: _copyMessage),
      if (_selecting)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            AppButton(label: 'Chọn tất cả', variant: AppButtonVariant.ghost, onPressed: () => setState(() { _selected..clear()..addAll(shown.where((e) => !e.pending).map((e) => e.id)); })),
            const Spacer(),
            AppButton(label: 'Xoá ${_selected.length} dòng', variant: AppButtonVariant.danger, loading: _bulkBusy, onPressed: _selected.isEmpty || _bulkBusy ? null : () => _deleteSelected(c)),
          ]),
        ),
      if (_bulkError.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: InfoBox(_bulkError)),
    ]);
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
            child: TextField(decoration: const InputDecoration(hintText: 'Tìm khách hàng...', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v)),
          ),
          ListTile(
            leading: const Icon(Icons.person_add_alt_1),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: selecting ? onToggle : null,
        onLongPress: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (selecting) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(selected ? Icons.check_box : Icons.check_box_outline_blank, color: selected ? Theme.of(context).colorScheme.primary : null)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (withCustomer) Text(e.customerName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(viDate(e.entryDate), style: muted),
                    _Tag(betTypeLabel(e.type)),
                    if (stationText != null) _Tag(stationText, tooltip: stations.stationLabel(station)),
                    if (e.pending) _Tag('Chờ đồng bộ', color: Brand.warning),
                  ]),
                  const SizedBox(height: 4),
                  Wrap(spacing: 14, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    MaskedText(e.value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Vào ', style: muted),
                      MaskedText(fmtPoints(e.score), style: TextStyle(fontWeight: FontWeight.w600, color: context.okColor)),
                    ]),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Ra ', style: muted),
                      MaskedText(fmtPoints(e.result), style: TextStyle(fontWeight: FontWeight.w600, color: context.badColor)),
                    ]),
                  ]),
                  if ((e.note ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: MaskedText(e.note!, style: muted)),
                ]),
              ),
              if (!selecting) ...[
                IconButton(tooltip: 'Sửa', visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 20), onPressed: onEdit),
                IconButton(tooltip: 'Xoá', visualDensity: VisualDensity.compact, icon: Icon(Icons.delete_outline, size: 20, color: context.badColor), onPressed: onDelete),
              ],
            ]),
            if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: Text(error, style: TextStyle(fontSize: 12.5, color: context.badColor))),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.color, this.tooltip});
  final String text;
  final Color? color;
  final String? tooltip;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color == null ? null : c)),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}
