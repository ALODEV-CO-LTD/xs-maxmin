import 'package:flutter/material.dart';
import 'scoring_data.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/bet_types.dart';
import '../../core/format.dart';
import '../../core/lottery_stations.dart';
import '../../core/mask_store.dart';
import '../../core/scoring_config.dart';
import '../../core/theme.dart';
import '../calc/calc_screen.dart';
import '../../core/widgets/masked_text.dart';
import 'date_field.dart';
import 'delete_data_dialog.dart';
import 'deletion_schedules_page.dart';
import 'entry_model.dart';
import 'scoring_controller.dart';
import 'scoring_days.dart';
import 'scoring_logic.dart';

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

  @override
  void initState() {
    super.initState();
    _c = ScoringController(context.read<ApiClient>(), context.read<LotteryStations>());
    _c.load();
  }

  @override
  void dispose() {
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
            TextButton.icon(onPressed: c.load, icon: const Icon(Icons.refresh), label: const Text('Thử lại')),
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
                  : (c.hasEntriesForCustomer ? 'Không có số liệu nào trong khoảng ngày này. Chọn "Tất cả" để xem lịch sử.' : 'Khách hàng này chưa có số liệu nào.'),
            )
          else ...[
            for (final d in c.visibleDays) _DayCard(d),
            if (c.hiddenDayCount > 0)
              OutlinedButton(onPressed: c.showMoreDays, child: Text('Xem thêm ngày cũ (${c.hiddenDayCount < ScoringController.pageDays ? c.hiddenDayCount : ScoringController.pageDays} / còn ${c.hiddenDayCount} ngày)')),
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
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const MaskBar(),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Xóa số liệu'),
              onPressed: () async {
                final n = await showDeleteDataDialog(context, api: api, customerName: c.selectedCustomer, dateFrom: c.dateFrom, dateTo: c.dateTo);
                if (n != null) await c.afterDeleted(n);
              },
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              icon: const Icon(Icons.event_repeat, size: 18),
              label: const Text('Đặt lịch xóa'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => DeletionSchedulesPage(api: api, customerName: c.selectedCustomer))),
            ),
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
          DropdownButtonFormField<String>(
            key: ValueKey('cust${names.length}'),
            initialValue: customer,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Khách hàng'),
            items: [const DropdownMenuItem(value: '', child: Text('-- Chọn khách hàng --')), for (final n in names) DropdownMenuItem(value: n, child: Text(n, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => c.selectCustomer(v ?? ''),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: c.regionFilter,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Xổ số'),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('Tất cả')),
                  DropdownMenuItem(value: 'mb', child: Text('Miền Bắc')),
                  DropdownMenuItem(value: 'mt', child: Text('Miền Trung')),
                  DropdownMenuItem(value: 'mn', child: Text('Miền Nam')),
                ],
                onChanged: (v) => c.setRegionFilter(v ?? 'all'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('preset${c.preset}'),
                initialValue: c.preset,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Thời gian'),
                items: [for (final p in timePresets) DropdownMenuItem(value: p.key, child: Text(p.label))],
                onChanged: (v) => c.setPreset(v ?? 'all'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DateField(label: 'Từ ngày', value: c.dateFrom, clearable: true, onChanged: c.setFrom)),
            const SizedBox(width: 10),
            Expanded(child: DateField(label: 'Đến ngày', value: c.dateTo, clearable: true, onChanged: c.setTo)),
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: c.onlyMissing,
            onChanged: (v) => c.setOnlyMissing(v ?? false),
            title: const Text('Chỉ hiện số liệu chưa có kết quả xổ số', style: TextStyle(fontSize: 13.5)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
              onPressed: c.autoCalcRunning > 0 || c.selectedCustomer.isEmpty ? null : c.recalc,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(c.autoCalcRunning > 0 ? 'Đang tính...' : 'Tính lại'),
            ),
          ),
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
            Expanded(child: _Tile(label: 'Tiền khách gửi', value: _money(s.sentMoney), sub: '${formatNumber(s.sentLots)} lô${s.sentPoints > 0 ? ' · ${formatNumber(s.sentPoints)} điểm' : ''}')),
            const SizedBox(width: 8),
            Expanded(child: _Tile(label: 'Lô trúng', value: _money(s.wonMoney), sub: '${formatNumber(s.wonLots)} lô trúng${s.wonHits != s.wonLots ? ' · ${formatNumber(s.wonHits)} lần' : ''}')),
          ]),
          const SizedBox(height: 8),
          _Tile(
            label: 'Còn lại = gửi − trúng',
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
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Chi tiết tiền gửi theo loại đánh', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              children: [
                if (s.byType.isEmpty)
                  const SizedBox.shrink()
                else
                  for (final tt in s.byType)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${betTypeLabel(tt.key)} · ${formatNumber(tt.lots)} lô'),
                      subtitle: MaskedText(tt.unit == 'point' ? '${formatNumber(tt.amount)} điểm × ${formatNumber(tt.pointValue)} đ' : 'tính theo tiền'),
                      trailing: MaskedText(_money(tt.money), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
              ],
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text('Các lô trúng (${s.wonLots})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              children: [
                if (s.won.isEmpty) Align(alignment: Alignment.centerLeft, child: Text('Chưa có lô nào trúng.', style: TextStyle(color: context.mutedColor))),
                for (final w in s.won.take(200)) _WonRow(w),
              ],
            ),
          ),
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

class _WonRow extends StatelessWidget {
  const _WonRow(this.w);
  final WonItem w;
  @override
  Widget build(BuildContext context) {
    final st = context.read<LotteryStations>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        SizedBox(width: 52, child: MaskedText(w.number, style: const TextStyle(fontWeight: FontWeight.w800))),
        Expanded(
          child: Text(
            '${betTypeLabel(w.type)} · ${viDate(w.date)}${w.station != 'mb' ? ' · ${st.stationName(w.station)}' : ''}${w.hits > 1 ? ' · trúng ${w.hits} lần' : ''}',
            style: TextStyle(color: context.mutedColor, fontSize: 12.5),
          ),
        ),
        MaskedText(_money(w.money), style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ---- day cards --------------------------------------------------------------------------------------------------

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
            if (day.lottery == 'partial' || day.lottery == 'no') TextButton(onPressed: () => context.go(calcLocation('results', date: day.date)), child: const Text('Nhập kết quả')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: context.badColor),
              onPressed: () async {
                final n = await showDeleteDataDialog(context, api: context.read<ApiClient>(), customerName: c.selectedCustomer, dateFrom: c.dateFrom, dateTo: c.dateTo, singleDay: day.date);
                if (n != null) await c.afterDeleted(n);
              },
              child: const Text('Xóa ngày này'),
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
    final cfg = c.configFor(e.betType, e.station);
    final rate = cfg['rate'];
    final digits = (cfg['digits'] as num?) ?? 2;
    // "Giá tiền → giá trúng" of the row the entry is scored with (older rows: "× tỉ lệ").
    final rateText = hasMoneyModel(cfg) ? '${formatNumber(numOf(cfg['price']))} → ${formatNumber(numOf(cfg['payout']))} đ/điểm' : '× ${rate is num ? numToString(rate) : '?'}';
    final fixedKind = isTableKind(cfg['kind']);
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
          _MiniChip('${betTypeLabel(key)} · $rateText'),
          if (!fixedKind) _MiniChip('${digits.toInt()} số cuối'),
          if (e.station != null && e.station!.isNotEmpty && e.station != 'mb') _MiniChip(st.stationLabel(e.station)),
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
