import 'dart:async';
import '../../core/widgets/svg_icon.dart';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/format.dart';
import '../../core/package_events.dart';
import '../../core/theme.dart';
import 'account_controller.dart';
import 'account_widgets.dart';
import 'me_profile.dart';
import '../../core/widgets/app_button.dart';

String formatVnd(num n) => '${formatNumber(n)}đ';

String paymentStatusLabel(String s) => const {'pending': 'Đang chờ duyệt', 'approved': 'Đã duyệt', 'rejected': 'Bị từ chối', 'cancelled': 'Đã huỷ'}[s] ?? s;

/// VietQR image URL (amount, content and account name are in the link, so the banking app fills them in when it scans the code).
/// It must be `api.vietqr.io`: `img.vietqr.io` now answers a `.png` request with an SVG, which Image.network cannot draw.
/// Null while there is no pending request or no bank configured.
String? vietQrUrl({required Map<String, dynamic>? bank, required Map<String, dynamic>? pending, required String username}) {
  final bin = bank?['bankBin'], acct = bank?['bankAccountNumber'];
  if (bank == null || pending == null || bin is! String || bin.isEmpty || acct is! String || acct.isEmpty) return null;
  final ref = pending['referenceCode'];
  final params = {
    'amount': '${pending['amount']}',
    'addInfo': ref is String && ref.isNotEmpty ? ref : '$username ${pending['packageType']}'.trim(),
    'accountName': (bank['bankAccountHolder'] as String?) ?? '',
  };
  return Uri.parse('https://api.vietqr.io/image/$bin-$acct-compact2.png').replace(queryParameters: params).toString();
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

  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadAll();
    // Admin decided a request: read the package and the requests again (the live event from the server).
    PackageEvents.instance.addListener(_loadAll);
    // While a request waits for Admin, look again every 30 s: the live event is lost when the connection is down.
    _poll = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _pending != null && !_loading) _loadAll();
    });
  }

  @override
  void dispose() {
    PackageEvents.instance.removeListener(_loadAll);
    _poll?.cancel();
    super.dispose();
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

  /// "XS" + 6 characters, like the server's own references (no 0/O/1/I). It is made here so the QR can carry it BEFORE any request
  /// exists; the server keeps it when the request is sent.
  static String newReference([Random? random]) {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = random ?? Random.secure();
    return 'XS${List.generate(6, (_) => alphabet[r.nextInt(alphabet.length)]).join()}';
  }

  /// "Gia hạn" / "Đăng ký": the transfer QR comes first. Nothing reaches Admin until "Đã chuyển khoản" is pressed there; "Huỷ"
  /// (or closing the sheet) leaves no request behind.
  Future<void> _purchase(Map<String, dynamic> plan) async {
    final api = context.read<ApiClient>();
    setState(() {
      _error = null;
      _success = null;
    });
    if (_pending != null) return;
    final draft = <String, dynamic>{'packageType': plan['type'], 'amount': plan['priceVnd'], 'referenceCode': newReference()};
    final transferred = await _showTransferSheet(draft, confirm: true);
    if (transferred != true || !mounted) return;
    setState(() => _purchasing = plan['type'] as String?);
    try {
      final res = await api.post('/me/packages/purchase', {'packageType': plan['type'], 'referenceCode': draft['referenceCode']});
      final ref = res is Map ? res['referenceCode'] : null;
      _success = ref is String && ref != draft['referenceCode']
          ? 'Đã gửi yêu cầu cho admin. Lưu ý: nội dung chuyển khoản của yêu cầu này là $ref (khác mã trên QR vừa rồi), admin sẽ đối chiếu theo số tiền.'
          : 'Đã gửi yêu cầu cho admin. Admin sẽ xác nhận khi nhận được tiền và bạn sẽ nhận được thông báo.';
      await _loadAll();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không gửi được yêu cầu mua gói');
    } finally {
      if (mounted) setState(() => _purchasing = null);
    }
  }

  /// The plan the customer has now (renewing it is "Gia hạn", any other one is "Đăng ký").
  bool _isCurrent(Map<String, dynamic> plan) {
    final t = widget.ctl.me?.packageType;
    return t != null && t.isNotEmpty && t == plan['type'];
  }

  /// Bank, account, holder, amount, content and the VietQR (amount and content are filled in when it is scanned).
  List<Widget> _transferRows(Map<String, dynamic>? pending, String? qr) {
    final bank = _bank;
    if (bank?['bankName'] == null) return [Text('Admin chưa cài thông tin tài khoản nhận tiền nên chưa có số tài khoản và mã QR. Hãy liên hệ Admin để được hướng dẫn chuyển khoản.', style: TextStyle(color: context.mutedColor))];
    return [
      InfoRow('Ngân hàng', value: '${bank!['bankName']}'),
      InfoRow('Số tài khoản', child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(child: SelectableText('${bank['bankAccountNumber']}', style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(visualDensity: VisualDensity.compact, tooltip: 'Sao chép', icon: const SvgIcon(AppSvg.copy, size: 18), onPressed: () => copyText(context, '${bank['bankAccountNumber']}')),
      ])),
      InfoRow('Chủ tài khoản', value: '${bank['bankAccountHolder'] ?? '-'}'),
      if (pending != null) ...[
        InfoRow('Số tiền', child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(formatVnd(pending['amount'] as num), style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Sao chép', icon: const SvgIcon(AppSvg.copy, size: 18), onPressed: () => copyText(context, '${pending['amount']}', done: 'Đã sao chép số tiền')),
        ])),
        InfoRow('Nội dung', child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: SelectableText('${pending['referenceCode']}', style: const TextStyle(fontWeight: FontWeight.w600))),
          IconButton(visualDensity: VisualDensity.compact, tooltip: 'Sao chép', icon: const SvgIcon(AppSvg.copy, size: 18), onPressed: () => copyText(context, '${pending['referenceCode']}', done: 'Đã sao chép nội dung chuyển khoản')),
        ])),
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
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Quét mã bằng app ngân hàng: số tiền và nội dung chuyển khoản được điền sẵn.', textAlign: TextAlign.center, style: TextStyle(color: context.mutedColor, fontSize: 13))),
      ],
    ];
  }

  /// The transfer details of [pending] in a sheet. With [confirm] (right after "Gia hạn" / "Đăng ký", before any request exists) it
  /// ends with "Huỷ" and "Đã chuyển khoản" and returns true only for the latter; otherwise it is just a view of a waiting request.
  Future<bool?> _showTransferSheet(Map<String, dynamic> pending, {bool confirm = false}) {
    final qr = vietQrUrl(bank: _bank, pending: pending, username: widget.ctl.me?.username ?? '');
    final hasBank = _bank?['bankName'] != null;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Chuyển khoản để kích hoạt gói', style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            confirm
                ? 'Gói "${_planLabel('${pending['packageType']}')}" · ${formatVnd(pending['amount'] as num)}. Chuyển khoản theo thông tin dưới đây, rồi bấm "Đã chuyển khoản" để gửi yêu cầu cho admin.'
                : 'Gói "${_planLabel('${pending['packageType']}')}" · ${formatVnd(pending['amount'] as num)}. Sau khi chuyển khoản, admin sẽ xác nhận và bạn nhận được thông báo.',
            style: TextStyle(color: context.mutedColor, fontSize: 13),
          ),
          const SizedBox(height: 12),
          ..._transferRows(pending, qr),
          const SizedBox(height: 16),
          if (confirm)
            Row(children: [
              Expanded(child: AppButton(label: 'Huỷ', variant: AppButtonVariant.secondary, onPressed: () => Navigator.pop(ctx, false))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: AppButton(label: 'Đã chuyển khoản', variant: AppButtonVariant.primary, onPressed: hasBank ? () => Navigator.pop(ctx, true) : null)),
            ])
          else
            AppButton(label: 'Đóng', variant: AppButtonVariant.primary, onPressed: () => Navigator.pop(ctx)),
        ]),
      ),
    );
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
    if (_loadError != null && _plans.isEmpty) return Column(children: [NoticeBox(_loadError!), AppButton(label: 'Thử lại', variant: AppButtonVariant.secondary, onPressed: _loadAll)]);
    final me = widget.ctl.me;
    final pending = _pending;
    final ok = context.okColor, bad = context.badColor;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Align(alignment: Alignment.centerRight, child: AppButton(label: 'Làm mới', variant: AppButtonVariant.ghost, svg: AppSvg.refresh, onPressed: _loading ? null : _loadAll)),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppButton(label: 'Xem thông tin chuyển khoản và mã QR', variant: AppButtonVariant.primary, svg: AppSvg.qr, onPressed: () => _showTransferSheet(pending)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: AppButton(label: 'Sao chép nội dung', variant: AppButtonVariant.secondary, svg: AppSvg.copy, onPressed: () => copyText(context, '${pending['referenceCode']}', done: 'Đã sao chép nội dung chuyển khoản'))),
              const SizedBox(width: 10),
              Expanded(child: AppButton(label: 'Huỷ yêu cầu', variant: AppButtonVariant.secondary, onPressed: _cancelling ? null : () => _cancel(pending))),
            ]),
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
                    Row(children: [
                      Flexible(child: Text('${plan['label']}', style: const TextStyle(fontWeight: FontWeight.w700))),
                      if (_isCurrent(plan)) Padding(padding: const EdgeInsets.only(left: 8), child: StatusChip('Đang dùng', color: ok, small: true)),
                    ]),
                    Text(formatVnd(plan['priceVnd'] as num), style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Theme.of(context).colorScheme.primary)),
                    Text('${plan['durationDays']} ngày', style: TextStyle(color: context.mutedColor, fontSize: 13)),
                  ]),
                ),
                AppButton(label: _purchasing == plan['type'] ? 'Đang xử lý...' : (_isCurrent(plan) ? 'Gia hạn' : 'Đăng ký'), variant: AppButtonVariant.primary, onPressed: pending != null || _purchasing != null ? null : () => _purchase(plan)),
              ]),
            ),
          ),
        ),
      // (no standing "Thông tin chuyển khoản" card: the transfer details open in the sheet - after Đăng ký / Gia hạn, or with
      // "Xem thông tin chuyển khoản và mã QR" while a request waits)
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
