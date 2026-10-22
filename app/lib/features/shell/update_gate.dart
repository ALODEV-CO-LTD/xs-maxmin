import 'package:flutter/material.dart';
import '../../core/widgets/svg_icon.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/app_version.dart';
import '../../core/config.dart';
import '../../core/widgets/app_button.dart';

/// App version management (A17): asks the public `GET /app-version` when the app starts and every time it comes back to
/// the foreground (at most once an hour), then
///  - below the Admin's minimum version: a full-screen block until the app is updated (link opens the download page),
///  - below the newest version: a dismissible card at the bottom, remembered per version so it is not repeated.
/// Fail-open: when the server cannot be reached, or sends something that is not a version, the app just runs.
/// It sits in `MaterialApp.router`'s builder (above the Navigator), so it draws with a Stack instead of dialogs.
class UpdateGate extends StatefulWidget {
  const UpdateGate({super.key, required this.api, required this.child, this.currentVersion = AppConfig.appVersionName});
  final ApiClient api;
  final Widget child;
  final String currentVersion;
  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> with WidgetsBindingObserver {
  AppVersionInfo? _info;
  UpdateNeed _need = UpdateNeed.none;
  bool _dismissed = false;
  bool _checking = false;
  DateTime _lastCheck = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && DateTime.now().difference(_lastCheck) > const Duration(hours: 1)) _check();
  }

  static String _dismissKey(String latest) => 'update_dismissed_$latest';

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final res = await widget.api.get('/app-version');
      final info = AppVersionInfo.fromJson(Map<String, dynamic>.from(res as Map));
      var need = updateNeed(widget.currentVersion, info);
      var dismissed = false;
      if (need == UpdateNeed.optional) {
        dismissed = (await SharedPreferences.getInstance()).getBool(_dismissKey(info.latest)) ?? false;
      }
      _lastCheck = DateTime.now();
      if (!mounted) return;
      setState(() {
        _info = info;
        _need = need;
        _dismissed = dismissed;
      });
    } catch (_) {
      // offline or server error: never block the app because the check failed
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openDownload() async {
    final url = Uri.tryParse(_info?.downloadUrl ?? '');
    if (url == null || url.scheme != 'https') return;
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _later() async {
    final latest = _info?.latest ?? '';
    setState(() => _dismissed = true);
    if (latest.isNotEmpty) (await SharedPreferences.getInstance()).setBool(_dismissKey(latest), true);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Stack(children: [
      Positioned.fill(child: widget.child),
      if (info != null && _need == UpdateNeed.optional && !_dismissed) Positioned(left: 12, right: 12, bottom: 12, child: _OptionalCard(info: info, current: widget.currentVersion, onUpdate: _openDownload, onLater: _later)),
      if (info != null && _need == UpdateNeed.required) Positioned.fill(child: _RequiredScreen(info: info, current: widget.currentVersion, onUpdate: _openDownload, onRetry: _check, busy: _checking)),
    ]);
  }
}

class _OptionalCard extends StatelessWidget {
  const _OptionalCard({required this.info, required this.current, required this.onUpdate, required this.onLater});
  final AppVersionInfo info;
  final String current;
  final VoidCallback onUpdate, onLater;
  @override
  Widget build(BuildContext context) => Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Có phiên bản mới ${info.latest}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text('Bạn đang dùng $current.', style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
            if (info.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(info.notes)),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              AppButton(label: 'Để sau', variant: AppButtonVariant.ghost, onPressed: onLater),
              if (info.downloadUrl.isNotEmpty) AppButton(label: 'Cập nhật', variant: AppButtonVariant.primary, onPressed: onUpdate),
            ]),
          ]),
        ),
      );
}

class _RequiredScreen extends StatelessWidget {
  const _RequiredScreen({required this.info, required this.current, required this.onUpdate, required this.onRetry, required this.busy});
  final AppVersionInfo info;
  final String current;
  final VoidCallback onUpdate, onRetry;
  final bool busy;
  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SvgIcon(AppSvg.download, size: 56),
                const SizedBox(height: 12),
                const Text('Cần cập nhật ứng dụng', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('Bạn đang dùng phiên bản $current, đã quá cũ. Hãy cập nhật lên phiên bản ${info.latest.isEmpty ? info.min : info.latest} để tiếp tục.', textAlign: TextAlign.center),
                if (info.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(info.notes, textAlign: TextAlign.center)),
                const SizedBox(height: 18),
                if (info.downloadUrl.isNotEmpty) AppButton(label: 'Tải bản mới', variant: AppButtonVariant.primary, svg: AppSvg.download, onPressed: onUpdate) else const Text('Liên hệ quản trị viên để nhận bản mới.', textAlign: TextAlign.center),
                AppButton(label: 'Kiểm tra lại', variant: AppButtonVariant.ghost, loading: busy, onPressed: busy ? null : onRetry),
              ]),
            ),
          ),
        ),
      );
}
