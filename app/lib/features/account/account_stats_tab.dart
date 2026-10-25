import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/mask_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/masked_text.dart';
import 'account_data_tab.dart' show DeleteDataButton;
import 'account_widgets.dart';
import 'stats_chart.dart';
import '../../core/lottery_stations.dart';
import 'stats_logic.dart';
import 'stats_money.dart';
import '../../core/widgets/app_button.dart';

/// Thống kê: one card with metric (tiền khách gửi / tiền khách trúng / lợi nhuận, in đồng) + period (ngày/tuần/tháng/năm) selectors, period total, bar chart and all-time figures (all masked by "Ẩn số liệu").
class AccountStatsTab extends StatefulWidget {
  const AccountStatsTab({super.key});
  @override
  State<AccountStatsTab> createState() => _AccountStatsTabState();
}

class _AccountStatsTabState extends State<AccountStatsTab> {
  bool _loading = true;
  String? _error;
  MoneyStats? _money;
  StatUnit _unit = StatUnit.day;
  StatMetric _metric = StatMetric.profit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = context.read<ApiClient>();
    final stations = context.read<LotteryStations>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await loadMoneyStats(api, stations);
      if (mounted) setState(() => _money = m);
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
    final money = _money!;
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 7),
    ); // Vietnam date, like the rest of the app
    final series = buildMoneySeries(money.byDate, _unit, _metric, now);
    final masked = context.select<MaskStore, bool>((m) => m.masked);
    final ok = context.okColor, bad = context.badColor;
    final cs = Theme.of(context).colorScheme;
    // The figure is the CURRENT period (today / this week / this month / this year) and is compared with the one before it;
    // the chart below still shows the last periods so the trend is visible. The series ends at the current period.
    final sum = series.isEmpty ? 0.0 : series.last.value;
    final prevSum = series.length < 2 ? 0.0 : series[series.length - 2].value;
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
    final current = statCurrentLabels[_unit]!;
    final previous = statPreviousLabels[_unit]!;
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
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: seg),
        ],
      ),
    );
    final segStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 28)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 8),
      ),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
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
                const SizedBox(height: 6),
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
                  '${statMetricLabels[_metric]} · $current',
                  style: TextStyle(color: context.mutedColor, fontSize: 12),
                ),
                const SizedBox(height: 2),
                MaskedText(
                  '${signed(sum)} đ',
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
                        ? 'Chưa có số liệu $previous'
                        : '${delta >= 0 ? '▲' : '▼'} ${delta >= 0 ? '+' : '−'}${formatNumber(delta.abs())} đ (${pct! >= 0 ? '+' : '−'}${pct.abs().toStringAsFixed(1).replaceAll('.', ',')}%) so với $previous',
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
                Text('Biểu đồ $span gần nhất', style: TextStyle(color: context.mutedColor, fontSize: 12)),
                const SizedBox(height: 4),
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
                        formatNumber(money.customerNames.length),
                      ),
                      fixed('Số lượt chơi', formatNumber(money.plays)),
                      fixed('Tổng tiền khách gửi', '${formatNumber(money.sent)} đ'),
                      fixed('Tổng tiền khách trúng', '${formatNumber(money.won)} đ'),
                      fixed(
                        'Lợi nhuận toàn bộ',
                        '${signedAll(money.profit)} đ',
                        color: money.profit > 0
                            ? ok
                            : money.profit < 0
                            ? bad
                            : null,
                      ),
                      if (money.pendingLots > 0)
                        fixed(
                          'Chưa có kết quả xổ số (chưa tính lợi nhuận)',
                          '${formatNumber(money.pendingLots)} lô · ${formatNumber(money.pending)} đ',
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                DeleteDataButton(onDeleted: _load),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String signedAll(double v) => v > 0 ? '+${formatNumber(v)}' : formatNumber(v);
}
