import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/mask_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/masked_text.dart';
import 'account_widgets.dart';
import 'stats_chart.dart';
import 'stats_logic.dart';
import '../../core/widgets/app_button.dart';

/// Thống kê: customers, plays, points in/out, profit (all masked by "Ẩn số liệu") and a bar chart by day/month/year.
class AccountStatsTab extends StatefulWidget {
  const AccountStatsTab({super.key});
  @override
  State<AccountStatsTab> createState() => _AccountStatsTabState();
}

class _AccountStatsTabState extends State<AccountStatsTab> {
  bool _loading = true;
  String? _error;
  List<String> _roster = const [];
  List<StatEntry> _entries = const [];
  StatUnit _unit = StatUnit.day;
  StatMetric _metric = StatMetric.profit;
  int _selected = -1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cust = await api.get('/me/customers');
      final names = [for (final c in (cust is Map ? cust['customers'] as List? : null) ?? const []) (c as Map)['name'] as String];
      final all = <String, StatEntry>{};
      var offset = 0;
      for (;;) {
        final page = await api.get('/me/entries?limit=1000&offset=$offset') as Map;
        final list = (page['entries'] as List?) ?? const [];
        for (final e in list) {
          final m = (e as Map).cast<String, dynamic>();
          all[(m['id'] ?? '${all.length}').toString()] = StatEntry.fromJson(m);
        }
        offset += list.length;
        if (page['hasMore'] != true || list.isEmpty) break;
      }
      if (!mounted) return;
      setState(() {
        _roster = names;
        _entries = all.values.toList();
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Không tải được thống kê');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Column(children: [NoticeBox(_error!), AppButton(label: 'Thử lại', variant: AppButtonVariant.secondary, onPressed: _load)]);
    }
    final totals = computeTotals(_roster, _entries);
    final now = DateTime.now().toUtc().add(const Duration(hours: 7)); // Vietnam date, like the rest of the app
    final series = buildSeries(_entries, _unit, _metric, now);
    final masked = context.select<MaskStore, bool>((m) => m.masked);
    final sel = _selected >= 0 && _selected < series.length ? series[_selected] : null;
    final ok = context.okColor, bad = context.badColor;
    Widget stat(String label, String value, {Color? color}) => Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: TextStyle(color: context.mutedColor, fontSize: 13)),
              const SizedBox(height: 4),
              MaskedText(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Align(alignment: Alignment.centerLeft, child: MaskBar()),
      const SizedBox(height: 8),
      Text('Tổng hợp trên toàn bộ số liệu của bạn (điểm vào/ra để trống được tính là 0).', style: TextStyle(color: context.mutedColor, fontSize: 13)),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: stat('Số lượng khách hàng', formatNumber(totals.customers))),
        const SizedBox(width: 10),
        Expanded(child: stat('Số lượt chơi', formatNumber(totals.plays))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: stat('Tổng điểm vào', formatNumber(totals.vao), color: ok)),
        const SizedBox(width: 10),
        Expanded(child: stat('Tổng điểm ra', formatNumber(totals.ra), color: bad)),
      ]),
      const SizedBox(height: 10),
      stat('Lợi nhuận (vào − ra)', formatNumber(totals.profit), color: totals.profit >= 0 ? ok : bad),
      const SizedBox(height: 14),
      Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final u in StatUnit.values) _Pill(statUnitLabels[u]!, _unit == u, () => setState(() { _unit = u; _selected = -1; })),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final m in StatMetric.values) _Pill(statMetricLabels[m]!, _metric == m, () => setState(() { _metric = m; _selected = -1; })),
            ]),
            const SizedBox(height: 8),
            Text(
              [
                _unit == StatUnit.day ? '30 ngày gần nhất' : _unit == StatUnit.month ? '12 tháng gần nhất' : '5 năm gần nhất',
                if (sel != null && !masked) '${sel.full}: ${formatNumber(sel.value)}',
              ].join(' · '),
              style: TextStyle(color: context.mutedColor, fontSize: 12),
            ),
            const SizedBox(height: 6),
            if (masked)
              Padding(padding: const EdgeInsets.symmetric(vertical: 36), child: Center(child: Text('Biểu đồ đang ẩn. Bấm Hiện số liệu để xem.', style: TextStyle(color: context.mutedColor))))
            else
              StatsBarChart(points: series, metric: _metric, positive: ok, negative: bad, selected: _selected, onSelect: (i) => setState(() => _selected = i == _selected ? -1 : i)),
          ]),
        ),
      ),
    ]);
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.on, this.onTap);
  final String label;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(99),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(color: on ? cs.primary : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(99), border: Border.all(color: on ? cs.primary : cs.outlineVariant)),
        child: Text(label, style: TextStyle(fontSize: 13, color: on ? cs.onPrimary : cs.onSurface)),
      ),
    );
  }
}
