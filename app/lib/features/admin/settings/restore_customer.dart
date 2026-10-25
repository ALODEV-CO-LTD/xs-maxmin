import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../../../core/widgets/app_button.dart';
import '../payments/payments_logic.dart' show viDateTime;
import '../trash/trash_logic.dart' show countsSummary;
import 'settings_logic.dart';
import 'settings_ui.dart';

/// A backup the Admin can restore one customer from: made in the app, or the daily one of the server.
class BackupSource {
  const BackupSource(this.id, this.source, this.name, this.size, this.createdAt);
  final String id, source, name;
  final int size;
  final String? createdAt;
  factory BackupSource.fromJson(Map<String, dynamic> j) =>
      BackupSource('${j['id']}', '${j['source']}', '${j['name']}', j['size'] is num ? (j['size'] as num).toInt() : 0, j['createdAt'] as String?);
  String get sourceLabel => source == 'cron' ? 'Tự động hằng ngày' : 'Tạo trong app';
}

/// A customer of a backup with what was kept then and what exists now.
class BackupCustomer {
  const BackupCustomer(this.id, this.username, this.name, this.inBackup, this.now);
  final String id, username, name;
  final Map<String, int> inBackup;
  final Map<String, int>? now; // null: the account no longer exists
  factory BackupCustomer.fromJson(Map<String, dynamic> j) {
    Map<String, int> m(Object? v) => {for (final e in ((v as Map?) ?? const {}).entries) '${e.key}': e.value is num ? (e.value as num).toInt() : 0};
    return BackupCustomer('${j['id']}', '${j['username']}', '${j['name'] ?? ''}', m(j['inBackup']), j['now'] == null ? null : m(j['now']));
  }
  String get title => name.isEmpty ? username : '$username ($name)';
}

/// "Khôi phục dữ liệu một khách": for a customer who deleted numbers by mistake. Pick a backup, then the customer, then how.
class RestoreCustomerSection extends StatefulWidget {
  const RestoreCustomerSection({super.key, required this.sources});
  final List<BackupSource> sources;
  @override
  State<RestoreCustomerSection> createState() => _RestoreCustomerSectionState();
}

class _RestoreCustomerSectionState extends State<RestoreCustomerSection> {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 18),
      const Text('Khôi phục dữ liệu một khách', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        'Khi khách lỡ xoá số liệu và nhờ bạn: chọn một bản sao lưu, rồi chọn khách. Chỉ dữ liệu của khách đó được đụng tới (số liệu, khách hàng, kết quả, mẫu cú pháp, lịch xoá); người khác giữ nguyên. Chỉ lấy lại được những gì đã có trong bản sao lưu.',
        style: TextStyle(color: context.mutedColor, fontSize: 13),
      ),
      const SizedBox(height: 8),
      if (widget.sources.isEmpty)
        const Placeholder2('Chưa có bản sao lưu nào.')
      else
        for (final b in widget.sources)
          Card(
            key: ValueKey('restore-${b.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(b.name, style: const TextStyle(fontSize: 14)),
              subtitle: Text('${b.sourceLabel} · ${viDateTime(b.createdAt)} · ${formatBackupSize(b.size)}'),
              trailing: AppButton(label: 'Khôi phục', variant: AppButtonVariant.ghost, onPressed: () => showRestoreCustomer(context, b)),
            ),
          ),
    ]);
  }
}

Future<void> showRestoreCustomer(BuildContext context, BackupSource b) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => Provider<ApiClient>.value(value: context.read<ApiClient>(), child: RestoreCustomerSheet(backup: b)),
    );

/// The sheet: customers of the chosen backup (searchable) -> counts then / now -> mode -> restore.
class RestoreCustomerSheet extends StatefulWidget {
  const RestoreCustomerSheet({super.key, required this.backup});
  final BackupSource backup;
  @override
  State<RestoreCustomerSheet> createState() => _RestoreCustomerSheetState();
}

class _RestoreCustomerSheetState extends State<RestoreCustomerSheet> {
  bool _loading = true, _working = false;
  String? _error, _result;
  List<BackupCustomer> _customers = [];
  BackupCustomer? _picked;
  bool _replace = false;
  final _search = TextEditingController();
  final _confirm = TextEditingController();

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await _api.get('/admin/backups/users?backup=${Uri.encodeQueryComponent(widget.backup.id)}') as Map;
      if (!mounted) return;
      setState(() => _customers = [for (final u in (res['users'] as List? ?? const [])) BackupCustomer.fromJson((u as Map).cast<String, dynamic>())]);
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không đọc được bản sao lưu này'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _canRestore => _picked != null && _picked!.now != null && !_working && (!_replace || _confirm.text.trim().toLowerCase() == _picked!.username.toLowerCase());

  Future<void> _restore() async {
    final c = _picked!;
    setState(() {
      _working = true;
      _error = null;
      _result = null;
    });
    try {
      final res = await _api.post('/admin/backups/restore-user', {'backup': widget.backup.id, 'userId': c.id, 'mode': _replace ? 'replace' : 'merge'}) as Map;
      final written = {for (final e in ((res['written'] as Map?) ?? const {}).entries) '${e.key}': e.value is num ? (e.value as num).toInt() : 0};
      if (!mounted) return;
      setState(() => _result = 'Đã khôi phục cho ${c.title}: ${countsSummary(written).isEmpty ? 'không có dòng nào cần thêm' : 'đã ghi ${countsSummary(written)}'}. Đã tạo thêm bản sao lưu an toàn ${res['safetyBackup']} trước khi làm.');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không khôi phục được'));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final shown = [for (final c in _customers) if (q.isEmpty || c.title.toLowerCase().contains(q)) c];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Khôi phục dữ liệu một khách', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${widget.backup.sourceLabel} · ${viDateTime(widget.backup.createdAt)}', style: TextStyle(color: context.mutedColor, fontSize: 13)),
          const SizedBox(height: 10),
          if (_error != null) Banner2(_error!),
          if (_result != null) Banner2(_result!, error: false),
          if (_loading)
            const Placeholder2('', busy: true)
          else if (_picked == null) ...[
            TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Tìm khách (tên đăng nhập hoặc tên)')),
            const SizedBox(height: 8),
            if (shown.isEmpty) const Placeholder2('Không có khách nào khớp trong bản sao lưu này.'),
            for (final c in shown)
              ListTile(
                key: ValueKey('customer-${c.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(c.title),
                subtitle: Text(c.now == null ? 'Tài khoản đã bị xoá (dùng Thùng rác)' : 'Lúc đó: ${countsSummary(c.inBackup).isEmpty ? 'chưa có dữ liệu' : countsSummary(c.inBackup)}', style: const TextStyle(fontSize: 12.5)),
                onTap: () => setState(() {
                  _picked = c;
                  _result = null;
                  _error = null;
                }),
              ),
          ] else ...[
            Text(_picked!.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _line('Trong bản sao lưu', countsSummary(_picked!.inBackup)),
            _line('Hiện tại', _picked!.now == null ? 'Tài khoản không còn' : countsSummary(_picked!.now!)),
            const SizedBox(height: 10),
            RadioGroup<bool>(
              groupValue: _replace,
              onChanged: (v) => setState(() => _replace = v ?? false),
              child: Column(children: [
                RadioListTile<bool>(key: const ValueKey('mode-merge'), contentPadding: EdgeInsets.zero, value: false, title: const Text('Thêm lại phần còn thiếu (khuyên dùng)'), subtitle: const Text('Không ghi đè, không nhân đôi; dữ liệu khách nhập sau bản sao lưu được giữ.')),
                RadioListTile<bool>(key: const ValueKey('mode-replace'), contentPadding: EdgeInsets.zero, value: true, title: const Text('Thay toàn bộ bằng bản sao lưu'), subtitle: const Text('Xoá dữ liệu hiện tại của khách này rồi ghi lại như bản sao lưu: những gì khách nhập sau đó sẽ mất.')),
              ]),
            ),
            if (_replace) ...[
              const SizedBox(height: 6),
              TextField(controller: _confirm, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: 'Gõ "${_picked!.username}" để xác nhận')),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: AppButton(label: 'Chọn khách khác', variant: AppButtonVariant.secondary, onPressed: _working ? null : () => setState(() => _picked = null))),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: AppButton(label: _replace ? 'Thay thế dữ liệu' : 'Khôi phục', variant: _replace ? AppButtonVariant.danger : AppButtonVariant.primary, loading: _working, onPressed: _canRestore ? _restore : null)),
            ]),
            const SizedBox(height: 6),
            Text('Trước khi khôi phục, hệ thống tự tạo một bản sao lưu mới nên việc này cũng quay lại được.', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
          ],
        ]),
      ),
    );
  }

  Widget _line(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 130, child: Text(k, style: TextStyle(color: context.mutedColor, fontSize: 13))),
          Expanded(child: Text(v.isEmpty ? 'chưa có dữ liệu' : v, style: const TextStyle(fontSize: 13))),
        ]),
      );
}
