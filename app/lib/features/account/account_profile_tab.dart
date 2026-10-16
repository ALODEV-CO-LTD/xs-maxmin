import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import 'account_controller.dart';
import 'account_widgets.dart';
import 'auth_flows.dart' show errorText;
import 'me_profile.dart';
import 'password_rules.dart';
import '../shell/version_card.dart';
import '../support/support_page.dart';

/// Hồ sơ: personal info (edit), package info, password dialogs, Mã ID kết bạn, logout.
class AccountProfileTab extends StatelessWidget {
  const AccountProfileTab({super.key, required this.ctl});
  final AccountController ctl;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (!context.read<AuthStore>().isAdmin) ...[const SupportEntryCard(), const SizedBox(height: 14)],
        _ProfileCard(ctl: ctl),
        const SizedBox(height: 14),
        const _CustomerCodesCard(),
      ]);
}

class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.ctl});
  final AccountController ctl;
  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _editing = false;
  bool _saving = false;
  String? _error;
  String? _success;
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _current = TextEditingController();

  MeProfile get _me => widget.ctl.me!;

  @override
  void initState() {
    super.initState();
    _username.addListener(() => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _current.dispose();
    super.dispose();
  }

  bool get _usernameChanged => _username.text.trim() != _me.username;

  void _startEdit() {
    _name.text = _me.name;
    _username.text = _me.username;
    _current.clear();
    setState(() {
      _error = null;
      _success = null;
      _editing = true;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim(), username = _username.text.trim();
    setState(() {
      _error = null;
      _success = null;
    });
    if (name.isEmpty) return setState(() => _error = 'Vui lòng nhập tên hiển thị');
    if (username.length < 3) return setState(() => _error = 'Tên đăng nhập phải có ít nhất 3 ký tự');
    if (_usernameChanged && _current.text.isEmpty) return setState(() => _error = 'Nhập mật khẩu hiện tại để đổi tên đăng nhập');
    setState(() => _saving = true);
    try {
      final res = await context.read<ApiClient>().patch('/me', {'name': name, 'username': username, if (_usernameChanged) 'currentPassword': _current.text});
      _current.clear();
      widget.ctl.setFromJson(res);
      if (mounted) {
        setState(() {
          _editing = false;
          _success = 'Đã cập nhật thông tin tài khoản';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final auth = context.read<AuthStore>();
    if (await confirmDialog(context, title: 'Đăng xuất', message: 'Bạn có chắc muốn đăng xuất?', confirmText: 'Đăng xuất')) auth.clear();
  }

  void _dialog(Widget d) => showDialog<void>(context: context, builder: (_) => d).then((_) => widget.ctl.load(silent: true));

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final api = context.read<ApiClient>();
    final ok = context.okColor, bad = context.badColor;
    return SectionCard(
      title: 'Thông tin cá nhân',
      trailing: _editing ? null : OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)), onPressed: _startEdit, child: const Text('Sửa')),
      children: [
        if (_success != null) NoticeBox(_success!, kind: NoticeKind.success),
        if (_editing) ...[
          if (_error != null) NoticeBox(_error!),
          TextField(controller: _name, enabled: !_saving, decoration: const InputDecoration(labelText: 'Tên')),
          const SizedBox(height: 12),
          TextField(controller: _username, enabled: !_saving, autocorrect: false, decoration: const InputDecoration(labelText: 'Tên đăng nhập')),
          if (_usernameChanged) ...[
            const SizedBox(height: 12),
            PasswordField(controller: _current, label: 'Mật khẩu hiện tại', enabled: !_saving),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Đang lưu...' : 'Lưu'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: _saving ? null : () => setState(() { _editing = false; _error = null; }), child: const Text('Huỷ'))),
          ]),
        ] else ...[
          InfoRow('Tên', value: me.name),
          InfoRow('Tên đăng nhập', value: me.username),
        ],
        if (!me.isAdmin && me.packageType != null) ...[
          InfoRow('Gói dịch vụ', child: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.end, children: [
            Text(me.packageLabel ?? me.packageType!, style: const TextStyle(fontWeight: FontWeight.w600)),
            StatusChip(me.packageActive ? 'Đang hoạt động' : 'Hết hạn', color: me.packageActive ? ok : bad),
          ])),
          InfoRow('Hạn mức nhập', value: me.unlimited ? 'Không giới hạn số lượng nhập' : 'Đã dùng ${formatNumber(me.quotaUsed)} / ${formatNumber(me.quotaTotal)}'),
          InfoRow('Hết hạn', value: viDateTimeLocal(me.packageExpiresAt)),
        ],
        InfoRow('Mật khẩu lớp hai', child: StatusChip(me.hasSecondPassword ? 'Đã bật' : 'Chưa đặt', color: me.hasSecondPassword ? ok : null)),
        InfoRow('Mật khẩu xoá dữ liệu', child: StatusChip(me.hasWipePassword ? 'Đã bật' : 'Chưa đặt', color: me.hasWipePassword ? ok : null)),
        const SizedBox(height: 10),
        OutlinedButton.icon(icon: const Icon(Icons.key, size: 18), label: const Text('Đổi mật khẩu'), onPressed: () => _dialog(_passwordDialog(api))),
        const SizedBox(height: 8),
        OutlinedButton.icon(icon: const Icon(Icons.shield_outlined, size: 18), label: Text(me.hasSecondPassword ? 'Đổi mật khẩu lớp hai' : 'Đặt mật khẩu lớp hai'), onPressed: () => _dialog(_secondDialog(api, me))),
        const SizedBox(height: 8),
        OutlinedButton.icon(icon: const Icon(Icons.delete_sweep_outlined, size: 18), label: Text(me.hasWipePassword ? 'Đổi mật khẩu xoá dữ liệu' : 'Đặt mật khẩu xoá dữ liệu'), onPressed: () => _wipeFlow(api, me)),
        const SizedBox(height: 14),
        const VersionCard(),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(icon: const Icon(Icons.logout, size: 18), label: const Text('Đăng xuất'), onPressed: _logout),
      ],
    );
  }

  Future<void> _wipeFlow(ApiClient api, MeProfile me) async {
    final verb = me.hasWipePassword ? 'đổi' : 'đặt';
    final ok = await confirmDialog(context,
        title: 'Xác nhận $verb mật khẩu',
        message: 'Xác nhận $verb mật khẩu xoá dữ liệu? Nếu bạn đăng nhập bằng mật khẩu này, hệ thống sẽ hỏi xác nhận xoá toàn bộ dữ liệu.');
    if (!ok || !mounted) return;
    _dialog(SecretFormDialog(
      title: 'Mật khẩu xoá dữ liệu',
      description:
          'Nếu bạn đăng nhập bằng mật khẩu này thay vì mật khẩu chính, hệ thống sẽ hỏi xác nhận xoá dữ liệu thay vì đăng nhập bình thường. Mật khẩu này phải khác mật khẩu lớp hai. ${me.hasWipePassword ? 'Chỉ có thể đổi, không thể tắt.' : 'Tuỳ chọn, bỏ trống nếu không cần.'}',
      labels: const ['Mật khẩu hiện tại', 'Mật khẩu xoá dữ liệu'],
      submitLabel: me.hasWipePassword ? 'Đổi mật khẩu xoá dữ liệu' : 'Đặt mật khẩu xoá dữ liệu',
      validate: (v) => v.any((s) => s.isEmpty) ? 'Vui lòng nhập đầy đủ thông tin' : passwordProblem(v[1]),
      submit: (v) async {
        await api.post('/me/wipe-password', {'currentPassword': v[0], 'wipePassword': v[1]});
        return 'Đã $verb mật khẩu xoá dữ liệu';
      },
    ));
  }
}

Widget _passwordDialog(ApiClient api) => SecretFormDialog(
      title: 'Đổi mật khẩu đăng nhập',
      labels: const ['Mật khẩu hiện tại', 'Mật khẩu mới', 'Nhập lại mật khẩu mới'],
      submitLabel: 'Đổi mật khẩu',
      validate: changePasswordProblem,
      submit: (v) async {
        await api.post('/me/password', {'currentPassword': v[0], 'newPassword': v[1]});
        return 'Đã đổi mật khẩu thành công';
      },
    );

Widget _secondDialog(ApiClient api, MeProfile me) => SecretFormDialog(
      title: 'Mật khẩu lớp hai',
      description: 'Lớp bảo mật thứ hai khi đăng nhập. ${me.hasSecondPassword ? 'Chỉ có thể đổi, không thể tắt.' : ''}',
      labels: const ['Mật khẩu hiện tại', 'Mật khẩu lớp hai mới'],
      submitLabel: me.hasSecondPassword ? 'Đổi mật khẩu lớp hai' : 'Đặt mật khẩu lớp hai',
      validate: (v) => v.any((s) => s.isEmpty) ? 'Vui lòng nhập đầy đủ thông tin' : passwordProblem(v[1]),
      submit: (v) async {
        await api.post('/me/second-password', {'currentPassword': v[0], 'secondPassword': v[1]});
        return 'Đã cập nhật mật khẩu lớp hai';
      },
    );

/// Client-side check of the "Đổi mật khẩu" form: [current, new, confirm].
String? changePasswordProblem(List<String> v) {
  if (v[0].isEmpty || v[1].isEmpty) return 'Vui lòng nhập đầy đủ thông tin';
  if (v[1] != v[2]) return 'Mật khẩu mới nhập lại không khớp';
  return passwordProblem(v[1]);
}

// ------------------------------------------------------------------ Mã ID

class _CustomerCodesCard extends StatefulWidget {
  const _CustomerCodesCard();
  @override
  State<_CustomerCodesCard> createState() => _CustomerCodesCardState();
}

class _CustomerCodesCardState extends State<_CustomerCodesCard> {
  List<Map<String, dynamic>> _codes = [];
  int _max = 5;
  bool _loading = true;
  bool _creating = false;
  String? _error;
  final _digits = TextEditingController();
  final _label = TextEditingController();
  String? _editingId;
  final _labelDraft = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _digits.dispose();
    _label.dispose();
    _labelDraft.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<ApiClient>().get('/me/customer-codes') as Map;
      if (!mounted) return;
      setState(() {
        _codes = [for (final c in (res['codes'] as List? ?? const [])) (c as Map).cast<String, dynamic>()];
        if (res['maxCodes'] is num) _max = (res['maxCodes'] as num).toInt();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không tải được danh sách mã ID');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final digits = _digits.text.trim(), label = _label.text.trim();
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final c = await context.read<ApiClient>().post('/me/customer-codes', {if (digits.isNotEmpty) 'code': digits, if (label.isNotEmpty) 'label': label}) as Map;
      if (!mounted) return;
      setState(() {
        _codes.insert(0, c.cast<String, dynamic>());
        _digits.clear();
        _label.clear();
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không tạo được mã ID');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final api = context.read<ApiClient>();
    final ok = await confirmDialog(context, title: 'Xoá mã ID', message: 'Xoá mã ID "${c['code']}"? Người khác sẽ không thể dùng mã này để kết bạn với bạn nữa.', confirmText: 'Xoá', danger: true);
    if (!ok) return;
    try {
      await api.delete('/me/customer-codes/${c['id']}');
      if (mounted) setState(() => _codes.removeWhere((x) => x['id'] == c['id']));
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không xoá được mã ID');
    }
  }

  Future<void> _saveLabel(Map<String, dynamic> c) async {
    try {
      final res = await context.read<ApiClient>().patch('/me/customer-codes/${c['id']}', {'label': _labelDraft.text}) as Map;
      if (mounted) {
        setState(() {
          c['label'] = res['label'];
          _editingId = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không đổi được nhãn');
    }
  }

  @override
  Widget build(BuildContext context) {
    final atLimit = _codes.length >= _max;
    return SectionCard(title: 'Mã ID kết bạn', children: [
      Text(
        'Tạo mã và gửi cho người khác để họ kết bạn với bạn. Bạn có thể tự chọn dãy số (6-12 chữ số, không trùng, không quá dễ đoán như 123456) hoặc để trống để hệ thống tạo ngẫu nhiên. Tối đa $_max mã (${_codes.length}/$_max đã dùng).',
        style: TextStyle(color: context.mutedColor, fontSize: 13),
      ),
      const SizedBox(height: 12),
      if (_error != null) NoticeBox(_error!),
      TextField(
        controller: _digits,
        enabled: !_creating,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(12)],
        decoration: const InputDecoration(labelText: 'Dãy số (tuỳ chọn)'),
      ),
      const SizedBox(height: 10),
      TextField(controller: _label, enabled: !_creating, maxLength: 40, decoration: const InputDecoration(labelText: 'Nhãn (tuỳ chọn)', counterText: '')),
      const SizedBox(height: 10),
      FilledButton.tonalIcon(icon: const Icon(Icons.add, size: 18), onPressed: _creating || atLimit ? null : _create, label: Text(_creating ? 'Đang tạo...' : 'Tạo mã mới')),
      if (atLimit) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Đã đạt giới hạn, hãy xoá bớt một mã để tạo mã mới.', style: TextStyle(color: context.mutedColor, fontSize: 13))),
      const SizedBox(height: 8),
      if (_loading)
        const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
      else if (_codes.isEmpty)
        Padding(padding: const EdgeInsets.only(top: 8), child: Text('Chưa có mã nào.', style: TextStyle(color: context.mutedColor)))
      else
        for (final c in _codes) _codeTile(c),
    ]);
  }

  Widget _codeTile(Map<String, dynamic> c) {
    final editing = _editingId == c['id'];
    final label = c['label'] as String?;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText('${c['code']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1)),
              if (label != null && label.isNotEmpty) Text(label, style: TextStyle(color: context.mutedColor, fontSize: 13)),
            ]),
          ),
          IconButton(tooltip: 'Nhãn', icon: const Icon(Icons.label_outline), onPressed: () => setState(() { _editingId = c['id'] as String?; _labelDraft.text = label ?? ''; })),
          IconButton(tooltip: 'Sao chép', icon: const Icon(Icons.copy), onPressed: () => copyText(context, '${c['code']}')),
          IconButton(tooltip: 'Xoá', icon: Icon(Icons.delete_outline, color: context.badColor), onPressed: () => _delete(c)),
        ]),
        if (editing)
          Padding(
            padding: const EdgeInsets.only(right: 8, top: 4),
            child: Row(children: [
              Expanded(child: TextField(controller: _labelDraft, autofocus: true, maxLength: 40, decoration: const InputDecoration(hintText: 'Nhãn (để trống để xoá)', counterText: ''))),
              const SizedBox(width: 8),
              FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(0, 44)), onPressed: () => _saveLabel(c), child: const Text('Lưu')),
              IconButton(onPressed: () => setState(() => _editingId = null), icon: const Icon(Icons.close)),
            ]),
          ),
      ]),
    );
  }
}
