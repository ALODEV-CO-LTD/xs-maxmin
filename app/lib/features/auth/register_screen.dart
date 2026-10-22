import 'package:flutter/material.dart';
import '../../core/widgets/svg_icon.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/theme.dart';
import '../account/account_widgets.dart';
import '../account/auth_flows.dart';
import '../account/auth_scaffold.dart';
import '../../core/widgets/app_button.dart';

/// Tạo tài khoản: account info -> security (second password, optional wipe password) -> recovery code shown once ->
/// second password re-typed (final verification). Same flow as frontend RegisterView.vue.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.flow});

  /// Injectable for tests.
  final RegisterFlow? flow;
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _second = TextEditingController();
  final _wipe = TextEditingController();
  final _step2 = TextEditingController();
  bool _wipeEnabled = false;
  bool _submitted = false; // show every field error
  final _touched = <String>{};
  late final RegisterFlow _flow = widget.flow ?? RegisterFlow(api: context.read<ApiClient>(), auth: context.read<AuthStore>());

  @override
  void initState() {
    super.initState();
    _flow.addListener(_onFlow);
    for (final c in [_name, _username, _password, _confirm, _second, _wipe]) {
      c.addListener(_onFlow); // re-validate while typing
    }
  }

  void _onFlow() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _flow.removeListener(_onFlow);
    if (widget.flow == null) _flow.dispose();
    for (final c in [_name, _username, _password, _confirm, _second, _wipe, _step2]) {
      c.dispose();
    }
    super.dispose();
  }

  RegisterDraft get _draft => RegisterDraft(
        name: _name.text,
        username: _username.text,
        password: _password.text,
        confirm: _confirm.text,
        second: _second.text,
        wipe: _wipe.text,
        wipeEnabled: _wipeEnabled,
      );

  String? _err(Map<String, String> errors, String f) => (_submitted || _touched.contains(f)) ? errors[f] : null;

  Widget _field(String f, TextEditingController c, String label, Map<String, String> errors, {bool secret = false, String? hint, TextInputAction? action, ValueChanged<String>? onSubmitted, List<String>? autofill}) {
    final enabled = !_flow.loading;
    void touch(String _) => setState(() => _touched.add(f));
    if (secret) {
      return Focus(
        onFocusChange: (focused) {
          if (!focused) touch('');
        },
        child: PasswordField(controller: c, label: label, hint: hint, enabled: enabled, errorText: _err(errors, f), textInputAction: action, onSubmitted: onSubmitted),
      );
    }
    return Focus(
      onFocusChange: (focused) {
        if (!focused) touch('');
      },
      child: TextField(
        controller: c,
        enabled: enabled,
        textInputAction: action ?? TextInputAction.next,
        autofillHints: autofill,
        decoration: InputDecoration(labelText: label, hintText: hint, errorText: _err(errors, f)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    switch (_flow.stage) {
      case RegisterStage.account:
        return _account();
      case RegisterStage.security:
        return _security();
      case RegisterStage.recoveryCode:
        return PopScope(
          canPop: false, // leaving would lose the only copy of the code
          child: AuthScaffold(
            title: 'Lưu mã khôi phục',
            onBack: () {},
            children: [RecoveryCodeDisplay(code: _flow.recoveryCode ?? '', onConfirmed: _flow.recoveryConfirmed)],
          ),
        );
      case RegisterStage.secondPassword:
        return _verify();
    }
  }

  Widget _errorBox() => _flow.error == null ? const SizedBox.shrink() : NoticeBox(_flow.error!);

  Widget _account() {
    final errors = registerAccountErrors(_draft);
    return AuthScaffold(
      title: 'Tạo tài khoản',
      subtitle: 'Dùng thử miễn phí 30 ngày',
      children: [
        Text('Bước 1/2 · Thông tin tài khoản', style: TextStyle(color: context.mutedColor, fontSize: 13)),
        const SizedBox(height: 10),
        _errorBox(),
        _field('name', _name, 'Tên hiển thị', errors, autofill: const [AutofillHints.name]),
        const SizedBox(height: 12),
        _field('username', _username, 'Tên đăng nhập', errors, hint: 'Ít nhất 3 ký tự', autofill: const [AutofillHints.newUsername]),
        const SizedBox(height: 12),
        _field('password', _password, 'Mật khẩu', errors, secret: true, hint: 'Tuỳ bạn đặt', action: TextInputAction.next),
        const SizedBox(height: 12),
        _field('confirmPassword', _confirm, 'Nhập lại mật khẩu', errors, secret: true, action: TextInputAction.done, onSubmitted: (_) => _next()),
        const SizedBox(height: 20),
        AppButton(label: 'Tiếp tục', variant: AppButtonVariant.primary, onPressed: _flow.loading ? null : _next),
        const SizedBox(height: 4),
        AppButton(label: 'Đã có tài khoản? Đăng nhập', variant: AppButtonVariant.ghost, onPressed: () => context.canPop() ? context.pop() : context.go('/login')),
      ],
    );
  }

  void _next() {
    setState(() => _submitted = true);
    if (_flow.nextFromAccount(_draft)) setState(() => _submitted = false);
  }

  Widget _security() {
    final d = _draft;
    final errors = registerSecurityErrors(d);
    return AuthScaffold(
      title: 'Bảo vệ tài khoản',
      subtitle: 'Dùng thử miễn phí 30 ngày',
      onBack: _flow.loading ? () {} : () {
        setState(() => _submitted = false);
        _flow.backToAccount();
      },
      children: [
        Text('Bước 2/2 · Bảo mật', style: TextStyle(color: context.mutedColor, fontSize: 13)),
        const SizedBox(height: 10),
        _errorBox(),
        _field('secondPassword', _second, 'Mật khẩu lớp hai (bắt buộc)', errors, secret: true, hint: 'Tuỳ bạn đặt'),
        Padding(padding: const EdgeInsets.only(top: 4, left: 4), child: Text('Dùng ở bước đăng nhập thứ hai.', style: TextStyle(color: context.mutedColor, fontSize: 12.5))),
        const SizedBox(height: 14),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _flow.loading
              ? null
              : () => setState(() {
                    _wipeEnabled = !_wipeEnabled;
                    if (!_wipeEnabled) _wipe.clear();
                  }),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Mật khẩu xoá dữ liệu', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('Không bắt buộc · Có thể đặt sau trong Tài khoản', style: TextStyle(fontSize: 12.5)),
                ]),
              ),
              SvgIcon(_wipeEnabled ? AppSvg.close : AppSvg.plus),
            ]),
          ),
        ),
        if (_wipeEnabled) ...[
          const SizedBox(height: 10),
          Text('Nếu nhập mật khẩu này khi đăng nhập, ứng dụng sẽ mở bước xác nhận xoá dữ liệu vĩnh viễn. Mật khẩu này phải khác hai mật khẩu trên.', style: TextStyle(color: context.mutedColor, fontSize: 13)),
          const SizedBox(height: 10),
          _field('wipePassword', _wipe, 'Mật khẩu xoá dữ liệu', errors, secret: true, hint: 'Tuỳ bạn đặt', action: TextInputAction.done, onSubmitted: (_) => _create()),
        ],
        const SizedBox(height: 20),
        AppButton(label: 'Tạo tài khoản', variant: AppButtonVariant.primary, loading: _flow.loading, onPressed: _flow.loading ? null : _create),
        AppButton(label: 'Quay lại', variant: AppButtonVariant.ghost, onPressed: _flow.loading
              ? null
              : () {
                  setState(() => _submitted = false);
                  _flow.backToAccount();
                }),
      ],
    );
  }

  Future<void> _create() async {
    setState(() => _submitted = true);
    await _flow.submit(_draft);
    if (!mounted) return;
    if (_flow.stage == RegisterStage.recoveryCode || _flow.stage == RegisterStage.secondPassword) {
      // The account exists now: no password needs to stay in memory except the second one for the final check.
      _password.clear();
      _confirm.clear();
      _second.clear();
      _wipe.clear();
      setState(() => _submitted = false);
    }
  }

  Widget _verify() {
    return PopScope(
      canPop: false,
      child: AuthScaffold(
        title: 'Xác minh lần cuối',
        onBack: () {},
        children: [
          const Text('Nhập lại mật khẩu lớp hai vừa đặt để hoàn tất đăng ký.'),
          const SizedBox(height: 12),
          _errorBox(),
          PasswordField(controller: _step2, label: 'Mật khẩu lớp hai', enabled: !_flow.loading, autofocus: true, onSubmitted: (_) => _flow.submitStep2(_step2.text)),
          const SizedBox(height: 20),
          AppButton(label: 'Hoàn tất', variant: AppButtonVariant.primary, loading: _flow.loading, onPressed: _flow.loading ? null : () => _flow.submitStep2(_step2.text)),
        ],
      ),
    );
  }
}
