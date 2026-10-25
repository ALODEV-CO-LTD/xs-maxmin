import 'dart:async';
import '../../core/widgets/svg_icon.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/package_events.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_button.dart';
import '../account/account_controller.dart';
import '../account/package_status.dart';
import '../friends/messaging_host.dart';
import 'guide_dialog.dart';

/// Tổng quan: how long the customer's package still runs (or that it ran out), with a way to renew it.
class PackageCard extends StatefulWidget {
  const PackageCard({super.key, this.controller, this.onRenew, this.onGuide, this.onSupport});

  /// Test hook: a controller that already holds the profile.
  final AccountController? controller;

  /// Test hook: what "Gia hạn" does (default: opens Tài khoản > Gói & Thanh toán).
  final VoidCallback? onRenew;

  /// Test hooks: what the two shortcuts on the right do (default: the guide dialog / the Hỗ trợ từ Admin page).
  final VoidCallback? onGuide, onSupport;

  @override
  State<PackageCard> createState() => _PackageCardState();
}

class _PackageCardState extends State<PackageCard> with WidgetsBindingObserver {
  late final AccountController _ctl = widget.controller ?? AccountController(context.read<ApiClient>());
  Timer? _tick;
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.controller == null) _ctl.load(silent: true);
    PackageEvents.instance.addListener(_onPackageEvent);
    // The remaining time moves every minute; the profile is read again every ten minutes (a payment confirmed by Admin shows up).
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      if (++_ticks % 10 == 0 && widget.controller == null) _ctl.load(silent: true);
      setState(() {});
    });
  }

  void _onPackageEvent() {
    if (widget.controller == null) _ctl.load(silent: true); // Admin decided a payment request: show the new expiry
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.controller == null) _ctl.load(silent: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PackageEvents.instance.removeListener(_onPackageEvent);
    _tick?.cancel();
    if (widget.controller == null) _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _ctl,
      builder: (context, _) {
        final me = _ctl.me;
        // The two shortcuts stay on the card whatever the state of the package (also before the profile is read, or offline).
        final st = me == null || me.isAdmin ? null : packageStatus(me, DateTime.now());
        final color = switch (st?.level) {
          null => context.mutedColor,
          PackageLevel.ok => context.okColor,
          PackageLevel.soon => Brand.warning,
          PackageLevel.expired || PackageLevel.none => context.badColor,
        };
        final icon = switch (st?.level) {
          null => AppSvg.info,
          PackageLevel.ok => AppSvg.verified,
          PackageLevel.soon => AppSvg.clock,
          PackageLevel.expired || PackageLevel.none => AppSvg.alertCircle,
        };
        final needsAction = st?.needsAction ?? false;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // The two shortcuts: side by side, above the card (also before the profile is read, or offline).
          Row(children: [
            Expanded(child: _CardLink(key: const Key('overview-guide'), label: 'Hướng dẫn sử dụng', icon: AppSvg.guide, color: context.okColor, onTap: widget.onGuide ?? () => showGuideDialog(context))),
            const SizedBox(width: 10),
            Expanded(child: _SupportLink(onTap: widget.onSupport ?? () => context.push('/support'))),
          ]),
          const SizedBox(height: 10),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color.withValues(alpha: needsAction ? 0.7 : 0.35))),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  SvgIcon(icon, color: color, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Số ngày sử dụng', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
                      Text(st?.headline ?? 'Chưa tải được', key: const Key('package-headline'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                      if (st != null && st.detail.isNotEmpty) Text(st.detail, style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
                    ]),
                  ),
                ]),
                if (st != null && st.level == PackageLevel.soon) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Sắp hết hạn, hãy gia hạn để không bị gián đoạn.', style: TextStyle(fontSize: 12.5, color: color))),
                if (st != null && (st.level == PackageLevel.expired || st.level == PackageLevel.none))
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('Không nhập được số liệu mới cho tới khi gia hạn.', style: TextStyle(fontSize: 12.5, color: color))),
                if (needsAction)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: AppButton(label: st!.level == PackageLevel.none ? 'Đăng ký' : 'Gia hạn', variant: AppButtonVariant.primary, onPressed: widget.onRenew ?? () => context.go('/account?tab=packages')),
                  ),
              ]),
            ),
          ),
        ]);
      },
    );
  }
}

/// An outlined shortcut (icon, one-line label, chevron) that fills the width it is given: two of them share a row above the card.
class _CardLink extends StatelessWidget {
  const _CardLink({super.key, required this.label, required this.icon, required this.color, required this.onTap, this.badge = 0});
  final String label;
  final AppSvg icon;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: color.withValues(alpha: 0.7))),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 4, 10),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Badge(isLabelVisible: badge > 0, label: Text(badge > 9 ? '9+' : '$badge'), child: SvgIcon(icon, color: color, size: 18)),
            const SizedBox(width: 6),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color, height: 1.2))),
            const SizedBox(width: 1),
            SvgIcon(AppSvg.chevronRight, color: color, size: 12),
          ]),
        ),
      ),
    );
  }
}

/// "Liên hệ admin" with the count of unread replies of Admin.
class _SupportLink extends StatelessWidget {
  const _SupportLink({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final hub = MessagingScope.maybeOf(context);
    Widget link(int n) => _CardLink(key: const Key('overview-support'), label: 'Liên hệ admin', icon: AppSvg.support, color: context.badColor, badge: n, onTap: onTap);
    if (hub == null) return link(0);
    return ListenableBuilder(listenable: hub, builder: (_, _) => link(hub.supportUnread));
  }
}
