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

/// Tổng quan: how long the customer's package still runs (or that it ran out), with a way to renew it.
class PackageCard extends StatefulWidget {
  const PackageCard({super.key, this.controller, this.onRenew});

  /// Test hook: a controller that already holds the profile.
  final AccountController? controller;

  /// Test hook: what "Gia hạn" does (default: opens Tài khoản > Gói & Thanh toán).
  final VoidCallback? onRenew;

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
        if (me == null) return const SizedBox.shrink(); // not read yet (or no network): the rest of the screen is not held back
        if (me.isAdmin) return const SizedBox.shrink();
        final st = packageStatus(me, DateTime.now());
        final color = switch (st.level) {
          PackageLevel.ok => context.okColor,
          PackageLevel.soon => Brand.warning,
          PackageLevel.expired || PackageLevel.none => context.badColor,
        };
        final icon = switch (st.level) {
          PackageLevel.ok => AppSvg.verified,
          PackageLevel.soon => AppSvg.clock,
          PackageLevel.expired || PackageLevel.none => AppSvg.alertCircle,
        };
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: color.withValues(alpha: st.needsAction ? 0.7 : 0.35))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(children: [
              SvgIcon(icon, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Gói sử dụng', style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
                  Text(st.headline, key: const Key('package-headline'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
                  if (st.detail.isNotEmpty) Text(st.detail, style: TextStyle(fontSize: 12.5, color: context.mutedColor)),
                  if (st.level == PackageLevel.soon) Text('Sắp hết hạn, hãy gia hạn để không bị gián đoạn.', style: TextStyle(fontSize: 12.5, color: color)),
                  if (st.level == PackageLevel.expired || st.level == PackageLevel.none) Text('Không nhập được số liệu mới cho tới khi gia hạn.', style: TextStyle(fontSize: 12.5, color: color)),
                ]),
              ),
              if (st.needsAction)
                AppButton(label: st.level == PackageLevel.none ? 'Đăng ký' : 'Gia hạn', variant: AppButtonVariant.primary, onPressed: widget.onRenew ?? () => context.go('/account?tab=packages')),
            ]),
          ),
        );
      },
    );
  }
}
