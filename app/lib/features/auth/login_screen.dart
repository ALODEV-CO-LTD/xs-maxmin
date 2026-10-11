import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/config.dart';
import '../../core/theme.dart';

enum _Stage { credentials, secondPassword, wipeConfirm, wipeDone }

/// Sign in, all the stages `POST /auth/login` can return (same flow as frontend LoginView.vue):
/// done -> token; `second_password_required` -> `/auth/step2`; `wipe_confirmation_required` -> `/auth/confirm-wipe`.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _second = TextEditingController();
  _Stage _stage = _Stage.credentials;
  String _pending = '';
  String _wipeToken = '';
  bool _wipeAck = false;
  bool _busy = false;
  bool _showPass = false;
  String? _error;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _run(Future<dynamic> Function(ApiClient api) call) async {
    final api = context.read<ApiClient>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await call(api);
      await _handle(res as Map<String, dynamic>? ?? {});
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handle(Map<String, dynamic> res) async {
    final auth = context.read<AuthStore>();
    if (res['stage'] == 'done' || res['token'] != null) {
      await auth.login(res['token'] as String, res['role'] as String?);
      return; // the router redirects away from /login
    }
    if (res['stage'] == 'second_password_required') {
      setState(() {
        _pending = res['pendingToken'] as String;
        _second.clear();
        _stage = _Stage.secondPassword;
      });
    } else if (res['stage'] == 'wipe_confirmation_required') {
      setState(() {
        _wipeToken = res['wipeToken'] as String;
        _wipeAck = false;
        _stage = _Stage.wipeConfirm;
      });
    } else {
      setState(() => _error = 'Phản hồi không xác định từ máy chủ');
    }
  }

  void _submitCredentials() {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Vui lòng nhập tên đăng nhập và mật khẩu');
      return;
    }
    _run((api) => api.post('/auth/login', {'username': _user.text.trim(), 'password': _pass.text}));
  }

  void _submitSecond() {
    if (_second.text.isEmpty) {
      setState(() => _error = 'Vui lòng nhập mật khẩu lớp hai');
      return;
    }
    _run((api) => api.post('/auth/step2', {'pendingToken': _pending, 'password': _second.text}));
  }

  Future<void> _confirmWipe() async {
    final api = context.read<ApiClient>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.post('/auth/confirm-wipe', {'wipeToken': _wipeToken});
      if (mounted) setState(() => _stage = _Stage.wipeDone);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('MAMBA', textAlign: TextAlign.center, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 4, color: Brand.gold)),
                  const SizedBox(height: 28),
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cs.error.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                      child: Text(_error!, style: TextStyle(color: cs.error)),
                    ),
                  ..._body(),
                  const SizedBox(height: 28),
                  Text('Phiên bản ${AppConfig.appVersion}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    switch (_stage) {
      case _Stage.credentials:
        return [
          const Text('Đăng nhập', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(controller: _user, enabled: !_busy, autofillHints: const [AutofillHints.username], textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Tên đăng nhập')),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            enabled: !_busy,
            obscureText: !_showPass,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _submitCredentials(),
            decoration: InputDecoration(
              labelText: 'Mật khẩu',
              suffixIcon: IconButton(icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPass = !_showPass)),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _submitCredentials, child: Text(_busy ? 'Đang đăng nhập...' : 'Đăng nhập')),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            TextButton(onPressed: () => context.push('/recover'), child: const Text('Quên mật khẩu?')),
            TextButton(onPressed: () => context.push('/register'), child: const Text('Tạo tài khoản')),
          ]),
        ];
      case _Stage.secondPassword:
        return [
          const Text('Mật khẩu lớp hai', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text('Nhập mật khẩu lớp hai để hoàn tất đăng nhập.'),
          const SizedBox(height: 14),
          TextField(controller: _second, enabled: !_busy, obscureText: true, autofocus: true, onSubmitted: (_) => _submitSecond(), decoration: const InputDecoration(labelText: 'Mật khẩu lớp hai')),
          const SizedBox(height: 18),
          FilledButton(onPressed: _busy ? null : _submitSecond, child: Text(_busy ? 'Đang xác nhận...' : 'Xác nhận')),
          TextButton(onPressed: _busy ? null : () => setState(() => _stage = _Stage.credentials), child: const Text('Quay lại')),
        ];
      case _Stage.wipeConfirm:
        return [
          const Text('Xác nhận xoá dữ liệu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Bạn vừa nhập mật khẩu xoá dữ liệu. Nếu tiếp tục, số liệu, khách hàng và các dữ liệu liên quan của tài khoản sẽ bị xoá và không thể khôi phục.'),
          CheckboxListTile(contentPadding: EdgeInsets.zero, value: _wipeAck, onChanged: (v) => setState(() => _wipeAck = v ?? false), title: const Text('Tôi hiểu và muốn xoá dữ liệu')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: _busy || !_wipeAck ? null : _confirmWipe,
            child: Text(_busy ? 'Đang xoá...' : 'Xoá dữ liệu'),
          ),
          TextButton(onPressed: _busy ? null : () => setState(() => _stage = _Stage.credentials), child: const Text('Huỷ')),
        ];
      case _Stage.wipeDone:
        return [
          const Text('Đã xoá dữ liệu', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          const Text('Dữ liệu của tài khoản đã được xoá. Bạn có thể đăng nhập lại bằng mật khẩu thường.'),
          const SizedBox(height: 14),
          FilledButton(onPressed: () => setState(() => _stage = _Stage.credentials), child: const Text('Về đăng nhập')),
        ];
    }
  }
}
