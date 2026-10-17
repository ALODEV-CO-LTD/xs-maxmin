import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/admin_session.dart';
import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../payments/payments_logic.dart' show viDateTime;
import '../settings/settings_ui.dart';
import 'notices_logic.dart';
import '../../../core/widgets/app_button.dart';

/// Admin - Thông báo & bảo trì (rights announcements.manage / maintenance.manage). Body only (the shell draws the AppBar).
class AdminNoticesScreen extends StatefulWidget {
  const AdminNoticesScreen({super.key});
  @override
  State<AdminNoticesScreen> createState() => _AdminNoticesScreenState();
}

class _AdminNoticesScreenState extends State<AdminNoticesScreen> {
  late final bool _announce = context.read<AdminSession>().can('announcements.manage');
  late final bool _maintenance = context.read<AdminSession>().can('maintenance.manage');

  String? _tab;
  bool _loading = true, _posting = false, _mtSaving = false, _mtSaved = false, _mtOn = false;
  String? _error, _composeError;
  List<Announcement> _list = [];
  String _kind = 'info';
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _mtMsg = TextEditingController();

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _mtMsg.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Future.wait<dynamic>([
        _maintenance ? _api.get('/admin/maintenance') : Future.value(<String, dynamic>{}),
        _announce ? _api.get('/admin/announcements') : Future.value(<String, dynamic>{}),
      ]);
      if (!mounted) return;
      final mt = r[0] as Map? ?? {};
      final ann = r[1] as Map? ?? {};
      setState(() {
        _mtOn = mt['enabled'] == true;
        _mtMsg.text = '${mt['message'] ?? ''}';
        _list = [
          for (final a in (ann['announcements'] as List? ?? const []))
            if (a is Map<String, dynamic>) Announcement.fromJson(a),
        ];
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không tải được dữ liệu'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveMaintenance() async {
    final bad = validateMaintenanceMessage(_mtMsg.text);
    if (bad != null) {
      setState(() => _error = bad);
      return;
    }
    setState(() {
      _mtSaving = true;
      _mtSaved = false;
      _error = null;
    });
    try {
      await _api.put('/admin/maintenance', {'enabled': _mtOn, 'message': _mtMsg.text.trim()});
      if (mounted) setState(() => _mtSaved = true);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không lưu được'));
    } finally {
      if (mounted) setState(() => _mtSaving = false);
    }
  }

  Future<void> _post() async {
    final bad = validateNotice(_kind, _title.text, _body.text);
    if (bad != null) {
      setState(() => _composeError = bad);
      return;
    }
    final title = _title.text.trim();
    if (!await confirmDialog(context, title: 'Gửi thông báo', message: 'Gửi "$title" tới tất cả người dùng?', confirmText: 'Gửi')) return;
    setState(() {
      _posting = true;
      _composeError = null;
    });
    try {
      final created = await _api.post('/admin/announcements', {'kind': _kind, 'title': title, 'body': _body.text.trim()});
      if (!mounted) return;
      setState(() {
        _list = [Announcement.fromJson(created as Map<String, dynamic>), ..._list];
        _title.clear();
        _body.clear();
        _tab = 'sent';
      });
    } catch (e) {
      if (mounted) setState(() => _composeError = errText(e, 'Không gửi được thông báo'));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _toggle(Announcement a) async {
    try {
      final res = await _api.patch('/admin/announcements/${a.id}', {'active': !a.active});
      final active = res is Map ? res['active'] == true : !a.active;
      if (mounted) setState(() => _list = [for (final x in _list) x.id == a.id ? x.copyWith(active: active) : x]);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không cập nhật được'));
    }
  }

  Future<void> _remove(Announcement a) async {
    if (!await confirmDialog(context, title: 'Xoá thông báo', message: 'Xoá thông báo "${a.title}"?', confirmText: 'Xoá', danger: true)) return;
    try {
      await _api.delete('/admin/announcements/${a.id}');
      if (mounted) setState(() => _list = _list.where((x) => x.id != a.id).toList());
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không xoá được'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = noticeSections(announce: _announce, maintenance: _maintenance, sentCount: _list.length);
    if (sections.isEmpty) return const Placeholder2('Tài khoản không có quyền thông báo hay bảo trì');
    final tab = sections.any((s) => s.$1 == _tab) ? _tab! : sections.first.$1;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('Thông báo hiển thị dạng banner cho mọi người dùng đang đăng nhập.', style: TextStyle(color: context.mutedColor, fontSize: 13)),
          const SizedBox(height: 12),
          if (_error != null) Banner2(_error!),
          if (_loading)
            const Placeholder2('', busy: true)
          else ...[
            PillBar<String>(items: sections, value: tab, onChanged: (v) => setState(() => _tab = v)),
            const SizedBox(height: 12),
            if (tab == 'sent') _sent(),
            if (tab == 'compose') _compose(),
            if (tab == 'maintenance') _maintenanceCard(),
          ],
        ],
      ),
    );
  }

  Widget _sent() {
    if (_list.isEmpty) return const Placeholder2('Chưa có thông báo nào.');
    return Column(
      children: [
        for (final a in _list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Chip(label: Text(noticeKindLabel(a.kind)), visualDensity: VisualDensity.compact),
                        if (!a.active) const Chip(label: Text('Đã ẩn'), visualDensity: VisualDensity.compact),
                      ],
                    ),
                    Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (a.body.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(a.body)),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(viDateTime(a.createdAt), style: TextStyle(color: context.mutedColor, fontSize: 12)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(label: a.active ? 'Ẩn' : 'Hiện lại', variant: AppButtonVariant.secondary, onPressed: () => _toggle(a)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AppButton(label: 'Xoá', variant: AppButtonVariant.danger, onPressed: () => _remove(a)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _compose() => SectionCard(
    title: 'Gửi thông báo mới',
    children: [
      if (_composeError != null) Banner2(_composeError!),
      DropdownButtonFormField<String>(
        initialValue: _kind,
        decoration: const InputDecoration(labelText: 'Loại'),
        items: [for (final k in noticeKinds) DropdownMenuItem(value: k.$1, child: Text(k.$2))],
        onChanged: (v) => setState(() => _kind = v ?? _kind),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _title,
        maxLength: kNoticeTitleMax,
        decoration: const InputDecoration(labelText: 'Tiêu đề'),
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 4),
      TextField(
        controller: _body,
        maxLength: kNoticeBodyMax,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(labelText: 'Nội dung (tuỳ chọn)'),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: AppButton(label: 'Gửi thông báo', variant: AppButtonVariant.primary, loading: _posting, onPressed: _posting || _title.text.trim().isEmpty ? null : _post),
      ),
    ],
  );

  Widget _maintenanceCard() => SectionCard(
    title: 'Chế độ bảo trì',
    children: [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _mtOn,
        onChanged: (v) => setState(() {
          _mtOn = v;
          _mtSaved = false;
        }),
        title: const Text('Đang bảo trì'),
        subtitle: const Text('Hiện banner cảnh báo cho mọi người dùng (không chặn ai đăng nhập)'),
      ),
      TextField(
        controller: _mtMsg,
        minLines: 2,
        maxLines: 4,
        maxLength: kMaintenanceMessageMax,
        onChanged: (_) => setState(() => _mtSaved = false),
        decoration: const InputDecoration(labelText: 'Nội dung hiển thị', hintText: 'Vd: Hệ thống bảo trì từ 23:00 đến 24:00'),
      ),
      if (_mtSaved) const Banner2('Đã lưu.', error: false),
      SizedBox(
        width: double.infinity,
        child: AppButton(label: 'Lưu cấu hình bảo trì', variant: AppButtonVariant.primary, loading: _mtSaving, onPressed: _mtSaving ? null : _saveMaintenance),
      ),
    ],
  );
}
