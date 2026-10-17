import 'package:flutter/material.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import 'admin_users_logic.dart';
import 'admin_users_widgets.dart';
import '../../../core/widgets/app_button.dart';

/// Queue of "nhờ Admin hỗ trợ khôi phục" requests (port of AdminRecoveryRequests.vue). Needs users.recovery.
class AdminRecoveryRequestsPage extends StatefulWidget {
  const AdminRecoveryRequestsPage({super.key, required this.api, this.onCount});
  final ApiClient api;
  final ValueChanged<int>? onCount;
  @override
  State<AdminRecoveryRequestsPage> createState() => _State();
}

class _State extends State<AdminRecoveryRequestsPage> {
  bool _loading = true;
  String? _error;
  RecoveryQueue _queue = const RecoveryQueue(0, []);
  String? _busyId;
  ({String username, String ticket, String expiresAt})? _issued; // shown once

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await widget.api.get('/admin/recovery-requests') as Map<String, dynamic>;
      final q = RecoveryQueue.fromJson(res);
      if (!mounted) return;
      setState(() {
        _queue = q;
        _error = null;
      });
      widget.onCount?.call(q.pending);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(RecoveryRequest r, String action) async {
    if (action == 'reject' &&
        !await adminConfirm(context,
            title: 'Từ chối yêu cầu',
            message: 'Từ chối yêu cầu khôi phục của "${r.username}"? Mã hỗ trợ đã cấp (nếu có) sẽ vô hiệu.',
            confirmText: 'Từ chối',
            danger: true)) {
      return;
    }
    setState(() {
      _busyId = r.id;
      _error = null;
    });
    try {
      final res = await widget.api.post('/admin/recovery-requests/${r.id}', {'action': action}) as Map<String, dynamic>;
      if (action == 'approve') {
        _issued = (username: r.username, ticket: '${res['ticket']}', expiresAt: '${res['expiresAt']}');
      }
      await _load();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yêu cầu khôi phục tài khoản')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
            'Hãy xác minh người gửi là chủ tài khoản qua kênh riêng (số điện thoại, tin nhắn đã đăng ký...) trước khi duyệt. Khách sẽ tự đặt mật khẩu mới bằng mã hỗ trợ, Admin không biết mật khẩu.',
            style: TextStyle(fontSize: 13, color: context.mutedColor),
          ),
          const SizedBox(height: 12),
          if (_error != null) AdminBanner(_error!),
          if (_issued != null) _issuedCard(context),
          if (_loading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_queue.requests.isEmpty)
            const EmptyState('Không có yêu cầu nào đang chờ')
          else
            for (final r in _queue.requests) _item(context, r),
        ]),
      ),
    );
  }

  Widget _issuedCard(BuildContext context) {
    final i = _issued!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.okColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: context.okColor.withValues(alpha: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SecretRow(label: 'Mã hỗ trợ cho ${i.username}', value: i.ticket),
        Text(
          'Hạn dùng đến ${fmtDateTime(i.expiresAt)}, dùng một lần. Gửi cho khách qua kênh riêng ngay bây giờ vì mã không xem lại được. Khách vào Đăng nhập, Quên mật khẩu, "Tôi đã có mã hỗ trợ từ Admin".',
          style: TextStyle(fontSize: 12, color: context.mutedColor),
        ),
        Align(alignment: Alignment.centerRight, child: AppButton(label: 'Đã gửi, ẩn mã', variant: AppButtonVariant.ghost, onPressed: () => setState(() => _issued = null))),
      ]),
    );
  }

  Widget _item(BuildContext context, RecoveryRequest r) {
    final busy = _busyId == r.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${r.name} (${r.username})', style: const TextStyle(fontWeight: FontWeight.w600))),
            AdminChip(r.statusLabel, color: r.isPending ? context.badColor : (r.status == 'approved' ? context.okColor : null)),
          ]),
          if (r.accountLocked) Padding(padding: const EdgeInsets.only(top: 4), child: AdminChip('Tài khoản đang khoá', color: context.badColor)),
          const SizedBox(height: 6),
          Text(
            'Gửi lúc ${fmtDateTime(r.createdAt)} · IP ${r.ip ?? '-'} · Đăng ký ${fmtDateTime(r.registeredAt)}${r.status == 'approved' ? ' · Mã hết hạn ${fmtDateTime(r.ticketExpiresAt)}' : ''}',
            style: TextStyle(fontSize: 13, color: context.mutedColor),
          ),
          if (r.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Ghi chú của khách: ${r.note}', style: TextStyle(fontSize: 13, color: context.mutedColor))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: AppButton(label: r.isPending ? 'Duyệt, cấp mã' : 'Cấp lại mã', variant: AppButtonVariant.primary, onPressed: busy ? null : () => _act(r, 'approve'))),
            const SizedBox(width: 8),
            AppButton(label: 'Từ chối', variant: AppButtonVariant.danger, onPressed: busy ? null : () => _act(r, 'reject')),
          ]),
        ]),
      ),
    );
  }
}
