import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import 'account_controller.dart';
import 'account_widgets.dart';
import 'me_profile.dart';

String formatVnd(num n) => '${formatNumber(n)}đ';

String paymentStatusLabel(String s) => const {'pending': 'Đang chờ duyệt', 'approved': 'Đã duyệt', 'rejected': 'Bị từ chối', 'cancelled': 'Đã huỷ'}[s] ?? s;

/// VietQR image URL built exactly like PackagesView.vue; null while there is no pending request or no bank configured.
String? vietQrUrl({required Map<String, dynamic>? bank, required Map<String, dynamic>? pending, required String username}) {
  final bin = bank?['bankBin'], acct = bank?['bankAccountNumber'];
  if (bank == null || pending == null || bin is! String || bin.isEmpty || acct is! String || acct.isEmpty) return null;
  final ref = pending['referenceCode'];
  final params = {
    'amount': '${pending['amount']}',
    'addInfo': ref is String && ref.isNotEmpty ? ref : '$username ${pending['packageType']}'.trim(),
    'accountName': (bank['bankAccountHolder'] as String?) ?? '',
  };
  return Uri.parse('https://img.vietqr.io/image/$bin-$acct-compact2.png').replace(queryParameters: params).toString();
}

/// Gói & Thanh toán: current package, catalog (purchase -> pending payment request), bank info + VietQR, history, cancel.
class AccountPackagesTab extends StatefulWidget {
  const AccountPackagesTab({super.key, required this.ctl});
  final AccountController ctl;
  @override
  State<AccountPackagesTab> createState() => _AccountPackagesTabState();
}

class _AccountPackagesTabState extends State<AccountPackagesTab> {
  List<Map<String, dynamic>> _plans = [];
  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic>? _bank;
  bool _loading = true;
  String? _loadError;
  String? _error;
  String? _success;
  String? _purchasing;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  List<Map<String, dynamic>> _list(Object? v) => [for (final x in (v as List? ?? const [])) (x as Map).cast<String, dynamic>()];

  Map<String, dynamic>? get _pending {
    for (final r in _requests) {
      if (r['status'] == 'pending') return r;
    }
    return null;
  }

  Future<void> _loadAll() async {
    final api = context.read<ApiClient>();
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final r = await Future.wait<dynamic>([api.get('/me/packages'), api.get('/me/payment-info'), api.get('/me/payment-requests'), widget.ctl.load(silent: true)]);
      if (!mounted) return;
      setState(() {
        _plans = _list((r[0] as Map)['packages']);
        _bank = (r[1] as Map).cast<String, dynamic>();
        _requests = _list((r[2] as Map)['requests']);
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e is ApiError ? e.message : 'Không tải được thông tin gói');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _planLabel(String type) {
    for (final p in _plans) {
      if (p['type'] == type) return '${p['label']}';
    }
    return type;
  }

  Future<void> _purchase(Map<String, dynamic> plan) async {
    final api = context.read<ApiClient>();
    setState(() {
      _error = null;
      _success = null;
    });
    if (_pending != null) return;
    if (!await confirmDialog(context, title: 'Đăng ký gói', message: 'Xác nhận đăng ký gói "${plan['label']}" (${formatVnd(plan['priceVnd'] as num)})? Bạn sẽ cần chuyển khoản và chờ admin duyệt.', confirmText: 'Đăng ký')) return;
    setState(() => _purchasing = plan['type'] as String?);
    try {
      await api.post('/me/packages/purchase', {'packageType': plan['type']});
      _success = 'Đã tạo yêu cầu. Vui lòng chuyển khoản theo thông tin bên dưới và chờ admin xác nhận.';
      await _loadAll();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không tạo được yêu cầu mua gói');
    } finally {
      if (mounted) setState(() => _purchasing = null);
    }
  }

  Future<void> _cancel(Map<String, dynamic> r) async {
    final api = context.read<ApiClient>();
    if (!await confirmDialog(context,
        title: 'Huỷ yêu cầu',
        message: 'Huỷ yêu cầu gói "${_planLabel('${r['packageType']}')}" (${r['referenceCode']})? Nếu bạn đã chuyển khoản, hãy liên hệ admin trước khi huỷ.',
        confirmText: 'Huỷ yêu cầu',
        danger: true)) {
      return;
    }
    setState(() {
      _cancelling = true;
      _error = null;
    });
    try {
      await api.post('/me/payment-requests/${r['id']}/cancel');
      _success = 'Đã huỷ yêu cầu.';
    } catch (e) {
      _error = e is ApiError ? e.message : 'Không huỷ được yêu cầu';
    }
    await _loadAll();
    if (mounted) setState(() => _cancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _plans.isEmpty) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    if (_loadError != null && _plans.isEmpty) return Column(children: [NoticeBox(_loadError!), OutlinedButton(onPressed: _loadAll, child: const Text('Thử lại'))]);
    final me = widget.ctl.me;
    final pending = _pending;
    final qr = vietQrUrl(bank: _bank, pending: pending, username: me?.username ?? '');
    final ok = context.okColor, bad = context.badColor;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _loading ? null : _loadAll, icon: const Icon(Icons.refresh, size: 18), label: const Text('Làm mới'))),
      SectionCard(title: 'Gói hiện tại', children: [
        Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          StatusChip(me?.packageLabel ?? '-', color: me?.packageActive == true ? ok : bad),
          Text('Hết hạn: ${viDateTimeLocal(me?.packageExpiresAt)}', style: TextStyle(color: context.mutedColor)),
        ]),
        if (me != null && !me.packageActive) const Padding(padding: EdgeInsets.only(top: 12), child: NoticeBox('Gói đã hết hạn. Đăng ký gói mới bên dưới để tiếp tục sử dụng.', kind: NoticeKind.warning)),
      ]),
      const SizedBox(height: 12),
      if (pending != null)
        NoticeBox('Yêu cầu gói "${_planLabel('${pending['packageType']}')}" (${formatVnd(pending['amount'] as num)}) đang chờ admin xác nhận. Chuyển khoản đúng số tiền và ghi nội dung ${pending['referenceCode']} để được duyệt nhanh.', kind: NoticeKind.warning),
      if (pending != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.copy, size: 18), onPressed: () => copyText(context, '${pending['referenceCode']}', done: 'Đã sao chép nội dung chuyển khoản'), label: const Text('Sao chép nội dung'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: _cancelling ? null : () => _cancel(pending), child: const Text('Huỷ yêu cầu'))),
          ]),
        ),
      if (_error != null) NoticeBox(_error!),
      if (_success != null) NoticeBox(_success!, kind: NoticeKind.success),
      const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('Các gói có sẵn', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      if (_plans.isEmpty) Text('Chưa có gói nào.', style: TextStyle(color: context.mutedColor)),
      for (final plan in _plans)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${plan['label']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(formatVnd(plan['priceVnd'] as num), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Brand.gold)),
                    Text('${plan['durationDays']} ngày', style: TextStyle(color: context.mutedColor, fontSize: 13)),
                  ]),
                ),
                FilledButton(onPressed: pending != null || _purchasing != null ? null : () => _purchase(plan), child: Text(_purchasing == plan['type'] ? 'Đang xử lý...' : 'Đăng ký')),
              ]),
            ),
          ),
        ),
      const SizedBox(height: 4),
      SectionCard(title: 'Thông tin chuyển khoản', children: [
        if (_bank?['bankName'] != null) ...[
          InfoRow('Ngân hàng', value: '${_bank!['bankName']}'),
          InfoRow('Số tài khoản', child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: SelectableText('${_bank!['bankAccountNumber']}', style: const TextStyle(fontWeight: FontWeight.w600))),
            IconButton(visualDensity: VisualDensity.compact, tooltip: 'Sao chép', icon: const Icon(Icons.copy, size: 18), onPressed: () => copyText(context, '${_bank!['bankAccountNumber']}')),
          ])),
          InfoRow('Chủ tài khoản', value: '${_bank!['bankAccountHolder'] ?? '-'}'),
          if (pending != null) ...[
            InfoRow('Số tiền', value: formatVnd(pending['amount'] as num)),
            InfoRow('Nội dung', value: '${pending['referenceCode']}'),
          ],
          if (qr != null) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 232,
                height: 232,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Image.network(
                  qr,
                  fit: BoxFit.contain,
                  semanticLabel: 'Mã QR chuyển khoản',
                  loadingBuilder: (c, child, p) => p == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (c, e, s) => const Center(child: Text('Không tải được mã QR', style: TextStyle(color: Colors.black54), textAlign: TextAlign.center)),
                ),
              ),
            ),
            Padding(padding: const EdgeInsets.only(top: 8), child: Text('Quét mã bằng app ngân hàng để tự động điền số tiền và nội dung chuyển khoản.', textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor, fontSize: 13))),
          ],
        ] else
          Text('Chưa cấu hình thông tin thanh toán.', style: TextStyle(color: context.mutedColor)),
      ]),
      const Padding(padding: EdgeInsets.fromLTRB(0, 16, 0, 6), child: Text('Lịch sử thanh toán', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
      if (_requests.isEmpty) Card(child: Padding(padding: const EdgeInsets.all(14), child: Text('Chưa có yêu cầu nào.', style: TextStyle(color: context.mutedColor)))),
      for (final r in _requests)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(_planLabel('${r['packageType']}'), style: const TextStyle(fontWeight: FontWeight.w700))),
                  StatusChip(paymentStatusLabel('${r['status']}'), color: switch (r['status']) { 'approved' => ok, 'rejected' => bad, 'pending' => Brand.warning, _ => null }),
                ]),
                const SizedBox(height: 4),
                Text('${formatVnd(r['amount'] as num)} · ${viDateTimeLocal(r['createdAt'] as String?, withTime: true)}${r['referenceCode'] != null ? ' · ${r['referenceCode']}' : ''}', style: TextStyle(color: context.mutedColor, fontSize: 13)),
                if (r['status'] == 'rejected' && r['rejectReason'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Lý do: ${r['rejectReason']}', style: TextStyle(color: bad, fontSize: 13))),
              ]),
            ),
          ),
        ),
    ]);
  }
}
