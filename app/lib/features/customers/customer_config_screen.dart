import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/lottery_stations.dart';
import '../../core/scoring_config.dart';
import '../../core/theme.dart';
import 'customer_model.dart';
import 'customers_controller.dart';
import 'scoring_config_editor.dart';

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

  @override
  Widget build(BuildContext context) {
    final cu = widget.customer;
    final options = context.watch<LotteryStations>().allStationOptions();
    final cur = options.any((o) => o.value == cu.stationCode) ? cu.stationCode : 'mb';
    return Scaffold(
      appBar: AppBar(title: Text(cu.name)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<String>(
            key: ValueKey('station-$cur-${options.length}'),
            initialValue: cur,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Đài xổ số mặc định khi nhập số cho khách này'),
            items: [for (final o in options) DropdownMenuItem(value: o.value, child: Text(o.label.trim(), overflow: TextOverflow.ellipsis))],
            onChanged: _saving ? null : (v) => v == null ? null : _saveStation(v),
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

/// The account-wide default config (GET/PUT /me/scoring-settings).
class DefaultConfigScreen extends StatelessWidget {
  const DefaultConfigScreen({super.key, this.onSaved});
  final void Function(RatesMap saved)? onSaved;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình tính điểm mặc định')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          ScoringConfigEditor(onSaved: (m) {
            if (m != null) onSaved?.call(m);
          }),
        ]),
      ),
    );
  }
}
