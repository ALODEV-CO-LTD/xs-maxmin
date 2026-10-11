import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../friends/friends_controller.dart';
import '../friends/messaging_host.dart';

/// Bottom navigation around the five main tabs (go_router StatefulShellRoute keeps each tab's state).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final hub = MessagingScope.maybeOf(context);
    return Scaffold(
      // Each tab draws its own heading, so there is no AppBar (it only repeated the title).
      body: SafeArea(bottom: false, child: shell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.edit_note_outlined), selectedIcon: Icon(Icons.edit_note), label: 'Nhập số'),
          const NavigationDestination(icon: Icon(Icons.fact_check_outlined), selectedIcon: Icon(Icons.fact_check), label: 'Kết quả'),
          const NavigationDestination(icon: Icon(Icons.calculate_outlined), selectedIcon: Icon(Icons.calculate), label: 'Tính điểm'),
          const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Khách hàng'),
          NavigationDestination(
            icon: _UnreadBadge(hub: hub, child: const Icon(Icons.more_horiz)),
            selectedIcon: _UnreadBadge(hub: hub, child: const Icon(Icons.more_horiz)),
            label: 'Thêm',
            tooltip: 'Thêm',
          ),
        ],
      ),
    );
  }
}

/// Red count on the "Thêm" icon: unread friend messages + unseen missed calls + replies from Admin.
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
