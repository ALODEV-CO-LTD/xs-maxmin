import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/admin_session.dart';
import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../users/admin_users_widgets.dart';
import 'admin_stats_chart.dart';
import 'admin_stats_logic.dart';

/// Admin - Thống kê: subscriber tiles, revenue / new-user charts and the per-package table. Body only.
class AdminStatsScreen extends StatelessWidget {
  const AdminStatsScreen({super.key});
  @override
  Widget build(BuildContext context) => StatsBody(api: context.read<ApiClient>(), allowed: context.watch<AdminSession>().can('stats.view'));
}

class StatsBody extends StatefulWidget {
  const StatsBody({super.key, required this.api, this.allowed = true});
  final ApiClient api;
  final bool allowed;
  @override
  State<StatsBody> createState() => _StatsBodyState();
}

class _StatsBodyState extends State<StatsBody> {
  AdminStats? _stats;
  Map<String, String> _labels = {};
  bool _loading = true;
  String? _error;
  String _range = 'day';

  @override
  void initState() {
    super.initState();
    _load();
    _loadLabels();
  }

  Future<void> _load() async {
    if (!widget.allowed) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await widget.api.get('/admin/stats?range=$_range') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _stats = AdminStats.fromJson(res);
        _error = null;
      });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Package names come from the admin-edited catalog; failure only means codes are shown raw.
  Future<void> _loadLabels() async {
    try {
      final res = await widget.api.get('/me/packages?all=1') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _labels = {for (final p in (res['packages'] as List? ?? const [])) if (p is Map) '${p['type']}': '${p['label']}'});
    } on ApiError {
      // keep codes
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.allowed) return const EmptyState('Tài khoản của bạn chưa được cấp quyền xem thống kê.');
    final s = _stats;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null) AdminBanner(_error!),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (s != null) ..._content(context, s)
        else if (_error == null)
          const EmptyState('Chưa có dữ liệu'),
      ]),
    );
  }

  List<Widget> _content(BuildContext context, AdminStats s) {
    return [
      Row(children: [
        Expanded(child: _tile(context, s.total, 'Tổng khách hàng', null)),
        const SizedBox(width: 8),
        Expanded(child: _tile(context, s.active, 'Đang hoạt động', context.okColor)),
        const SizedBox(width: 8),
        Expanded(child: _tile(context, s.expired, 'Đã hết hạn', Brand.warning)),
      ]),
      const SizedBox(height: 20),
      Text(s.canRevenue ? 'Thu nhập và người dùng mới' : 'Người dùng mới', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, children: [
        for (final r in statsRanges)
          ChoiceChip(
            label: Text(r.label),
            selected: _range == r.key,
            onSelected: (_) {
              setState(() => _range = r.key);
              _load();
            },
          ),
      ]),
      const SizedBox(height: 4),
      Text('${statsRangeSpans[_range]}', style: TextStyle(fontSize: 12, color: context.mutedColor)),
      const SizedBox(height: 8),
      if (s.canRevenue) ...[
        AdminSeriesChart(points: [for (final p in s.series) ChartPoint(p.date, p.revenue)], line: false, color: Theme.of(context).colorScheme.primary, label: 'Thu nhập', money: true, unit: _range),
        const SizedBox(height: 12),
      ],
      AdminSeriesChart(points: [for (final p in s.series) ChartPoint(p.date, p.newUsers)], line: true, color: context.okColor, label: 'Người dùng mới', unit: _range),
      const SizedBox(height: 20),
      const Text('Theo gói dịch vụ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Card(
        child: s.byPackage.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Text('Chưa có dữ liệu'))
            : Column(children: [
                for (final e in s.byPackage.entries)
                  ListTile(dense: true, title: Text(packageLabelOf(e.key, _labels)), trailing: Text(formatNumber(e.value), style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
      ),
    ];
  }

  Widget _tile(BuildContext context, int value, String label, Color? color) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(formatNumber(value), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color))),
            const SizedBox(height: 4),
            Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.mutedColor)),
          ]),
        ),
      );
}
