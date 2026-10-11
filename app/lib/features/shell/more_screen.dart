import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The "Thêm" tab: the screens that do not fit the bottom bar.
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _tile(context, Icons.chat_bubble_outline, 'Bạn bè', 'Nhắn tin, gọi thoại, mã ID kết bạn', '/friends'),
        _tile(context, Icons.person_outline, 'Tài khoản', 'Hồ sơ, mật khẩu, thiết bị, gói & thanh toán', '/account'),
      ],
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String sub, String route) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: ListTile(
            leading: Icon(icon),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(route),
          ),
        ),
      );
}
