import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/lottery_stations.dart';
import '../../core/widgets/app_dialog.dart';
import '../entries/dialogs.dart';
import 'customer_model.dart';
import '../../core/widgets/app_button.dart';

const offlineWriteMessage = 'Đang offline: thêm/xoá khách hàng cần có mạng, vui lòng thử lại khi kết nối lại.';

/// "Thêm khách hàng": tên, SĐT, đài mặc định. The scoring config is set afterwards, per customer.
/// Resolves the created [Customer], or null when cancelled.
Future<Customer?> showAddCustomerDialog(BuildContext context) {
  final api = context.read<ApiClient>();
  final stations = context.read<LotteryStations>();
  stations.load(api);
  return showDialog<Customer>(context: context, builder: (_) => _AddCustomerDialog(api: api, stations: stations));
}

class _AddCustomerDialog extends StatefulWidget {
  const _AddCustomerDialog({required this.api, required this.stations});
  final ApiClient api;
  final LotteryStations stations;
  @override
  State<_AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends State<_AddCustomerDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String _station = 'mb';
  bool _busy = false;
  String _error = '';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final res = Map<String, dynamic>.from(await widget.api.post('/me/customers', {'name': name, 'phone': _phone.text.trim()}) as Map);
      var created = Customer.fromJson(res);
      if (_station != 'mb') {
        try {
          final patched = await widget.api.patch('/me/customers/${created.id}', {'defaultStation': _station}) as Map;
          created.defaultStation = patched['defaultStation'] as String?;
        } on ApiError catch (e) {
          if (mounted) {
            setState(() {
              _error = 'Đã tạo khách nhưng chưa lưu được đài mặc định: ${e.message}.';
              _busy = false;
            });
          }
          // the customer exists now: close once the user has read the message
          await Future<void>.delayed(const Duration(seconds: 2));
          if (mounted) Navigator.pop(context, created);
          return;
        }
      }
      if (mounted) Navigator.pop(context, created);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.status == 0 ? offlineWriteMessage : e.message;
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = context.watch<LotteryStations>().allStationOptions();
    return AppDialog(
      title: 'Thêm khách hàng',
      closeEnabled: !_busy,
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _name, autofocus: true, enabled: !_busy, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Tên khách hàng')),
          const SizedBox(height: 12),
          TextField(controller: _phone, enabled: !_busy, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Số điện thoại', hintText: 'Không bắt buộc')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: options.any((o) => o.value == _station) ? _station : 'mb',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Đài xổ số mặc định khi nhập số'),
            items: [for (final o in options) DropdownMenuItem(value: o.value, child: Text(o.label.trim(), overflow: TextOverflow.ellipsis))],
            onChanged: _busy ? null : (v) => setState(() => _station = v ?? 'mb'),
          ),
          const SizedBox(height: 8),
          const Text('Cấu hình tính điểm của khách đặt sau, ở nút "Cấu hình tính điểm" trong danh sách.', style: TextStyle(fontSize: 12.5)),
          if (_error.isNotEmpty) ...[const SizedBox(height: 10), InfoBox(_error)],
      ]),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: _busy ? null : () => Navigator.pop(context)),
        AppButton(label: 'Thêm khách hàng', variant: AppButtonVariant.primary, loading: _busy, onPressed: _busy ? null : _submit),
      ],
    );
  }
}
