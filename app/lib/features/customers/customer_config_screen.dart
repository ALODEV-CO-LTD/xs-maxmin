import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
import '../../core/scoring_config_bus.dart';
import '../../core/theme.dart';
import 'customer_model.dart';
import 'customers_controller.dart';
import 'scoring_config_editor.dart';
import '../../core/widgets/app_dropdown.dart';

/// The customer's own region: decides how "Đầu" is scored on a Miền Bắc result (Bắc 1 lô = 1 điểm, Nam/Trung ×4 giải bảy).
const homeRegionOptions = {'': 'Chưa chọn (tính như khách Bắc)', 'mb': 'Khách Miền Bắc', 'mn': 'Khách Miền Nam / Miền Trung'};

/// One customer: the default đài used by Nhập số, and the customer's own "Cấu hình tính điểm".
class CustomerConfigScreen extends StatefulWidget {
  const CustomerConfigScreen({super.key, required this.controller, required this.customer});
  final CustomersController controller;
  final Customer customer;
  @override
  State<CustomerConfigScreen> createState() => _CustomerConfigScreenState();
}

class _CustomerConfigScreenState extends State<CustomerConfigScreen> {
  String _msg = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    context.read<LotteryStations>().load(context.read<ApiClient>());
  }

  Future<void> _saveStation(String code) async {
    setState(() {
      _saving = true;
      _msg = '';
    });
    final err = await widget.controller.saveStation(widget.customer, code);
    if (mounted) {
      setState(() {
        _saving = false;
        _msg = err.isEmpty ? 'Đã lưu đài mặc định' : err;
      });
    }
  }

  Future<void> _saveHomeRegion(String? region) async {
    setState(() {
      _saving = true;
      _msg = '';
    });
    final err = await widget.controller.saveHomeRegion(widget.customer, region);
    if (mounted) {
      setState(() {
        _saving = false;
        _msg = err.isEmpty ? 'Đã lưu miền của khách' : err;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cu = widget.customer;
    final options = context.watch<LotteryStations>().allStationOptions();
    final cur = options.any((o) => o.value == cu.stationCode) ? cu.stationCode : 'mb';
    return Scaffold(
      appBar: AppBar(title: Text(cu.name)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          AppDropdown<String>(
            key: ValueKey('station-$cur-${options.length}'),
            initialValue: cur,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Đài xổ số mặc định khi nhập số cho khách này'),
            items: [for (final o in options) DropdownMenuItem(value: o.value, child: Text(o.label.trim(), overflow: TextOverflow.ellipsis))],
            onChanged: _saving ? null : (v) => v == null ? null : _saveStation(v),
          ),
          const SizedBox(height: 14),
          AppDropdown<String>(
            key: ValueKey('region-${cu.homeRegion}'),
            initialValue: cu.homeRegion ?? '',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Khách thuộc miền nào (để tính Đầu ở đài Miền Bắc)'),
            items: [for (final o in homeRegionOptions.entries) DropdownMenuItem(value: o.key, child: Text(o.value, overflow: TextOverflow.ellipsis))],
            onChanged: _saving ? null : (v) => _saveHomeRegion(v == null || v.isEmpty ? null : v),
          ),
          if (_msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg, style: TextStyle(fontSize: 13, color: context.mutedColor))),
          const Divider(height: 32),
          Text('Cấu hình tính điểm của khách này${cu.scoringRates != null ? ' (có cấu hình riêng)' : ''}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ScoringConfigEditor(
            customer: cu,
            accountRates: widget.controller.accountRates,
            onSaved: (m) => widget.controller.customerConfigSaved(cu, m),
          ),
        ]),
      ),
    );
  }
}

/// Cấu hình: the account-wide default scoring config (GET/PUT /me/scoring-settings), a tab of the bottom bar.
class DefaultConfigScreen extends StatelessWidget {
  const DefaultConfigScreen({super.key, this.onSaved});
  final void Function(RatesMap saved)? onSaved;
  @override
  Widget build(BuildContext context) {
    final bus = Provider.of<ScoringConfigBus?>(context, listen: false);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Cấu hình tính điểm mặc định')),
      // The region bar and Sửa / Lưu stay at the top; only the table under them scrolls.
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: ScoringConfigEditor(
            scrollable: true,
            onSaved: (m) {
              if (m == null) return;
              bus?.publish(m);
              onSaved?.call(m);
            },
          ),
        ),
      ),
    );
  }
}
