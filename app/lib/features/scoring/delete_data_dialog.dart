import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_dialog.dart';
import 'date_field.dart';
import '../../core/widgets/app_button.dart';

/// "Xóa số liệu": delete saved entries now - one customer or everyone, an optional date range, optionally keeping the
/// newest N days. Shows how many entries would go (dry run, no password) and needs the account password.
///
/// POST /me/entries/bulk-delete { customerName, dateFrom, dateTo, keepDays, dryRun, password, allDataConfirmed }
///   -> { count } (dryRun) | { deleted }; 403 wrong password, 429 locked out.
/// Returns the number removed through Navigator.pop (null when cancelled).
Future<int?> showDeleteDataDialog(
  BuildContext context, {
  required ApiClient api,
  required String customerName,
  required String dateFrom,
  required String dateTo,
  String singleDay = '',
}) {
  return showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DeleteDataDialog(api: api, customerName: customerName, dateFrom: dateFrom, dateTo: dateTo, singleDay: singleDay),
  );
}

class DeleteDataDialog extends StatefulWidget {
  const DeleteDataDialog({super.key, required this.api, required this.customerName, required this.dateFrom, required this.dateTo, this.singleDay = ''});
  final ApiClient api;
  final String customerName;
  final String dateFrom;
  final String dateTo;
  final String singleDay;
  @override
  State<DeleteDataDialog> createState() => _DeleteDataDialogState();
}

class _DeleteDataDialogState extends State<DeleteDataDialog> {
  late String _scope = widget.customerName.isNotEmpty ? 'customer' : 'all';
  late String _from = widget.singleDay.isNotEmpty ? widget.singleDay : widget.dateFrom;
  late String _to = widget.singleDay.isNotEmpty ? widget.singleDay : widget.dateTo;
  final _keep = TextEditingController(text: '0');
  final _password = TextEditingController();
  bool _allConfirmed = false;
  int? _count;
  String _error = '';
  bool _busy = false;
  int _seq = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _refreshCount();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _keep.dispose();
    _password.dispose();
    super.dispose();
  }

  int get _keepDays => (int.tryParse(_keep.text.trim()) ?? 0).clamp(0, 3650);
  bool get _hasLimit => _scope == 'customer' || _from.isNotEmpty || _to.isNotEmpty || _keepDays > 0;

  Map<String, dynamic> _body([Map<String, dynamic> extra = const {}]) => {
        'customerName': _scope == 'customer' ? widget.customerName : null,
        'dateFrom': _from.isEmpty ? null : _from,
        'dateTo': _to.isEmpty ? null : _to,
        'keepDays': _keepDays,
        if (!_hasLimit) 'allDataConfirmed': true,
        ...extra,
      };

  void _refreshCount() {
    _timer?.cancel();
    setState(() => _count = null);
    _timer = Timer(const Duration(milliseconds: 250), () async {
      final mine = ++_seq;
      try {
        final r = await widget.api.post('/me/entries/bulk-delete', _body({'dryRun': true})) as Map;
        if (mounted && mine == _seq) setState(() => _count = (r['count'] as num?)?.toInt() ?? 0);
      } on ApiError catch (e) {
        if (mounted && mine == _seq) setState(() => _error = e.message);
      }
    });
  }

  void _changed(VoidCallback f) {
    setState(() {
      f();
      _error = '';
    });
    _refreshCount();
  }

  String get _scopeText {
    final who = _scope == 'customer' ? 'khách "${widget.customerName}"' : 'TẤT CẢ khách';
    final range = _from.isNotEmpty || _to.isNotEmpty
        ? (_from.isNotEmpty && _from == _to ? 'ngày ${viDate(_from)}' : 'ngày ${_from.isEmpty ? '...' : viDate(_from)} đến ${_to.isEmpty ? '...' : viDate(_to)}')
        : 'mọi ngày';
    return '$who, $range${_keepDays > 0 ? ', giữ lại $_keepDays ngày gần nhất' : ''}';
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!_hasLimit && !_allConfirmed) return setState(() => _error = 'Hãy tích ô xác nhận xoá toàn bộ số liệu');
    if (_password.text.isEmpty) return setState(() => _error = 'Nhập mật khẩu đăng nhập để xác nhận');
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      final r = await widget.api.post('/me/entries/bulk-delete', _body({'password': _password.text})) as Map;
      if (mounted) Navigator.pop(context, (r['deleted'] as num?)?.toInt() ?? 0);
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final single = widget.singleDay;
    return AppDialog(
      title: 'Xóa số liệu',
      closeEnabled: !_busy,
      body: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Chọn phạm vi cần xóa. Số liệu đã xóa không thể khôi phục.', style: TextStyle(color: context.mutedColor, fontSize: 13)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _scope,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Phạm vi'),
          items: [
            if (widget.customerName.isNotEmpty) DropdownMenuItem(value: 'customer', child: Text('Khách đang chọn: ${widget.customerName}', overflow: TextOverflow.ellipsis)),
            const DropdownMenuItem(value: 'all', child: Text('Tất cả khách hàng')),
          ],
          onChanged: (v) => _changed(() => _scope = v ?? 'all'),
        ),
        if (single.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Chỉ ngày này'), selected: _from == single && _to == single, onSelected: (_) => _changed(() {
              _from = single;
              _to = single;
            })),
            ChoiceChip(label: const Text('Khoảng đang xem'), selected: !(_from == single && _to == single) && _from == widget.dateFrom && _to == widget.dateTo, onSelected: (_) => _changed(() {
              _from = widget.dateFrom;
              _to = widget.dateTo;
            })),
          ]),
        ],
        const SizedBox(height: 12),
        DateField(label: 'Từ ngày', value: _from, clearable: true, onChanged: (v) => _changed(() => _from = v)),
        const SizedBox(height: 10),
        DateField(label: 'Đến ngày', value: _to, clearable: true, onChanged: (v) => _changed(() => _to = v)),
        const SizedBox(height: 12),
        TextField(
          controller: _keep,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Giữ lại N ngày gần nhất (tuỳ chọn)'),
          onChanged: (_) => _changed(() {}),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: (_count == 0 ? context.mutedColor : context.badColor).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: _count == null
              ? const Text('Đang đếm số liệu...')
              : Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Sẽ xóa '),
                  TextSpan(text: formatNumber(_count!), style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: ' số liệu của $_scopeText. Không thể khôi phục.'),
                ])),
        ),
        if (!_hasLimit)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _allConfirmed,
            onChanged: (v) => setState(() => _allConfirmed = v ?? false),
            title: const Text('Tôi hiểu: xóa TOÀN BỘ số liệu của tất cả khách hàng', style: TextStyle(fontSize: 13)),
          ),
        const SizedBox(height: 12),
        TextField(controller: _password, obscureText: true, enabled: !_busy, decoration: const InputDecoration(labelText: 'Mật khẩu đăng nhập')),
        if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error, style: TextStyle(color: context.badColor))),
      ]),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: _busy ? null : () => Navigator.pop(context)),
        AppButton(label: 'Xóa', variant: AppButtonVariant.danger, loading: _busy, onPressed: _busy || _count == 0 ? null : _submit),
      ],
    );
  }
}
