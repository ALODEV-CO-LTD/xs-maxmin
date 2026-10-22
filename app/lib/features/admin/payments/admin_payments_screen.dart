import 'dart:async';
import '../../../core/widgets/svg_icon.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/format.dart';
import '../../../core/theme.dart';
import '../settings/settings_ui.dart';
import 'payments_logic.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_dropdown.dart';

/// Admin - Thanh toán & gia hạn (right payments.manage). Body only (the admin shell draws the AppBar and drawer).
class AdminPaymentsScreen extends StatefulWidget {
  const AdminPaymentsScreen({super.key});
  @override
  State<AdminPaymentsScreen> createState() => _AdminPaymentsScreenState();
}

class _AdminPaymentsScreenState extends State<AdminPaymentsScreen> {
  String _view = 'requests';
  Map<String, String> _labels = const {'none': 'Chưa đăng ký', 'trial': 'Dùng thử 30 ngày'};

  @override
  void initState() {
    super.initState();
    _loadLabels();
  }

  Future<void> _loadLabels() async {
    try {
      final res = await context.read<ApiClient>().get('/me/packages?all=1');
      final list = res is Map ? res['packages'] : null;
      if (list is List && mounted) {
        setState(
          () => _labels = {
            ..._labels,
            for (final p in list)
              if (p is Map) '${p['type']}': '${p['label']}',
          },
        );
      }
    } on ApiError {
      // labels are cosmetic: unknown codes are shown as-is
    }
  }

  String _label(String code) => _labels[code] ?? code;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillBar<String>(items: const [('requests', 'Duyệt thanh toán'), ('renewals', 'Lịch sử gia hạn')], value: _view, onChanged: (v) => setState(() => _view = v)),
          ),
        ),
        Expanded(
          child: _view == 'requests' ? PaymentRequestsView(key: const ValueKey('req'), label: _label) : RenewalsView(key: const ValueKey('ren'), label: _label),
        ),
      ],
    );
  }
}

class PaymentRequestsView extends StatefulWidget {
  const PaymentRequestsView({super.key, required this.label});
  final String Function(String) label;
  @override
  State<PaymentRequestsView> createState() => _PaymentRequestsViewState();
}

class _PaymentRequestsViewState extends State<PaymentRequestsView> {
  PaymentFilter _f = const PaymentFilter();
  final _q = TextEditingController();
  Timer? _debounce;
  bool _loading = true, _more = false, _busy = false, _exporting = false;
  bool _hasMore = false;
  int _total = 0;
  int _gen = 0; // drops answers of superseded requests
  String? _error, _actionError;
  List<PaymentRequest> _items = [];
  PaymentSummary? _summary;

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final gen = ++_gen;
    setState(() {
      if (more) {
        _more = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final res = await _api.get('/admin/payment-requests?${_f.query(limit: kPaymentPageSize, offset: more ? _items.length : 0)}');
      if (!mounted || gen != _gen) return;
      final page = PaymentPage.fromJson(res as Map<String, dynamic>);
      setState(() {
        _items = more ? [..._items, ...page.requests] : page.requests;
        _total = page.total;
        _hasMore = page.hasMore;
        _summary = page.summary ?? _summary;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() => _error = errText(e, 'Không thể tải danh sách yêu cầu'));
    } finally {
      if (mounted && gen == _gen) {
        setState(() {
          _loading = false;
          _more = false;
        });
      }
    }
  }

  void _setFilter(PaymentFilter f, {bool debounce = false}) {
    setState(() => _f = f);
    _debounce?.cancel();
    if (debounce) {
      _debounce = Timer(const Duration(milliseconds: 300), _load);
    } else {
      _load();
    }
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final cur = DateTime.tryParse(isFrom ? _f.from : _f.to);
    final d = await showDatePicker(context: context, initialDate: cur ?? now, firstDate: DateTime(2020), lastDate: DateTime(now.year + 1));
    if (d == null) return;
    _setFilter(isFrom ? _f.copyWith(from: isoOf(d)) : _f.copyWith(to: isoOf(d)));
  }

  Future<void> _approve(PaymentRequest r) async {
    final ok = await confirmDialog(
      context,
      title: 'Duyệt thanh toán',
      message: 'Xác nhận đã nhận ${formatVnd(r.amount)} từ ${r.userName} (${r.referenceCode}) và cấp gói ${widget.label(r.packageType)}?',
      confirmText: 'Duyệt',
    );
    if (ok) await _act(r.id, 'approve');
  }

  Future<void> _reject(PaymentRequest r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectDialog(request: r),
    );
    if (reason != null) await _act(r.id, 'reject', {'reason': reason});
  }

  Future<void> _act(String id, String action, [Map<String, dynamic>? body]) async {
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await _api.post('/admin/payment-requests/$id/$action', body);
    } catch (e) {
      if (mounted) setState(() => _actionError = errText(e, 'Không thể xử lý yêu cầu'));
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _error = null;
    });
    try {
      final bytes = await _api.blob('/admin/payment-requests/export?${_f.query()}');
      await saveAndShareFile(bytes, paymentsCsvName(DateTime.now()), mime: 'text/csv');
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không xuất được file'));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (s != null) _summaryTiles(s),
          const SizedBox(height: 12),
          _filters(),
          const SizedBox(height: 12),
          if (_error != null) Banner2(_error!),
          if (_actionError != null) Banner2(_actionError!),
          if (_loading)
            const Placeholder2('', busy: true)
          else if (_items.isEmpty)
            const Placeholder2('Không có yêu cầu nào')
          else ...[
            for (final r in _items) Padding(padding: const EdgeInsets.only(bottom: 10), child: _tile(r)),
            Row(
              children: [
                Expanded(
                  child: Text('Hiển thị ${_items.length} / $_total', style: TextStyle(color: context.mutedColor)),
                ),
                if (_hasMore) AppButton(label: 'Xem thêm', variant: AppButtonVariant.secondary, loading: _more, onPressed: _more ? null : () => _load(more: true)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryTiles(PaymentSummary s) {
    Widget tile(String label, String value, {bool hot = false}) => SizedBox(
      width: (MediaQuery.sizeOf(context).width - 32 - 10) / 2,
      child: Card(
        shape: hot
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Theme.of(context).colorScheme.primary),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: context.mutedColor)),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ),
      ),
    );
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        tile('Chờ duyệt', '${s.pending}', hot: s.pending > 0),
        tile('Doanh thu hôm nay', formatVnd(s.revenueToday)),
        tile('7 ngày', formatVnd(s.revenue7d)),
        tile('30 ngày', formatVnd(s.revenue30d)),
        tile('Tổng (${s.approvedCount} giao dịch)', formatVnd(s.revenueAll)),
      ],
    );
  }

  Widget _filters() {
    Widget date(String label, String value, bool isFrom) => Expanded(
      child: AppButton(label: value.isEmpty ? label : '$label ${viDate(value)}', variant: AppButtonVariant.secondary, svg: AppSvg.calendar, onPressed: () => _pickDate(isFrom)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: AppDropdown<String>(
                key: const ValueKey('status-filter'),
            isExpanded: true,
                initialValue: _f.status,
                decoration: const InputDecoration(labelText: 'Trạng thái'),
                items: [for (final t in paymentStatusFilters) DropdownMenuItem(value: t.$1, child: Text(t.$2))],
                onChanged: (v) => v == null ? null : _setFilter(_f.copyWith(status: v)),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(label: 'Xuất CSV', variant: AppButtonVariant.secondary, svg: AppSvg.download, loading: _exporting, onPressed: _exporting || _loading ? null : _export),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _q,
          decoration: const InputDecoration(hintText: 'Tìm tên, tài khoản hoặc mã tham chiếu...', prefixIcon: SvgIcon(AppSvg.search, size: 8)),
          onChanged: (v) => _setFilter(_f.copyWith(q: v), debounce: true),
        ),
        const SizedBox(height: 10),
        Row(children: [date('Từ ngày', _f.from, true), const SizedBox(width: 8), date('Đến ngày', _f.to, false)]),
        if (_f.hasExtra)
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(label: 'Xoá lọc', variant: AppButtonVariant.ghost, onPressed: () {
                _q.clear();
                _setFilter(PaymentFilter(status: _f.status));
              }),
          ),
      ],
    );
  }

  Widget _tile(PaymentRequest r) {
    final color = switch (r.status) {
      'approved' => context.okColor,
      'rejected' => context.badColor,
      'pending' => Brand.warning,
      _ => context.mutedColor,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${r.userName} (@${r.username})', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
                  child: Text(
                    paymentStatusLabels[r.status] ?? r.status,
                    style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('${widget.label(r.packageType)} · ${formatVnd(r.amount)}'),
            const SizedBox(height: 2),
            SelectableText(r.referenceCode, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 2),
            Text('Tạo: ${viDateTime(r.createdAt)}${r.decidedAt != null ? '\nXử lý: ${viDateTime(r.decidedAt)}' : ''}', style: TextStyle(color: context.mutedColor, fontSize: 12)),
            if (r.status == 'rejected' && (r.rejectReason ?? '').isNotEmpty) Text('Lý do: ${r.rejectReason}', style: TextStyle(color: context.badColor, fontSize: 13)),
            if (r.pending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: AppButton(label: 'Duyệt', variant: AppButtonVariant.primary, onPressed: _busy ? null : () => _approve(r)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppButton(label: 'Từ chối', variant: AppButtonVariant.danger, onPressed: _busy ? null : () => _reject(r)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog({required this.request});
  final PaymentRequest request;
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return AlertDialog(
      title: const Text('Từ chối thanh toán'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${r.userName} - ${r.referenceCode} - ${formatVnd(r.amount)}', style: TextStyle(color: context.mutedColor, fontSize: 13)),
            const SizedBox(height: 12),
            const Text('Lý do (người dùng sẽ nhìn thấy)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final x in rejectReasonPresets) ActionChip(label: Text(x), onPressed: () => setState(() => _c.text = x))],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _c,
              maxLength: 200,
              maxLines: 3,
              minLines: 2,
              decoration: const InputDecoration(hintText: 'Không bắt buộc'),
            ),
          ],
        ),
      ),
      actions: [
        AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(context)),
        AppButton(label: 'Từ chối', variant: AppButtonVariant.danger, onPressed: () => Navigator.pop(context, _c.text.trim())),
      ],
    );
  }
}

class RenewalsView extends StatefulWidget {
  const RenewalsView({super.key, required this.label});
  final String Function(String) label;
  @override
  State<RenewalsView> createState() => _RenewalsViewState();
}

class _RenewalsViewState extends State<RenewalsView> {
  bool _loading = true;
  String? _error;
  List<Renewal> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await context.read<ApiClient>().get('/admin/renewals');
      final list = res is Map ? res['renewals'] : null;
      if (!mounted) return;
      setState(
        () => _items = [
          for (final r in (list as List? ?? const []))
            if (r is Map<String, dynamic>) Renewal.fromJson(r),
        ],
      );
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không thể tải danh sách gia hạn'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text('Lịch sử mua/gia hạn gói dịch vụ toàn hệ thống, gồm các yêu cầu đã được duyệt (tối đa 200 gần nhất)', style: TextStyle(color: context.mutedColor, fontSize: 13)),
          const SizedBox(height: 12),
          if (_error != null) Banner2(_error!),
          if (_loading)
            const Placeholder2('', busy: true)
          else if (_items.isEmpty)
            const Placeholder2('Chưa có giao dịch nào')
          else
            for (final r in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    title: Text(r.userName, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('${renewalTypeLabels[r.type] ?? r.type} · ${widget.label(r.packageType)}\n${viDateTime(r.createdAt)}'),
                    isThreeLine: true,
                    trailing: Text(formatVnd(r.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
