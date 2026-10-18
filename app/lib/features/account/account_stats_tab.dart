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

/// Thống kê: one card with metric (vào/ra/lợi nhuận) + period (ngày/tuần/tháng/năm) selectors, period total, bar chart and all-time figures (all masked by "Ẩn số liệu").
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
      final names = [
        for (final c
            in (cust is Map ? cust['customers'] as List? : null) ?? const [])
          (c as Map)['name'] as String,
      ];
      final all = <String, StatEntry>{};
      var offset = 0;
      for (;;) {
        final page =
            await api.get('/me/entries?limit=1000&offset=$offset') as Map;
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
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Column(
        children: [
          NoticeBox(_error!),
          AppButton(
            label: 'Thử lại',
            variant: AppButtonVariant.secondary,
            onPressed: _load,
          ),
        ],
      );
    }
    final totals = computeTotals(_roster, _entries);
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 7),
    ); // Vietnam date, like the rest of the app
    final series = buildSeries(_entries, _unit, _metric, now);
    final masked = context.select<MaskStore, bool>((m) => m.masked);
    final ok = context.okColor, bad = context.badColor;
    final cs = Theme.of(context).colorScheme;
    final sum = sumOf(series);
    final prevSum = sumOf(
      buildSeries(_entries, _unit, _metric, previousAnchor(_unit, now)),
    );
    final pct = percentChange(sum, prevSum);
    final isProfit = _metric == StatMetric.profit;
    Color? signColor(double v) => isProfit
        ? (v > 0
              ? ok
              : v < 0
              ? bad
              : null)
        : null;
    String signed(double v) =>
        isProfit && v > 0 ? '+${formatNumber(v)}' : formatNumber(v);
    final span = statSpanLabels[_unit]!;
    final delta = sum - prevSum;

    Widget fixed(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.mutedColor, fontSize: 13),
            ),
          ),
          MaskedText(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
    Widget group(String label, Widget seg) => Semantics(
      container: true,
      label: 'Nhóm $label',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(color: context.mutedColor, fontSize: 12),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: seg),
        ],
      ),
    );
    final segStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
      tapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                group(
                  'Chỉ số',
                  SegmentedButton<StatMetric>(
                    style: segStyle,
                    showSelectedIcon: false,
                    segments: [
                      for (final m in StatMetric.values)
                        ButtonSegment(
                          value: m,
                          label: Text(statMetricLabels[m]!),
                        ),
                    ],
                    selected: {_metric},
                    onSelectionChanged: (v) =>
                        setState(() => _metric = v.first),
                  ),
                ),
                const SizedBox(height: 10),
                group(
                  'Kỳ',
                  SegmentedButton<StatUnit>(
                    style: segStyle,
                    showSelectedIcon: false,
                    segments: [
                      for (final u in StatUnit.values)
                        ButtonSegment(
                          value: u,
                          label: Text(statUnitLabels[u]!),
                        ),
                    ],
                    selected: {_unit},
                    onSelectionChanged: (v) => setState(() => _unit = v.first),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${statMetricLabels[_metric]} · $span gần nhất',
                  style: TextStyle(color: context.mutedColor, fontSize: 12),
                ),
                const SizedBox(height: 2),
                MaskedText(
                  signed(sum),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: signColor(sum),
                  ),
                ),
                const SizedBox(height: 2),
                if (prevSum != 0 || sum != 0)
                  MaskedText(
                    prevSum == 0
                        ? 'Kỳ trước ($span liền trước): chưa có số liệu'
                        : '${delta >= 0 ? '▲' : '▼'} ${delta >= 0 ? '+' : '−'}${formatNumber(delta.abs())} (${pct! >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(1).replaceAll('.', ',')}%) so với $span liền trước',
                    style: TextStyle(
                      fontSize: 12,
                      color: prevSum == 0
                          ? context.mutedColor
                          : (isProfit
                                ? (delta > 0
                                      ? ok
                                      : delta < 0
                                      ? bad
                                      : null)
                                : context.mutedColor),
                    ),
                  ),
                const SizedBox(height: 10),
                if (masked)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Center(
                      child: Text(
                        'Biểu đồ đang ẩn. Bấm Hiện số liệu để xem.',
                        style: TextStyle(color: context.mutedColor),
                      ),
                    ),
                  )
                else
                  StatsBarChart(
                    points: series,
                    metric: _metric,
                    primary: cs.primary,
                    positive: ok,
                    negative: bad,
                  ),
                const Divider(height: 24),
                Semantics(
                  container: true,
                  label: 'Chỉ số toàn bộ',
                  child: Column(
                    children: [
                      fixed(
                        'Số lượng khách hàng',
                        formatNumber(totals.customers),
                      ),
                      fixed('Số lượt chơi', formatNumber(totals.plays)),
                      fixed('Tổng điểm vào', formatNumber(totals.vao)),
                      fixed('Tổng điểm ra', formatNumber(totals.ra)),
                      fixed(
                        'Lợi nhuận toàn bộ',
                        signedAll(totals.profit),
                        color: totals.profit > 0
                            ? ok
                            : totals.profit < 0
                            ? bad
                            : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String signedAll(double v) => v > 0 ? '+${formatNumber(v)}' : formatNumber(v);
}
