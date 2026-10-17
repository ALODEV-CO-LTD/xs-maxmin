import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/theme.dart';
import 'account_controller.dart';
import 'account_data_tab.dart' show RecoveryCodeCard;
import 'account_widgets.dart';
import 'me_profile.dart';
import 'privacy/privacy_store.dart';
import '../../core/widgets/app_button.dart';

/// Thiết bị & riêng tư: signed-in devices (revoke), the recovery code and the privacy settings of this device.
class AccountDevicesTab extends StatelessWidget {
  const AccountDevicesTab({super.key, required this.ctl});
  final AccountController ctl;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const _SessionsCard(),
        const SizedBox(height: 14),
        // Admin accounts have no recovery code (like the web).
        if (ctl.me?.isAdmin != true) ...[RecoveryCodeCard(ctl: ctl), const SizedBox(height: 14)],
        const PrivacySettingsCard(),
      ]);
}

class _SessionsCard extends StatefulWidget {
  const _SessionsCard();
  @override
  State<_SessionsCard> createState() => _SessionsCardState();
}

class _SessionsCardState extends State<_SessionsCard> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await context.read<ApiClient>().get('/me/sessions') as Map;
      if (!mounted) return;
      setState(() {
        _sessions = [for (final s in (res['sessions'] as List? ?? const [])) (s as Map).cast<String, dynamic>()];
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không tải được danh sách thiết bị');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> s) async {
    final api = context.read<ApiClient>();
    if (!await confirmDialog(context, title: 'Đăng xuất thiết bị', message: 'Đăng xuất "${s['deviceLabel']}" khỏi tài khoản?', confirmText: 'Đăng xuất')) return;
    try {
      await api.delete('/me/sessions/${s['id']}');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không đăng xuất được thiết bị');
    }
  }

  Future<void> _revokeOthers() async {
    final api = context.read<ApiClient>();
    if (!await confirmDialog(context, title: 'Đăng xuất thiết bị khác', message: 'Đăng xuất tất cả thiết bị khác, chỉ giữ thiết bị này?', confirmText: 'Đăng xuất')) return;
    try {
      await api.delete('/me/sessions');
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Không đăng xuất được các thiết bị khác');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Thiết bị đang đăng nhập',
      trailing: _sessions.length > 1 ? AppButton(label: 'Đăng xuất thiết bị khác', variant: AppButtonVariant.ghost, onPressed: _revokeOthers) : null,
      children: [
        if (_error != null) NoticeBox(_error!),
        if (_loading)
          const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
        else if (_sessions.isEmpty)
          Text('Chưa có thông tin thiết bị (phiên đăng nhập cũ). Đăng nhập lại để theo dõi thiết bị.', style: TextStyle(color: context.mutedColor))
        else
          for (final s in _sessions)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${s['deviceLabel'] ?? 'Thiết bị'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (s['current'] == true) StatusChip('Thiết bị này', color: context.okColor),
                    ]),
                    const SizedBox(height: 2),
                    Text('Hoạt động gần nhất: ${viDateTimeLocal(s['lastSeen'] as String?, withTime: true)} · IP ${s['ip'] ?? '-'}', style: TextStyle(color: context.mutedColor, fontSize: 12.5)),
                  ]),
                ),
                if (s['current'] != true) AppButton(label: 'Đăng xuất', variant: AppButtonVariant.ghost, onPressed: () => _revoke(s)),
              ]),
            ),
      ],
    );
  }
}

/// Auto-lock after idle minutes, lock after the app was in the background, blur (when the Admin allows it).
/// Stored on this device only.
class PrivacySettingsCard extends StatelessWidget {
  const PrivacySettingsCard({super.key});

  static String idleLabel(int m) => m == 0 ? 'Tắt' : '$m phút';
  static String hideLabel(int s) => s == 0 ? 'Tắt' : s < 60 ? 'Sau $s giây' : 'Sau ${s ~/ 60} phút';

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PrivacyStore>();
    final store = context.read<PrivacyStore>();
    final idle = {...PrivacyStore.idleChoices, p.autoLockMinutes}.toList()..sort();
    final hide = {...PrivacyStore.hideChoices, p.hideLockSeconds}.toList()..sort();
    return SectionCard(title: 'Cài đặt quyền riêng tư', children: [
      Text('Áp dụng cho thiết bị này.', style: TextStyle(color: context.mutedColor, fontSize: 13)),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        key: ValueKey('idle${p.autoLockMinutes}'),
        initialValue: p.autoLockMinutes,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Tự động khoá khi không hoạt động'),
        items: [for (final m in idle) DropdownMenuItem(value: m, child: Text(idleLabel(m) + (!p.hasOwnAutoLock && m == p.autoLockMinutes && m > 0 ? ' (mặc định của hệ thống)' : '')))],
        onChanged: (v) => v == null ? null : store.setAutoLockMinutes(v),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<int>(
        key: ValueKey('hide${p.hideLockSeconds}'),
        initialValue: p.hideLockSeconds,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Khoá khi thoát ra / chuyển ứng dụng'),
        items: [for (final s in hide) DropdownMenuItem(value: s, child: Text(hideLabel(s)))],
        onChanged: (v) => v == null ? null : store.setHideLockSeconds(v),
      ),
      if (p.policy.blurOnHideEnabled)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: p.blurOnHide,
          onChanged: (v) => store.setBlurOnHide(v ?? true),
          title: const Text('Làm mờ nội dung khi ứng dụng bị ẩn hoặc ở màn hình đa nhiệm'),
        ),
      const SizedBox(height: 8),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(p.screenshotGuardOn ? Icons.verified_user_outlined : Icons.info_outline, size: 18, color: context.mutedColor),
        const SizedBox(width: 8),
        Expanded(child: Text(p.screenshotGuardOn ? 'Chặn chụp màn hình và quay màn hình đang bật (theo chính sách của hệ thống).' : 'Chặn chụp màn hình đang tắt theo chính sách của hệ thống.', style: TextStyle(color: context.mutedColor, fontSize: 13))),
      ]),
      const SizedBox(height: 8),
      Text('Khi khoá, bạn nhập lại mật khẩu (hoặc mật khẩu lớp hai) để xem dữ liệu; dữ liệu đang nhập được giữ lại.', style: TextStyle(color: context.mutedColor, fontSize: 13)),
    ]);
  }
}
