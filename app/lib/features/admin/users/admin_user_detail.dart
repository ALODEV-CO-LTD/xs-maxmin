import 'package:flutter/material.dart';
import '../../../core/widgets/svg_icon.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import 'admin_users_logic.dart';
import 'admin_users_widgets.dart';
import '../../../core/widgets/app_button.dart';

/// Customer detail page: profile, devices, lock/unlock, reset password, recovery code, clear lockouts, delete.
class AdminUserDetailPage extends StatefulWidget {
  const AdminUserDetailPage({super.key, required this.api, required this.rights, required this.userId, this.initial, this.onChanged, this.onDeleted});
  final ApiClient api;
  final UserRights rights;
  final String userId;
  final Subscriber? initial;
  final ValueChanged<Subscriber>? onChanged;
  final VoidCallback? onDeleted;
  @override
  State<AdminUserDetailPage> createState() => _State();
}

class _State extends State<AdminUserDetailPage> {
  Subscriber? _user;
  bool _loading = true, _busy = false;
  String? _error, _actionError, _note, _sessionsError;
  List<DeviceSession> _sessions = const [];
  String? _lastPassword, _lastCode;
  bool _resetOpen = false;
  final _pw = TextEditingController();

  String get _base => '/admin/users/${widget.userId}';

  @override
  void initState() {
    super.initState();
    _user = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await widget.api.get(_base) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _user = Subscriber.fromJson(res);
        _error = null;
      });
      await _loadSessions();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSessions() async {
    if (!widget.rights.lock) return;
    try {
      final res = await widget.api.get('$_base/sessions') as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _sessions = [for (final s in (res['sessions'] as List? ?? const [])) DeviceSession.fromJson((s as Map).cast<String, dynamic>())];
        _sessionsError = null;
      });
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _sessions = const [];
          _sessionsError = e.message;
        });
      }
    }
  }

  /// Runs a mutating call with the shared busy / error handling.
  Future<void> _run(Future<void> Function() f, String fallback) async {
    setState(() {
      _busy = true;
      _actionError = null;
      _note = null;
    });
    try {
      await f();
    } on ApiError catch (e) {
      if (mounted) setState(() => _actionError = e.message.isEmpty ? fallback : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _apply(Map<String, dynamic> updated) {
    final u = Subscriber.fromJson(updated);
    setState(() => _user = u);
    widget.onChanged?.call(u);
  }

  Future<void> _toggleLock() async {
    final u = _user!;
    final locking = !u.locked;
    if (!await adminConfirm(context,
        title: locking ? 'Khoá tài khoản' : 'Mở khoá tài khoản',
        message: locking ? 'Khoá tài khoản "${u.name}"? Khách hàng sẽ không đăng nhập được và bị đăng xuất mọi thiết bị.' : 'Mở khoá tài khoản "${u.name}"?',
        confirmText: locking ? 'Khoá' : 'Mở khoá',
        danger: locking)) {
      return;
    }
    await _run(() async {
      _apply(await widget.api.patch(_base, {'locked': locking}) as Map<String, dynamic>);
      await _loadSessions();
    }, 'Không thể cập nhật');
  }

  Future<void> _support(bool code) async {
    final ok = await adminConfirm(context,
        title: code ? 'Cấp lại mã khôi phục' : 'Gỡ khoá đăng nhập',
        message: code ? 'Mã khôi phục cũ sẽ không còn dùng được. Mã mới chỉ hiện một lần.' : 'Gỡ mọi khoá đăng nhập, xác thực và khôi phục của tài khoản này?',
        confirmText: code ? 'Cấp lại' : 'Gỡ khoá');
    if (!ok) return;
    await _run(() async {
      final res = await widget.api.patch(_base, code ? {'reissueRecoveryCode': true} : {'clearLockouts': true}) as Map<String, dynamic>;
      _apply(res);
      setState(() {
        if (res['recoveryCode'] != null) {
          _lastCode = '${res['recoveryCode']}';
          _lastPassword = null;
        }
        _note = code ? 'Đã cấp mã khôi phục mới (mã cũ không còn dùng được).' : 'Đã gỡ mọi khoá đăng nhập/xác thực/khôi phục của tài khoản.';
      });
    }, 'Không thể thực hiện');
  }

  Future<void> _resetPassword() async {
    final pw = _pw.text.trim();
    if (pw.isEmpty) return;
    await _run(() async {
      final res = await widget.api.patch(_base, {'newPassword': pw}) as Map<String, dynamic>;
      _apply(res);
      setState(() {
        _lastPassword = pw;
        _lastCode = res['recoveryCode'] == null ? null : '${res['recoveryCode']}';
        _pw.clear();
        _resetOpen = false;
      });
      await _loadSessions();
    }, 'Không thể đặt lại mật khẩu');
  }

  Future<void> _revoke(String? sid) async {
    if (sid == null && !await adminConfirm(context, title: 'Thu hồi tất cả', message: 'Đăng xuất khách hàng khỏi mọi thiết bị?', confirmText: 'Thu hồi', danger: true)) return;
    try {
      await widget.api.delete(sid == null ? '$_base/sessions' : '$_base/sessions/$sid');
      await _loadSessions();
    } on ApiError catch (e) {
      if (mounted) setState(() => _sessionsError = e.message);
    }
  }

  Future<void> _delete() async {
    final u = _user!;
    final typed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Xoá tài khoản'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Xoá vĩnh viễn tài khoản "${u.name}" và toàn bộ dữ liệu liên quan? Không thể hoàn tác.'),
            const SizedBox(height: 12),
            Text('Gõ "${u.username}" để xác nhận:', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            TextField(controller: typed, autofocus: true, autocorrect: false, onChanged: (_) => set(() {})),
          ]),
          actions: [
            AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: () => Navigator.pop(c, false)),
            AppButton(label: 'Xoá', svg: AppSvg.delete, variant: AppButtonVariant.danger, onPressed: deleteConfirmed(typed.text, u.username) ? () => Navigator.pop(c, true) : null),
          ],
        ),
      ),
    );
    typed.dispose();
    if (ok != true || !mounted) return;
    await _run(() async {
      await widget.api.delete(_base);
      widget.onDeleted?.call();
      if (mounted) Navigator.of(context).pop();
    }, 'Không thể xoá tài khoản');
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    return Scaffold(
      appBar: AppBar(title: Text(u?.name ?? 'Khách hàng')),
      body: _loading && u == null
          ? const Center(child: CircularProgressIndicator())
          : u == null
              ? ListView(padding: const EdgeInsets.all(16), children: [AdminBanner(_error ?? 'Không thể tải chi tiết')])
              : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(16), children: _content(context, u))),
    );
  }

  List<Widget> _content(BuildContext context, Subscriber u) {
    final r = widget.rights;
    return [
      Text('@${u.username}', style: TextStyle(color: context.mutedColor)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        AdminChip(u.active ? 'Gói hoạt động' : 'Gói hết hạn', color: u.active ? context.okColor : Brand.warning),
        AdminChip(u.locked ? 'Tài khoản đã khoá' : 'Tài khoản đang mở', color: u.locked ? context.badColor : context.okColor),
      ]),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            _row('Gói', u.packageLabel),
            _row('Hết hạn', fmtDateTime(u.expiresAt)),
            if (r.lock) _row('Thiết bị đăng nhập', '${_sessions.length}'),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      if (_actionError != null) AdminBanner(_actionError!),
      if (_note != null) AdminBanner(_note!, error: false),
      if (_lastPassword != null || _lastCode != null)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: context.okColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10), border: Border.all(color: context.okColor.withValues(alpha: 0.5))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (_lastPassword != null) SecretRow(label: 'Mật khẩu mới', value: _lastPassword!),
            if (_lastCode != null) SecretRow(label: 'Mã khôi phục mới', value: _lastCode!),
            Text(
              'Gửi cho khách hàng qua kênh riêng ngay bây giờ: các giá trị này không xem lại được. Mọi thiết bị của khách đã bị đăng xuất và mã khôi phục cũ không còn dùng được.',
              style: TextStyle(fontSize: 12, color: context.mutedColor),
            ),
            Align(alignment: Alignment.centerRight, child: AppButton(label: 'Đã gửi, ẩn', variant: AppButtonVariant.ghost, onPressed: () => setState(() => _lastPassword = _lastCode = null))),
          ]),
        ),
      if (_resetOpen)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Mật khẩu mới cho tài khoản này', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(controller: _pw, autocorrect: false, enableSuggestions: false, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Mật khẩu mới')),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                AppButton(label: 'Tạo ngẫu nhiên', variant: AppButtonVariant.secondary, onPressed: _busy ? null : () => setState(() => _pw.text = generatePassword())),
                AppButton(label: 'Lưu', variant: AppButtonVariant.primary, onPressed: _busy || _pw.text.trim().isEmpty ? null : _resetPassword),
                AppButton(label: 'Huỷ', variant: AppButtonVariant.ghost, onPressed: _busy ? null : () => setState(() {_resetOpen = false; _pw.clear();})),
              ]),
            ]),
          ),
        ),
      if (r.lock) ...[const SizedBox(height: 12), _sessionsCard(context)],
      const SizedBox(height: 16),
      if (r.lock) _btn(u.locked ? 'Mở khoá tài khoản' : 'Khoá tài khoản', _toggleLock),
      if (r.recovery && !_resetOpen) _btn('Đặt lại mật khẩu', () => setState(() {_resetOpen = true; _lastPassword = null;})),
      if (r.recovery) _btn('Cấp lại mã khôi phục', () => _support(true)),
      if (r.recovery) _btn('Gỡ khoá đăng nhập', () => _support(false)),
      if (r.delete)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: AppButton(label: 'Xoá tài khoản', svg: AppSvg.delete, variant: AppButtonVariant.danger, onPressed: _busy ? null : _delete),
        ),
    ];
  }

  Widget _btn(String t, VoidCallback f) => Padding(padding: const EdgeInsets.only(bottom: 8), child: AppButton(label: t, variant: AppButtonVariant.secondary, onPressed: _busy ? null : f));

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: context.mutedColor))),
          Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _sessionsCard(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Thiết bị đang đăng nhập (${_sessions.length})', style: const TextStyle(fontWeight: FontWeight.w600))),
              if (_sessions.isNotEmpty) AppButton(label: 'Thu hồi tất cả', variant: AppButtonVariant.ghost, onPressed: () => _revoke(null)),
            ]),
            if (_sessionsError != null) AdminBanner(_sessionsError!),
            if (_sessions.isEmpty && _sessionsError == null) Text('Không có phiên nào', style: TextStyle(color: context.mutedColor)),
            for (final s in _sessions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s.label} · IP ${s.ip ?? '-'}'),
                      Text('Gần nhất: ${fmtDateTime(s.lastSeen)}', style: TextStyle(fontSize: 12, color: context.mutedColor)),
                    ]),
                  ),
                  AppButton(label: 'Thu hồi', variant: AppButtonVariant.ghost, onPressed: () => _revoke(s.id)),
                ]),
              ),
          ]),
        ),
      );
}
