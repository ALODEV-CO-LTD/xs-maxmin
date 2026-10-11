import 'package:flutter/material.dart';
import '../../core/widgets/logout.dart';
import 'package:go_router/go_router.dart';

import '../friends/friends_controller.dart';
import '../friends/messaging_host.dart';

/// The "Thêm" tab: the screens that do not fit the bottom bar.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final hub = MessagingScope.maybeOf(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tile(context, Icons.chat_bubble_outline, 'Bạn bè', 'Nhắn tin, gọi thoại, mã ID kết bạn', '/friends', badgeOf: hub),
        _tile(context, Icons.person_outline, 'Tài khoản', 'Hồ sơ, mật khẩu, thiết bị, gói & thanh toán', '/account'),
        Card(
          child: ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text('Đăng xuất', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.error)),
            onTap: () => confirmLogout(context),
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String sub, String route, {FriendsController? badgeOf}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub),
            trailing: badgeOf == null
                ? const Icon(Icons.chevron_right)
                : ListenableBuilder(
                    listenable: Listenable.merge([badgeOf, badgeOf.chat]),
                    builder: (context, _) {
                      final n = badgeOf.unreadTotal;
                      return Row(mainAxisSize: MainAxisSize.min, children: [
                        if (n > 0) Badge(label: Text(n > 99 ? '99+' : '$n')),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right),
                      ]);
                    },
                  ),
            onTap: () => context.push(route),
          ),
        ),
      );
}
