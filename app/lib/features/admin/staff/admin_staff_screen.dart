import 'package:flutter/material.dart';
import '../../../core/widgets/svg_icon.dart';
import 'package:provider/provider.dart';

import '../../../core/admin_session.dart';
import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../users/admin_users_logic.dart';
import '../users/admin_users_widgets.dart';
import 'admin_staff_logic.dart';
import '../../../core/widgets/app_button.dart';

/// Admin - Phân quyền: staff admin accounts and their rights (root Admin only). Body only.
class AdminStaffScreen extends StatelessWidget {
  const AdminStaffScreen({super.key});
  @override
  Widget build(BuildContext context) => StaffBody(api: context.read<ApiClient>(), isRoot: context.watch<AdminSession>().isRoot);
}

class StaffBody extends StatefulWidget {
  const StaffBody({super.key, required this.api, required this.isRoot});
  final ApiClient api;
  final bool isRoot;
  @override
  State<StaffBody> createState() => _StaffBodyState();
}

class _StaffBodyState extends State<StaffBody> {
  StaffData _data = const StaffData({}, []);
  bool _loading = true;
  String? _error, _notice, _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.isRoot) {
      setState(() => _loading = false);
      return;
    }
    try {
      final res = await widget.api.get('/admin/staff') as Map<String, dynamic>;
      if (mounted) setState(() { _data = StaffData.fromJson(res); _error = null; });
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _patch(StaffAccount s, Map<String, dynamic> body, String ok) async {
    setState(() { _busyId = s.id; _error = null; _notice = null; });
    try {
      await widget.api.patch('/admin/staff/${s.id}', body);
      if (mounted) setState(() => _notice = ok);
      await _load();
      return true;
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _toggleLock(StaffAccount s) async {
    if (!s.locked && !await adminConfirm(context, title: 'Khoá tài khoản', message: 'Khoá "${s.username}" và đăng xuất mọi thiết bị của nhân viên?', confirmText: 'Khoá', danger: true)) return;
    await _patch(s, {'locked': !s.locked}, s.locked ? 'Đã mở khoá ${s.name}' : 'Đã khoá ${s.name} và đăng xuất mọi thiết bị');
  }

  Future<void> _remove(StaffAccount s) async {
    if (!await adminConfirm(context, title: 'Xoá tài khoản thứ cấp', message: 'Xoá tài khoản "${s.username}"? Nhân viên sẽ không đăng nhập được nữa.', confirmText: 'Xoá', danger: true)) return;
    setState(() { _busyId = s.id; _error = null; _notice = null; });
    try {
      await widget.api.delete('/admin/staff/${s.id}');
      if (mounted) setState(() => _notice = 'Đã xoá ${s.username}');
      await _load();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _create() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => StaffCreatePage(api: widget.api, catalog: _data.catalog)));
    if (ok == true) {
      setState(() => _notice = 'Đã tạo tài khoản. Hãy gửi tên đăng nhập và mật khẩu cho nhân viên qua kênh riêng.');
      _load();
    }
  }

  Future<void> _edit(StaffAccount s) async {
    final ok = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => StaffEditPage(api: widget.api, catalog: _data.catalog, account: s)));
    if (ok != null) {
      setState(() => _notice = ok);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isRoot) return const EmptyState('Chỉ Admin gốc được quản lý phân quyền.');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Tạo tài khoản thứ cấp cho nhân viên và tích chọn những quyền họ được dùng. Quyền thay đổi có hiệu lực ngay ở lần thao tác kế tiếp.', style: TextStyle(fontSize: 13, color: context.mutedColor)),
        const SizedBox(height: 12),
        if (_error != null) AdminBanner(_error!),
        if (_notice != null) AdminBanner(_notice!, error: false),
        if (_loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else ...[
          Row(children: [
            Expanded(child: Text('Tài khoản thứ cấp (${_data.staff.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            AppButton(label: 'Tạo', variant: AppButtonVariant.primary, icon: Icons.add, onPressed: _create),
          ]),
          const SizedBox(height: 12),
          if (_data.staff.isEmpty && _error == null) const EmptyState('Chưa có tài khoản thứ cấp nào.'),
          for (final s in _data.staff) _card(context, s),
        ],
      ]),
    );
  }

  Widget _card(BuildContext context, StaffAccount s) {
    final busy = _busyId == s.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${s.name} (${s.username})', style: const TextStyle(fontWeight: FontWeight.w600))),
            if (s.locked) AdminChip('Đang khoá', color: context.badColor),
          ]),
          const SizedBox(height: 4),
          Text('${s.permissions.length} quyền · tạo ${fmtDate(s.createdAt)}', style: TextStyle(fontSize: 13, color: context.mutedColor)),
          if (s.permissions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(s.permissions.join(', '), style: TextStyle(fontSize: 12, color: context.mutedColor)),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            AppButton(label: 'Sửa', svg: AppSvg.edit, variant: AppButtonVariant.primary, onPressed: busy ? null : () => _edit(s)),
            AppButton(label: s.locked ? 'Mở khoá' : 'Khoá', variant: AppButtonVariant.secondary, onPressed: busy ? null : () => _toggleLock(s)),
            AppButton(label: 'Xoá', svg: AppSvg.delete, variant: AppButtonVariant.danger, onPressed: busy ? null : () => _remove(s)),
          ]),
        ]),
      ),
    );
  }
}

/// Checkbox list of every right (labels from the server catalog) with quick presets.
class PermissionPicker extends StatelessWidget {
  const PermissionPicker({super.key, required this.catalog, required this.selected, required this.onChanged});
  final Map<String, String> catalog;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Chọn nhanh:', style: TextStyle(color: context.mutedColor)),
        for (final p in staffPresets) ActionChip(label: Text(p.label), onPressed: () => onChanged([...p.keys.where(catalog.containsKey)])),
        ActionChip(label: const Text('Bỏ chọn'), onPressed: () => onChanged([])),
      ]),
      for (final e in catalog.entries)
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: selected.contains(e.key),
          title: Text(e.value, style: const TextStyle(fontSize: 14)),
          onChanged: (v) => onChanged(v == true ? [...selected, e.key] : selected.where((k) => k != e.key).toList()),
        ),
    ]);
  }
}

class StaffCreatePage extends StatefulWidget {
  const StaffCreatePage({super.key, required this.api, required this.catalog});
  final ApiClient api;
  final Map<String, String> catalog;
  @override
  State<StaffCreatePage> createState() => _StaffCreateState();
}

class _StaffCreateState extends State<StaffCreatePage> {
  final _name = TextEditingController(), _user = TextEditingController(), _pw = TextEditingController();
  List<String> _perms = [];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final problem = validateNewStaff(name: _name.text, username: _user.text, password: _pw.text, permissions: _perms);
    if (problem != null) return setState(() => _error = problem);
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.post('/admin/staff', {'name': _name.text.trim(), 'username': _user.text.trim(), 'password': _pw.text, 'permissions': _perms});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Tạo tài khoản thứ cấp')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null) AdminBanner(_error!),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tên hiển thị')),
          const SizedBox(height: 12),
          TextField(controller: _user, autocorrect: false, decoration: const InputDecoration(labelText: 'Tên đăng nhập')),
          const SizedBox(height: 12),
          TextField(controller: _pw, autocorrect: false, enableSuggestions: false, decoration: const InputDecoration(labelText: 'Mật khẩu (từ 8 ký tự)')),
          const SizedBox(height: 16),
          PermissionPicker(catalog: widget.catalog, selected: _perms, onChanged: (v) => setState(() => _perms = v)),
          const SizedBox(height: 16),
          AppButton(label: 'Tạo tài khoản', variant: AppButtonVariant.primary, loading: _busy, onPressed: _busy ? null : _submit),
        ]),
      );
}

class StaffEditPage extends StatefulWidget {
  const StaffEditPage({super.key, required this.api, required this.catalog, required this.account});
  final ApiClient api;
  final Map<String, String> catalog;
  final StaffAccount account;
  @override
  State<StaffEditPage> createState() => _StaffEditState();
}

class _StaffEditState extends State<StaffEditPage> {
  late List<String> _perms = [...widget.account.permissions];
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _send(Map<String, dynamic> body, String ok) async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.patch('/admin/staff/${widget.account.id}', body);
      if (mounted) Navigator.of(context).pop(ok);
    } on ApiError catch (e) {
      if (mounted) setState(() { _error = e.message; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    final changed = !samePermissions(_perms, a.permissions);
    return Scaffold(
      appBar: AppBar(title: Text(a.name)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('@${a.username}', style: TextStyle(color: context.mutedColor)),
        const SizedBox(height: 12),
        if (_error != null) AdminBanner(_error!),
        PermissionPicker(catalog: widget.catalog, selected: _perms, onChanged: (v) => setState(() => _perms = v)),
        const SizedBox(height: 8),
        AppButton(label: 'Lưu quyền', variant: AppButtonVariant.primary, onPressed: _busy || !changed || _perms.isEmpty ? null : () => _send({'permissions': _perms}, 'Đã lưu quyền của ${a.name}')),
        const Divider(height: 32),
        const Text('Đặt lại mật khẩu', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(controller: _pw, autocorrect: false, enableSuggestions: false, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Mật khẩu mới (từ 8 ký tự)')),
        const SizedBox(height: 8),
        AppButton(label: 'Đặt mật khẩu mới', variant: AppButtonVariant.secondary, onPressed: _busy || _pw.text.isEmpty ? null : () => _send({'newPassword': _pw.text}, 'Đã đặt mật khẩu mới cho ${a.name} (đã đăng xuất mọi thiết bị)')),
      ]),
    );
  }
}
