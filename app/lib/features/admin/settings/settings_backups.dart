import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/theme.dart';
import '../payments/payments_logic.dart' show viDateTime;
import 'settings_logic.dart';
import 'settings_ui.dart';
import '../../../core/widgets/app_button.dart';

class BackupItem {
  const BackupItem(this.name, this.size, this.createdAt);
  final String name;
  final int size;
  final String? createdAt;
  factory BackupItem.fromJson(Map<String, dynamic> j) => BackupItem('${j['name'] ?? ''}', j['size'] is num ? (j['size'] as num).toInt() : 0, j['createdAt'] as String?);
}

/// Sao lưu: create a snapshot, list, download (ApiClient.blob -> temp file -> share sheet).
class BackupsSection extends StatefulWidget {
  const BackupsSection({super.key});
  @override
  State<BackupsSection> createState() => _BackupsSectionState();
}

class _BackupsSectionState extends State<BackupsSection> {
  bool _loading = true, _creating = false;
  String? _error, _message, _downloading;
  List<BackupItem> _items = [];

  ApiClient get _api => context.read<ApiClient>();

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _api.get('/admin/backups');
      if (!mounted) return;
      setState(
        () => _items = [
          for (final b in ((res as Map)['backups'] as List? ?? const []))
            if (b is Map<String, dynamic>) BackupItem.fromJson(b),
        ],
      );
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không tải được danh sách'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
      _message = null;
    });
    try {
      final b = BackupItem.fromJson(Map<String, dynamic>.from(await _api.post('/admin/backups') as Map));
      if (!mounted) return;
      setState(() {
        _items = [b, ..._items];
        _message = 'Đã tạo bản sao lưu ${b.name}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không tạo được bản sao lưu'));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _download(BackupItem b) async {
    setState(() {
      _downloading = b.name;
      _error = null;
    });
    try {
      final bytes = await _api.blob('/admin/backups/${Uri.encodeComponent(b.name)}');
      await saveAndShareFile(bytes, b.name, mime: 'application/octet-stream');
    } catch (e) {
      if (mounted) setState(() => _error = errText(e, 'Không tải được tệp'));
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tạo bản sao lưu cơ sở dữ liệu (lưu trên máy chủ) và tải về máy. Bản sao lưu chứa dữ liệu của mọi người dùng, hãy cất giữ cẩn thận.',
          style: TextStyle(color: context.mutedColor, fontSize: 13),
        ),
        const SizedBox(height: 10),
        if (_error != null) Banner2(_error!),
        if (_message != null) Banner2(_message!, error: false),
        AppButton(label: 'Tạo bản sao lưu mới', variant: AppButtonVariant.primary, loading: _creating, onPressed: _creating ? null : _create),
        const SizedBox(height: 12),
        if (_loading)
          const Placeholder2('', busy: true)
        else if (_items.isEmpty)
          const Placeholder2('Chưa có bản sao lưu nào.')
        else
          for (final b in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  title: Text(b.name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text('${viDateTime(b.createdAt)} · ${formatBackupSize(b.size)}'),
                  trailing: _downloading == b.name
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(tooltip: 'Tải về', icon: const Icon(Icons.download), onPressed: _downloading != null ? null : () => _download(b)),
                ),
              ),
            ),
      ],
    );
  }
}
