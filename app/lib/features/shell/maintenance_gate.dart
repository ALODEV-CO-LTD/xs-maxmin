import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/theme.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/svg_icon.dart';

/// Maintenance mode for customers: while Admin has it on, [ApiClient.maintenance] holds the message and this full-screen
/// notice replaces the app (the server refuses a customer's requests with 503 anyway). It re-checks the notice feed by
/// itself every [recheck], and "Thử lại" checks at once; "Đăng xuất" lets the person leave the account. Signed-out screens
/// (login) are never covered, so an admin can still sign in.
class MaintenanceGate extends StatefulWidget {
  const MaintenanceGate({super.key, required this.api, required this.auth, required this.child, this.recheck = const Duration(seconds: 20)});
  final ApiClient api;
  final AuthStore auth;
  final Widget child;
  final Duration recheck;
  @override
  State<MaintenanceGate> createState() => _MaintenanceGateState();
}

class _MaintenanceGateState extends State<MaintenanceGate> {
  Timer? _timer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.api.maintenance.addListener(_onChange);
    widget.auth.addListener(_onAuth);
    _onChange();
  }

  @override
  void dispose() {
    widget.api.maintenance.removeListener(_onChange);
    widget.auth.removeListener(_onAuth);
    _timer?.cancel();
    super.dispose();
  }

  /// Signing out forgets the notice (the next account, an admin for instance, starts clean).
  void _onAuth() {
    if (!widget.auth.signedIn || widget.auth.isAdmin) widget.api.maintenance.value = null;
  }

  void _onChange() {
    if (widget.api.maintenance.value != null) {
      _timer ??= Timer.periodic(widget.recheck, (_) => _check());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Asks the notice feed (open during maintenance) whether it is over; the server's answer clears or keeps the notice.
  Future<void> _check() async {
    if (_busy || !widget.auth.signedIn) return;
    setState(() => _busy = true);
    try {
      widget.api.retryNow();
      final res = await widget.api.get('/announcements');
      widget.api.applyNotices(res is Map ? res['maintenance'] : null);
    } catch (_) {/* still down or offline: keep the notice */} finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([widget.api.maintenance, widget.auth]),
        builder: (context, _) {
          final message = widget.api.maintenance.value;
          if (message == null || !widget.auth.signedIn || widget.auth.isAdmin) return widget.child;
          return Stack(children: [
            widget.child,
            Positioned.fill(
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          SvgIcon(AppSvg.warning, size: 56, color: Brand.warning),
                          const SizedBox(height: 18),
                          const Text('Hệ thống đang bảo trì', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Text(message, key: const Key('maintenance-message'), textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: context.mutedColor, height: 1.4)),
                          const SizedBox(height: 24),
                          AppButton(label: 'Thử lại', variant: AppButtonVariant.primary, block: true, loading: _busy, onPressed: _busy ? null : _check),
                          const SizedBox(height: 8),
                          AppButton(label: 'Đăng xuất', variant: AppButtonVariant.ghost, block: true, onPressed: widget.auth.logout),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
}
