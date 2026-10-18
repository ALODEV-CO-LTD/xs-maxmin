import 'package:flutter/material.dart';
import 'scoring_data.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/bet_types.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/mask_store.dart';
import '../../core/theme.dart';
import '../calc/calc_screen.dart';
import '../calc/calc_sync.dart';
import '../../core/widgets/masked_text.dart';
import 'date_field.dart';
import 'delete_data_dialog.dart';
import 'deletion_schedules_page.dart';
import 'entry_model.dart';
import 'scoring_controller.dart';
import 'scoring_days.dart';
import 'scoring_logic.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_dropdown.dart';

String _money(num n) => '${formatNumber(n.round())} đ';
String _signed(num n) => '${n > 0 ? '+' : ''}${_money(n)}';

/// Tính điểm: one customer's numbers by day with the money summary, "Điểm ra" calculated and stored automatically
/// (frontend/src/views/ScoringView.vue).
class ScoringScreen extends StatefulWidget {
  const ScoringScreen({super.key});
  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  late final ScoringController _c;
  Future<void>? _loaded;
  String? _linkKey;

  @override
  void initState() {
    super.initState();
    _c = ScoringController(context.read<ApiClient>(), context.read<LotteryStations>());
    _loaded = _c.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _sync = CalcSync.maybeOf(context)?..addListener(_onSync);
      final s = _sync;
      if (s != null && s.customer.isNotEmpty) _loaded = _loaded!.then((_) => mounted ? _c.syncFrom(customer: s.customer, date: s.date) : null);
    });
  }

  CalcSync? _sync;
  int _seenActivation = 0;

  /// Opened as a tab (or the customer / day of Nhập số changed while it is the visible one): re-read and follow Nhập số.
  void _onSync() {
    final s = _sync;
    if (s == null || !mounted || s.activeTab != 'scoring' || s.activations == _seenActivation) return;
    _seenActivation = s.activations;
    _loaded = _c.syncFrom(customer: s.customer, date: s.date);
  }

  // A link such as /calc?tab=scoring&customer=An&date=...&added=3 (after the numbers of a chat were saved in Nhập số):
  // open that customer and day, with a note.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Uri? uri;
    try {
      uri = GoRouterState.of(context).uri;
    } catch (_) {/* not under a router (tests) */}
    final q = uri?.queryParameters;
    if (uri == null || q == null || q['tab'] != 'scoring' || (q['customer'] ?? '').isEmpty || uri.toString() == _linkKey) return;
    _linkKey = uri.toString();
    final customer = q['customer']!, date = q['date'] ?? '', added = int.tryParse(q['added'] ?? '') ?? 0;
    _loaded?.then((_) {
      if (mounted) _c.focusOn(customer: customer, date: date, added: added);
    });
  }

  @override
  void dispose() {
    _sync?.removeListener(_onSync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ScoringController>.value(
      value: _c,
      child: Listener(
        // any touch restarts the idle timer of "Hiện số liệu"
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => context.read<MaskStore>().touch(),
        child: RefreshIndicator(
          onRefresh: () async {
            _c.lotteryCache.clear();
            await _c.load();
          },
          child: const _Body(),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ScoringController>();
    final t = Theme.of(context).textTheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Text(
          'Điểm ra được máy tự động tính và lưu theo kết quả xổ số đã nhập ở màn Nhập kết quả. Tỉ lệ ăn của từng khách chỉnh ở màn Khách hàng.',
          style: t.bodySmall?.copyWith(color: context.mutedColor),
        ),
        const SizedBox(height: 12),
        const _Toolbar(),
        if (c.autoCalcError != null) _Banner(c.autoCalcError!, error: true),
        if (c.notice != null) _Banner(c.notice!, error: false),
        if (DataSource.fromCache) const _Banner('Đang offline: đang tính theo số liệu và kết quả xổ số đã lưu trên máy. Ngày nào chưa từng mở khi có mạng thì chưa có kết quả.', error: false),
        const SizedBox(height: 12),
        if (c.loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator()))
        else if (c.loadError != null)
          Column(children: [
            _Banner(c.loadError!, error: true),
            AppButton(label: 'Thử lại', variant: AppButtonVariant.ghost, icon: Icons.refresh, onPressed: c.load),
          ])
        else ...[
          const _Filters(),
          const SizedBox(height: 12),
          if (c.selectedCustomer.isNotEmpty && c.days.isNotEmpty) ...[const _SummaryCard(), const SizedBox(height: 12)],
          if (c.selectedCustomer.isEmpty)
            const _Empty(icon: Icons.people_outline, text: 'Chọn khách hàng ở trên để xem điểm ra của họ.')
          else if (c.days.isEmpty)
            _Empty(
              icon: Icons.inbox_outlined,
              text: c.onlyMissing
                  ? 'Không có ngày nào thiếu kết quả xổ số trong khoảng này. Bỏ chọn ô lọc để xem toàn bộ lịch sử.'
                  : (c.hasEntriesForCustomer ? 'Chưa có số liệu của khách này trong ngày đã chọn. Bấm X ở ô Ngày để xem mọi ngày.' : 'Khách hàng này chưa có số liệu nào.'),
            )
          else ...[
            for (final d in c.visibleDays) _DayCard(d),
            if (c.hiddenDayCount > 0)
              AppButton(label: 'Xem thêm ngày cũ (${c.hiddenDayCount < ScoringController.pageDays ? c.hiddenDayCount : ScoringController.pageDays} / còn ${c.hiddenDayCount} ngày)', variant: AppButtonVariant.secondary, onPressed: c.showMoreDays),
          ],
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.text, {required this.error});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final color = error ? context.badColor : context.okColor;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Text(text, style: TextStyle(color: color, fontSize: 13.5)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Icon(icon, size: 36, color: context.mutedColor),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor)),
          ]),
        ),
      );
}

// ---- toolbar: mask + delete -------------------------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar();
  @override
  Widget build(BuildContext context) {
    final c = context.read<ScoringController>();
    final api = context.read<ApiClient>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            AppButton(label: 'Xóa số liệu', variant: AppButtonVariant.secondary, size: AppButtonSize.small, onPressed: () async {
                final n = await showDeleteDataDialog(context, api: api, customerName: c.selectedCustomer, dateFrom: c.dateFrom, dateTo: c.dateTo);
                if (n != null) await c.afterDeleted(n);
              }),
            AppButton(label: 'Đặt lịch xóa', variant: AppButtonVariant.secondary, size: AppButtonSize.small, onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DeletionSchedulesPage(api: api, customerName: c.selectedCustomer)))),
          ]),
        ]),
      ),
    );
  }
}

// ---- filters ----------------------------------------------------------------------------------------------------

class _Filters extends StatelessWidget {
  const _Filters();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ScoringController>();
    final names = [for (final x in c.customers) x.name];
    final customer = names.contains(c.selectedCustomer) ? c.selectedCustomer : '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Only the customer and the day (they follow Nhập số); ⟳ = read everything again and recalculate.
          AppDropdown<String>(
            key: ValueKey('cust${names.length}'),
            initialValue: customer,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Khách hàng'),
            items: [const DropdownMenuItem(value: '', child: Text('-- Chọn khách hàng --')), for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => c.selectCustomer(v ?? ''),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DateField(label: 'Ngày', value: c.dateTo, clearable: true, onChanged: c.setDay)),
            const SizedBox(width: 6),
            c.autoCalcRunning > 0
                ? const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : AppButton(label: 'Tính lại', variant: AppButtonVariant.secondary, size: AppButtonSize.small, icon: Icons.refresh, onPressed: c.selectedCustomer.isEmpty ? null : () => c.syncFrom()),
          ]),
        ]),
      ),
    );
  }
}

// ---- summary tiles ----------------------------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard();
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ScoringController>();
    final masked = context.select<MaskStore, bool>((m) => m.masked);
    final s = c.total;
    final t = Theme.of(context).textTheme;
    Color? tone(double v) => masked ? null : (v > 0 ? context.okColor : (v < 0 ? context.badColor : null));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: _Tile(label: '(1) Tiền khách gửi', value: _money(s.sentMoney), sub: '${formatNumber(s.sentLots)} lô${s.sentPoints > 0 ? ' · ${formatNumber(s.sentPoints)} điểm' : ''}')),
            const SizedBox(width: 8),
            Expanded(child: _Tile(label: '(2) Tiền khách trúng', value: _money(s.wonMoney), sub: '${formatNumber(s.wonLots)} lô trúng${s.wonHits != s.wonLots ? ' · ${formatNumber(s.wonHits)} lần' : ''}')),
          ]),
          const SizedBox(height: 8),
          _Tile(
            label: '(3) Còn lại = (1) − (2)',
            value: _signed(s.remaining),
            sub: s.remaining > 0 ? 'Còn lại sau khi trả khách' : (s.remaining < 0 ? 'Phải trả khách thêm' : ''),
            color: tone(s.remaining),
            highlight: true,
          ),
          const SizedBox(height: 8),
          Wrap(children: [
            Text('Tính trên ', style: t.bodySmall?.copyWith(color: context.mutedColor)),
            MaskedText('${formatNumber(s.settledLots)} lô, ${_money(s.settledMoney)}', style: t.bodySmall?.copyWith(color: context.mutedColor)),
            Text(' khách gửi ở các ngày đã có kết quả.', style: t.bodySmall?.copyWith(color: context.mutedColor)),
            if (s.pendingLots > 0) ...[
              Text(' Chưa có kết quả: ', style: t.bodySmall?.copyWith(color: context.mutedColor)),
              MaskedText('${formatNumber(s.pendingLots)} lô, ${_money(s.pendingMoney)}', style: t.bodySmall?.copyWith(color: context.mutedColor)),
              Text(' (chưa tính).', style: t.bodySmall?.copyWith(color: context.mutedColor)),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.sub, this.color, this.highlight = false});
  final String label;
  final String value;
  final String sub;
  final Color? color;
  final bool highlight;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: highlight ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.bodySmall?.copyWith(color: context.mutedColor)),
        const SizedBox(height: 2),
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: MaskedText(value, style: TextStyle(fontSize: highlight ? 24 : 18, fontWeight: FontWeight.w800, color: color))),
        const SizedBox(height: 2),
        MaskedText(sub, style: t.bodySmall?.copyWith(color: context.mutedColor)),
      ]),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard(this.day);
  final DayView day;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ScoringController>();
    final masked = context.select<MaskStore, bool>((m) => m.masked);
    final label = dayLabel(day.date);
    final s = c.daySummary(day.date);
    final open = c.isOpen(day.date);
    final settled = s.settledLots > 0;
    final rem = s.remaining;
    final remColor = settled && !masked ? (rem > 0 ? context.okColor : (rem < 0 ? context.badColor : null)) : null;
    Widget fig(String name, Widget value) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
          ]),
        );
    const dash = Text('-');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => c.toggleDay(day.date),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(open ? Icons.expand_less : Icons.expand_more, size: 22),
                const SizedBox(width: 4),
                Text(label.date, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(child: Text(label.weekday, style: TextStyle(color: context.mutedColor, fontSize: 13), overflow: TextOverflow.ellipsis)),
                Chip(label: Text('${day.entries.length} dòng', style: const TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
              ]),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                fig('Số lô', MaskedText(formatNumber(s.sentLots), style: const TextStyle(fontWeight: FontWeight.w700))),
                fig('Tiền gửi', MaskedText(_money(s.sentMoney), style: const TextStyle(fontWeight: FontWeight.w700))),
                fig('Tiền trúng', settled ? MaskedText(_money(s.wonMoney), style: const TextStyle(fontWeight: FontWeight.w700)) : dash),
                fig('Còn lại', settled ? MaskedText(_signed(rem), style: TextStyle(fontWeight: FontWeight.w700, color: remColor)) : dash),
              ]),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
          child: Wrap(spacing: 8, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
            switch (day.lottery) {
              'yes' => _StateChip('Đã có kết quả xổ số', context.okColor),
              'partial' => _StateChip('Thiếu kết quả của một số đài', Brand.warning),
              'no' => _StateChip('Chưa có kết quả xổ số', Brand.warning),
              _ => _StateChip('Đang kiểm tra...', context.mutedColor),
            },
            if (day.lottery == 'partial' || day.lottery == 'no') AppButton(label: 'Nhập kết quả', variant: AppButtonVariant.ghost, onPressed: () => context.go(calcLocation('results', date: day.date))),
            AppButton(
              label: 'Xóa ngày này',
              variant: AppButtonVariant.danger,
              onPressed: () async {
                final n = await showDeleteDataDialog(context, api: context.read<ApiClient>(), customerName: c.selectedCustomer, dateFrom: c.dateFrom, dateTo: c.dateTo, singleDay: day.date);
                if (n != null) await c.afterDeleted(n);
              },
            ),
          ]),
        ),
        if (open) ...[
          const Divider(height: 1),
          for (final e in day.entries) _EntryRow(e),
        ],
      ]),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _EntryRow extends StatelessWidget {
  const _EntryRow(this.e);
  final Entry e;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<ScoringController>();
    final st = context.read<LotteryStations>();
    final masked = context.select<MaskStore, bool>((m) => m.masked);
    final status = c.status[e.id];
    final key = (e.betType == null || e.betType!.isEmpty) ? 'de' : e.betType!;
    Widget out;
    switch (status?.state) {
      case CalcState.computing:
        out = Text('Đang tính...', style: TextStyle(color: context.mutedColor));
      case CalcState.noLottery:
        out = Text('Chưa có kết quả', style: TextStyle(color: context.mutedColor));
      case CalcState.error:
        out = Text(status!.error ?? 'Lỗi', style: TextStyle(color: context.badColor, fontSize: 12));
      case CalcState.saved:
        out = MaskedText(formatNumber(status!.value ?? 0), style: TextStyle(fontWeight: FontWeight.w800, color: !masked && (status.value ?? 0) > 0 ? context.okColor : null));
      case null:
        out = (e.result ?? '').isNotEmpty ? MaskedText(formatNumber(toNumber(e.result))) : Text('Chưa có kết quả', style: TextStyle(color: context.mutedColor));
    }
    final won = status?.state == CalcState.saved && !masked;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          // Only: kind of bet, the region / station it is played on, won or not (the figures are in the cells below).
          _MiniChip(betTypeLabel(key)),
          _MiniChip(_areaName(st, e.station)),
          if (won) _MiniChip((status!.value ?? 0) > 0 ? 'Trúng' : 'Không trúng', color: (status.value ?? 0) > 0 ? context.okColor : null),
        ]),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 4, child: _Cell('Số', MaskedText(e.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)))),
          Expanded(flex: 3, child: _Cell('Điểm vào', MaskedText((e.score ?? '').isNotEmpty ? formatNumber(toNumber(e.score)) : '-'))),
          Expanded(flex: 3, child: _Cell('Điểm ra', out)),
        ]),
      ]),
    );
  }
}

/// "Miền Bắc" / "Miền Trung" / the name of one station, without the "(tất cả đài trong ngày)" note.
String _areaName(LotteryStations st, String? station) {
  if (station == null || station.isEmpty || station == 'mb') return 'Miền Bắc';
  return st.isRegionCode(station) ? st.regionOf(station).name : st.stationName(station);
}

class _Cell extends StatelessWidget {
  const _Cell(this.label, this.child);
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: context.mutedColor, fontSize: 11.5)),
        child,
      ]);
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.text, {this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.mutedColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: c.withValues(alpha: 0.5)), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: c)),
    );
  }
}
