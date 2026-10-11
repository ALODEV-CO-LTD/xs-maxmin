import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth_store.dart';

/// Admin accounts are managed on the web; the app is for customer accounts.
class AdminNoticeScreen extends StatelessWidget {
  const AdminNoticeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 56),
                const SizedBox(height: 12),
                const Text('Tài khoản Admin dùng trên bản web', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Ứng dụng này dành cho tài khoản khách hàng. Hãy đăng nhập Admin trên trình duyệt.', textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton(onPressed: () => context.read<AuthStore>().clear(), child: const Text('Đăng xuất')),
              ]),
            ),
          ),
        ),
      );
}
