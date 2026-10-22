import 'package:flutter/material.dart';
import '../../core/widgets/svg_icon.dart';
import 'package:go_router/go_router.dart';

import '../friends/friends_controller.dart';
import '../friends/messaging_host.dart';
import 'announcement_banner.dart';

/// Bottom navigation around the five main tabs (go_router StatefulShellRoute keeps each tab's state):
/// Tổng quan | Tính toán | Bạn bè | Cấu hình | Tài khoản.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final hub = MessagingScope.maybeOf(context);
    return Scaffold(
      // Each tab draws its own heading (or tab bar), so the shell has no AppBar.
      // Admin notices sit above the tabs (they take their own height, the tab keeps the rest).
      body: SafeArea(bottom: false, child: Column(children: [const AnnouncementBanner(), Expanded(child: shell)])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: SvgIcon(AppSvg.chart), selectedIcon: SvgIcon(AppSvg.chart), label: 'Tổng quan'),
          const NavigationDestination(icon: SvgIcon(AppSvg.calculator), selectedIcon: SvgIcon(AppSvg.calculator), label: 'Tính toán'),
          NavigationDestination(
            icon: _UnreadBadge(hub: hub, child: const SvgIcon(AppSvg.friends)),
            selectedIcon: _UnreadBadge(hub: hub, child: const SvgIcon(AppSvg.friends)),
            label: 'Bạn bè',
          ),
          const NavigationDestination(icon: SvgIcon(AppSvg.config), label: 'Cấu hình'),
          const NavigationDestination(icon: SvgIcon(AppSvg.account), selectedIcon: SvgIcon(AppSvg.account), label: 'Tài khoản'),
        ],
      ),
    );
  }
}

/// Red count on the "Bạn bè" icon: unread friend messages + unseen missed calls + replies from Admin + pending friend requests.
class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.hub, required this.child});
  final FriendsController? hub;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final h = hub;
    if (h == null) return child;
    return ListenableBuilder(
      listenable: Listenable.merge([h, h.chat]),
      builder: (context, _) {
        final n = h.unreadTotal;
        return Badge(isLabelVisible: n > 0, label: Text(n > 99 ? '99+' : '$n'), child: child);
      },
    );
  }
}
