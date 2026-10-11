import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import '../account/account_widgets.dart';
import '../account/auth_flows.dart';
import '../account/auth_scaffold.dart';

/// Khôi phục mật khẩu: username + mã khôi phục + new password (then a NEW code is shown once), or the
/// admin-assisted flow (recovery-request -> mã hỗ trợ -> recover-with-ticket). Port of the LoginView.vue recover stages.
class RecoverScreen extends StatefulWidget {
  const RecoverScreen({super.key, this.flow});
  final RecoverFlow? flow;
  @override
  State<RecoverScreen> createState() => _RecoverScreenState();
}

class _RecoverScreenState extends State<RecoverScreen> {
  final _username = TextEditingController();
  final _code = TextEditingController();
  final _ticket = TextEditingController();
  final _note = TextEditingController();
  final _newPw = TextEditingController();
  final _confirm = TextEditingController();
  late final RecoverFlow _flow = widget.flow ?? RecoverFlow(api: context.read<ApiClient>());

  @override
  void initState() {
    super.initState();
    _flow.addListener(_onFlow);
  }

  void _onFlow() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _flow.removeListener(_onFlow);
    if (widget.flow == null) _flow.dispose();
    for (final c in [_username, _code, _ticket, _note, _newPw, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toLogin() => context.go('/login');
  bool get _busy => _flow.loading;
  Widget get _err => _flow.error == null ? const SizedBox.shrink() : NoticeBox(_flow.error!);

  Widget _userField() => TextField(controller: _username, enabled: !_busy, autofillHints: const [AutofillHints.username], decoration: const InputDecoration(labelText: 'Tên đăng nhập'));

  Widget _desc(String t) => Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(t, style: TextStyle(color: context.mutedColor, fontSize: 14)));

  @override
  Widget build(BuildContext context) {
    switch (_flow.stage) {
      case RecoverStage.recover:
        return AuthScaffold(title: 'Khôi phục mật khẩu', onBack: _toLogin, children: [
          _desc('Nhập tên đăng nhập và mã khôi phục để đặt mật khẩu mới. Sau khi đặt lại, bạn sẽ nhận một mã khôi phục mới (mã cũ không dùng được nữa).'),
          _err,
          _userField(),
          const SizedBox(height: 12),
          TextField(controller: _code, enabled: !_busy, autocorrect: false, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Mã khôi phục', hintText: 'XXXX-XXXX-XXXX-XXXX')),
          const SizedBox(height: 12),
          PasswordField(controller: _newPw, label: 'Mật khẩu mới', hint: 'Tuỳ bạn đặt', enabled: !_busy),
          const SizedBox(height: 12),
          PasswordField(controller: _confirm, label: 'Nhập lại mật khẩu mới', enabled: !_busy, onSubmitted: (_) => _submitRecover()),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _submitRecover, child: Text(_busy ? 'Đang xử lý...' : 'Đặt lại mật khẩu')),
          TextButton(onPressed: _busy ? null : () => _flow.go(RecoverStage.helpRequest), child: const Text('Mất cả mã khôi phục? Nhờ Admin hỗ trợ', textAlign: TextAlign.center)),
          TextButton(onPressed: _busy ? null : () => _flow.go(RecoverStage.ticket), child: const Text('Tôi đã có mã hỗ trợ từ Admin')),
          TextButton(onPressed: _toLogin, child: const Text('Quay lại đăng nhập')),
        ]);
      case RecoverStage.helpRequest:
        return AuthScaffold(title: 'Nhờ Admin hỗ trợ', onBack: () => _flow.go(RecoverStage.recover), children: [
          _desc('Gửi yêu cầu để quản trị viên hỗ trợ. Admin sẽ xác minh bạn là chủ tài khoản qua kênh hỗ trợ (ví dụ số điện thoại hoặc tin nhắn đã đăng ký); khi được duyệt bạn nhận một mã hỗ trợ dùng một lần, hạn 24 giờ để tự đặt mật khẩu mới. Admin không biết mật khẩu của bạn.'),
          _err,
          _userField(),
          const SizedBox(height: 12),
          TextField(controller: _note, enabled: !_busy, maxLength: 300, decoration: const InputDecoration(labelText: 'Thông tin giúp Admin xác minh (không bắt buộc)', hintText: 'Ví dụ: tên, số điện thoại liên hệ')),
          const SizedBox(height: 10),
          FilledButton(onPressed: _busy ? null : () => _flow.submitHelp(username: _username.text, note: _note.text), child: Text(_busy ? 'Đang gửi...' : 'Gửi yêu cầu')),
          TextButton(onPressed: _busy ? null : () => _flow.go(RecoverStage.recover), child: const Text('Quay lại')),
        ]);
      case RecoverStage.helpSent:
        return AuthScaffold(title: 'Nhờ Admin hỗ trợ', onBack: _toLogin, children: [
          NoticeBox(_flow.helpMessage, kind: NoticeKind.success),
          FilledButton(onPressed: () => _flow.go(RecoverStage.ticket), child: const Text('Tôi đã có mã hỗ trợ')),
          TextButton(onPressed: _toLogin, child: const Text('Về trang đăng nhập')),
        ]);
      case RecoverStage.ticket:
        return AuthScaffold(title: 'Nhập mã hỗ trợ', onBack: () => _flow.go(RecoverStage.recover), children: [
          _desc('Nhập mã hỗ trợ Admin đã gửi cho bạn và đặt mật khẩu mới. Mã chỉ dùng được một lần.'),
          _err,
          _userField(),
          const SizedBox(height: 12),
          TextField(controller: _ticket, enabled: !_busy, autocorrect: false, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Mã hỗ trợ', hintText: 'XXXX-XXXX-XXXX-XXXX')),
          const SizedBox(height: 12),
          PasswordField(controller: _newPw, label: 'Mật khẩu mới', hint: 'Tuỳ bạn đặt', enabled: !_busy),
          const SizedBox(height: 12),
          PasswordField(controller: _confirm, label: 'Nhập lại mật khẩu mới', enabled: !_busy, onSubmitted: (_) => _submitTicket()),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _submitTicket, child: Text(_busy ? 'Đang xử lý...' : 'Đặt lại mật khẩu')),
          TextButton(onPressed: _toLogin, child: const Text('Quay lại đăng nhập')),
        ]);
      case RecoverStage.recoveryCode:
        return PopScope(
          canPop: false,
          child: AuthScaffold(title: 'Lưu mã khôi phục mới', onBack: () {}, children: [
            const NoticeBox('Đã đặt lại mật khẩu. Đây là mã khôi phục mới của bạn.', kind: NoticeKind.success),
            RecoveryCodeDisplay(
              code: _flow.newRecoveryCode ?? '',
              continueText: 'Về đăng nhập',
              onConfirmed: () {
                _flow.codeConfirmed();
                _toLogin();
              },
            ),
          ]),
        );
    }
  }

  Future<void> _submitRecover() async {
    await _flow.submitRecover(username: _username.text, code: _code.text, newPassword: _newPw.text, confirm: _confirm.text);
    if (_flow.stage == RecoverStage.recoveryCode) _clearSecrets();
  }

  Future<void> _submitTicket() async {
    await _flow.submitTicket(username: _username.text, ticket: _ticket.text, newPassword: _newPw.text, confirm: _confirm.text);
    if (_flow.stage == RecoverStage.recoveryCode) _clearSecrets();
  }

  void _clearSecrets() {
    _code.clear();
    _ticket.clear();
    _newPw.clear();
    _confirm.clear();
  }
}
