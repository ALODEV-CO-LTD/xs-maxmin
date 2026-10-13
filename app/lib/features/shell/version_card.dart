import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_version.dart';
import '../../core/config.dart';
import '../../core/theme.dart';

/// "Phiên bản ứng dụng" card: the installed version (e.g. `1.4.5 (11)`), whether a newer one exists (compared with the
/// Admin's setting from the public `GET /app-version`, see A17), a manual "Kiểm tra cập nhật" button and the download
/// link when there is one. It checks once when it appears; a failed check never raises an error, it just says so.
/// Shown in Tài khoản (customer) and in the Admin menu.
class VersionCard extends StatefulWidget {
  const VersionCard({super.key, this.api, this.currentVersion = AppConfig.appVersionName, this.display = AppConfig.appVersion});

  /// Defaults to the app's [ApiClient] from Provider; tests pass a fake.
  final ApiClient? api;
  final String currentVersion;
  final String display;

  @override
  State<VersionCard> createState() => _VersionCardState();
}

enum _Phase { checking, upToDate, optional, required, notSet, failed }

class _VersionCardState extends State<VersionCard> {
  _Phase _phase = _Phase.checking;
  AppVersionInfo _info = const AppVersionInfo();
  DateTime? _checkedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    setState(() => _phase = _Phase.checking);
    try {
      final api = widget.api ?? context.read<ApiClient>();
      final res = await api.get('/app-version');
      final info = AppVersionInfo.fromJson(Map<String, dynamic>.from(res as Map));
      final need = updateNeed(widget.currentVersion, info);
      if (!mounted) return;
      setState(() {
        _info = info;
        _checkedAt = DateTime.now();
        _phase = need == UpdateNeed.required
            ? _Phase.required
            : need == UpdateNeed.optional
                ? _Phase.optional
                : (info.latest.isEmpty ? _Phase.notSet : _Phase.upToDate);
      });
    } catch (_) {
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _download() async {
    final url = Uri.tryParse(_info.downloadUrl);
    if (url == null || url.scheme != 'https') return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (String text, Color color, IconData icon) = switch (_phase) {
      _Phase.checking => ('Đang kiểm tra cập nhật...', cs.onSurface.withValues(alpha: 0.6), Icons.sync),
      _Phase.upToDate => ('Bạn đang dùng phiên bản mới nhất.', context.okColor, Icons.check_circle_outline),
      _Phase.optional => ('Có phiên bản mới ${_info.latest}.', cs.primary, Icons.system_update_alt),
      _Phase.required => ('Phiên bản này không còn được hỗ trợ, cần cập nhật lên ${_info.latest.isEmpty ? _info.min : _info.latest}.', context.badColor, Icons.error_outline),
      _Phase.notSet => ('Quản trị viên chưa đăng thông tin phiên bản mới.', cs.onSurface.withValues(alpha: 0.6), Icons.info_outline),
      _Phase.failed => ('Không kiểm tra được (không có mạng hoặc máy chủ không phản hồi).', cs.onSurface.withValues(alpha: 0.6), Icons.cloud_off_outlined),
    };
    final canDownload = _info.downloadUrl.isNotEmpty && (_phase == _Phase.optional || _phase == _Phase.required);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.phone_android, size: 20),
            const SizedBox(width: 8),
            const Text('Phiên bản ứng dụng', style: TextStyle(fontWeight: FontWeight.w700)),
            const Spacer(),
            SelectableText(widget.display, key: const Key('version-text'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _phase == _Phase.checking
                ? const SizedBox(width: 18, height: 18, child: Padding(padding: EdgeInsets.all(2), child: CircularProgressIndicator(strokeWidth: 2)))
                : Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(text, key: const Key('version-status'), style: TextStyle(color: color, fontSize: 13.5))),
          ]),
          if (_phase == _Phase.optional && _info.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6, left: 26), child: Text(_info.notes, style: const TextStyle(fontSize: 13))),
          if (_checkedAt != null && _phase != _Phase.checking) Padding(padding: const EdgeInsets.only(top: 4, left: 26), child: Text('Kiểm tra lúc ${_hhmm(_checkedAt!)}', style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 4, children: [
            OutlinedButton.icon(onPressed: _phase == _Phase.checking ? null : _check, icon: const Icon(Icons.refresh, size: 18), label: const Text('Kiểm tra cập nhật')),
            if (canDownload) FilledButton.icon(onPressed: _download, icon: const Icon(Icons.download, size: 18), label: const Text('Tải bản mới')),
          ]),
        ]),
      ),
    );
  }
}

/// Small dialog with the card, for places without room for it (the Admin drawer).
Future<void> showVersionDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(child: Padding(padding: const EdgeInsets.all(8), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const VersionCard(),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))),
      ]))),
    );
