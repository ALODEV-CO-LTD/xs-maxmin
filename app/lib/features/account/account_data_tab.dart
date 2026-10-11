import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'account_controller.dart';
import 'account_widgets.dart';
import 'auth_flows.dart' show errorText;

/// Must match backend/lib/src/data_wipe.dart (the single definition of the wipe scope).
const wipeDeletes = 'số liệu đã nhập, danh sách khách hàng, mẫu cú pháp, lịch xoá tự động, nhật ký cuộc gọi, tin nhắn phản hồi với Admin, lịch sử giao dịch và các yêu cầu thanh toán chưa duyệt';
const wipeKeeps = 'Tài khoản, gói dịch vụ, danh sách bạn bè, tin nhắn trò chuyện với bạn bè, Mã ID và cấu hình tính điểm được giữ nguyên.';

/// Dữ liệu: recovery code (create / replace, password re-checked) and "delete all my data".
class AccountDataTab extends StatelessWidget {
  const AccountDataTab({super.key, required this.ctl});
  final AccountController ctl;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (ctl.me?.isAdmin != true) _RecoveryCodeCard(ctl: ctl),
        if (ctl.me?.isAdmin != true) const SizedBox(height: 14),
        const _DeleteDataCard(),
      ]);
}

class _RecoveryCodeCard extends StatefulWidget {
  const _RecoveryCodeCard({required this.ctl});
  final AccountController ctl;
  @override
  State<_RecoveryCodeCard> createState() => _RecoveryCodeCardState();
}

class _RecoveryCodeCardState extends State<_RecoveryCodeCard> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  String? _newCode;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.isEmpty) return setState(() => _error = 'Nhập mật khẩu hiện tại để tiếp tục');
    final api = context.read<ApiClient>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await api.post('/me/recovery-code', {'currentPassword': _password.text});
      final code = res is Map ? res['recoveryCode'] : null;
      if (code is! String || code.isEmpty) throw ApiError(500, 'Không tạo được mã khôi phục');
      _password.clear();
      if (mounted) setState(() => _newCode = code);
      await widget.ctl.load(silent: true);
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.ctl.me?.hasRecoveryCode == true;
    return SectionCard(title: 'Mã khôi phục', children: [
      if (_newCode != null)
        RecoveryCodeDisplay(code: _newCode!, continueText: 'Xong', onConfirmed: () => setState(() => _newCode = null))
      else ...[
        Text(
          has
              ? 'Bạn đã có mã khôi phục (vì lý do bảo mật, mã cũ không thể xem lại). Tạo mã mới sẽ vô hiệu mã cũ. Mã chỉ hiển thị một lần.'
              : 'Tài khoản chưa có mã khôi phục. Tạo mã để có thể đặt lại mật khẩu khi quên (mã chỉ hiển thị một lần).',
          style: TextStyle(color: context.mutedColor, fontSize: 13.5),
        ),
        const SizedBox(height: 12),
        if (_error != null) NoticeBox(_error!),
        PasswordField(controller: _password, label: 'Mật khẩu hiện tại', enabled: !_busy, onSubmitted: (_) => _submit()),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Đang tạo...' : has ? 'Đổi mã khôi phục' : 'Tạo mã khôi phục')),
      ],
    ]);
  }
}

class _DeleteDataCard extends StatefulWidget {
  const _DeleteDataCard();
  @override
  State<_DeleteDataCard> createState() => _DeleteDataCardState();
}

class _DeleteDataCardState extends State<_DeleteDataCard> {
  String? _error;
  String? _success;
  bool _busy = false;

  Future<void> _delete() async {
    final api = context.read<ApiClient>();
    if (!await confirmDialog(context, title: 'Xoá toàn bộ dữ liệu', message: 'CẢNH BÁO: Thao tác này sẽ xoá vĩnh viễn: $wipeDeletes. $wipeKeeps Bạn có chắc chắn muốn tiếp tục?', confirmText: 'Tiếp tục', danger: true)) return;
    if (!mounted) return;
    final password = await showDialog<String>(context: context, builder: (_) => const _PasswordPrompt());
    if (password == null || password.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      await api.post('/me/delete-data', {'password': password});
      if (mounted) setState(() => _success = 'Đã xoá toàn bộ dữ liệu của bạn.');
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không xoá được dữ liệu');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(title: 'Xoá toàn bộ dữ liệu', danger: true, children: [
      Text('Xoá: $wipeDeletes. $wipeKeeps Không thể hoàn tác.', style: TextStyle(color: context.mutedColor, fontSize: 13.5)),
      const SizedBox(height: 12),
      if (_error != null) NoticeBox(_error!),
      if (_success != null) NoticeBox(_success!, kind: NoticeKind.success),
      FilledButton(
        style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError),
        onPressed: _busy ? null : _delete,
        child: Text(_busy ? 'Đang xoá...' : 'Xoá toàn bộ dữ liệu'),
      ),
    ]);
  }
}

class _PasswordPrompt extends StatefulWidget {
  const _PasswordPrompt();
  @override
  State<_PasswordPrompt> createState() => _PasswordPromptState();
}

class _PasswordPromptState extends State<_PasswordPrompt> {
  final _c = TextEditingController();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Xác nhận xoá dữ liệu'),
        content: PasswordField(controller: _c, label: 'Mật khẩu đăng nhập', autofocus: true, onSubmitted: (v) => Navigator.pop(context, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Xoá dữ liệu')),
        ],
      );
}
