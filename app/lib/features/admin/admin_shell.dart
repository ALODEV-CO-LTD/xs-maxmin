import 'package:flutter/material.dart';
import '../../core/widgets/svg_icon.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/admin_session.dart';
import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../../core/widgets/logout.dart';
import '../../core/config.dart';
import '../shell/version_card.dart';
import 'messages/admin_messages_screen.dart';
import 'notices/admin_notices_screen.dart';
import 'payments/admin_payments_screen.dart';
import 'settings/admin_settings_screen.dart';
import 'staff/admin_staff_screen.dart';
import 'stats/admin_stats_screen.dart';
import 'trash/admin_trash_screen.dart';
import 'users/admin_users_screen.dart';
import '../../core/widgets/app_button.dart';

class _Section {
  const _Section(this.title, this.icon, this.perm, this.build, {this.root = false});
  final String title;
  final AppSvg icon;
  final Object? perm; // a right, a list of rights (any), or null = always
  final Widget Function() build;
  final bool root;
}

/// The admin area of the app: a drawer with the sections the account is allowed to open (same list and rights as the
/// web admin menu), the section's screen as the body. Admin accounts are managed here; customers use [AppShell].
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  static final _all = <_Section>[
    _Section('Tổng quan', AppSvg.chart, 'stats.view', () => const AdminStatsScreen()),
    _Section('Khách hàng', AppSvg.usersGroup, 'users.view', () => const AdminUsersScreen()),
    _Section('Thanh toán & gia hạn', AppSvg.pay, 'payments.manage', () => const AdminPaymentsScreen()),
    _Section('Phản hồi', AppSvg.feedback, 'support.messages', () => const AdminMessagesScreen()),
    _Section('Thông báo & bảo trì', AppSvg.megaphone, ['announcements.manage', 'maintenance.manage'], () => const AdminNoticesScreen()),
    _Section('Cài đặt', AppSvg.gear, ['settings.manage', 'security.view', 'security.policy', 'backups.manage'], () => const AdminSettingsScreen()),
    _Section('Thùng rác', AppSvg.delete, 'trash.manage', () => const AdminTrashScreen()),
    _Section('Phân quyền', AppSvg.userAdmin, null, () => const AdminStaffScreen(), root: true),
  ];

  int _index = 0;
  final Set<int> _visited = {0}; // sections are built when first opened and keep their state afterwards

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AdminSession>().load(context.read<ApiClient>()));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AdminSession>();
    final sections = [for (final s in _all) if (s.root ? session.isRoot : (s.perm == null || session.can(s.perm!))) s];
    if (session.loading && session.me == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (session.error != null && session.me == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(session.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              AppButton(label: 'Thử lại', variant: AppButtonVariant.primary, onPressed: () => session.load(context.read<ApiClient>())),
              AppButton(label: 'Đăng xuất', variant: AppButtonVariant.ghost, onPressed: () => context.read<AuthStore>().clear()),
            ]),
          ),
        ),
      );
    }
    if (sections.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin')),
        body: const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Tài khoản này chưa được cấp quyền nào.', textAlign: TextAlign.center))),
      );
    }
    if (_index >= sections.length) _index = 0;
    final current = sections[_index];
    return Scaffold(
      appBar: AppBar(title: Text(current.title, style: const TextStyle(fontWeight: FontWeight.w700))),
      drawer: Drawer(
        child: SafeArea(
          child: Column(children: [
            ListTile(
              title: Text(session.name.isEmpty ? 'Admin' : session.name, style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(session.isRoot ? '${session.username} · Admin gốc' : session.username),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(children: [
                for (var i = 0; i < sections.length; i++)
                  ListTile(
                    leading: SvgIcon(sections[i].icon),
                    title: Text(sections[i].title),
                    selected: i == _index,
                    onTap: () {
                      setState(() {
                        _index = i;
                        _visited.add(i);
                      });
                      Navigator.pop(context);
                    },
                  ),
              ]),
            ),
            const Divider(height: 1),
            ListTile(leading: const SvgIcon(AppSvg.account), title: const Text('Tài khoản'), onTap: () {
              Navigator.pop(context);
              context.push('/admin/account');
            }),
            ListTile(
              leading: const SvgIcon(AppSvg.info),
              title: const Text('Phiên bản ứng dụng'),
              subtitle: Text(AppConfig.appVersion),
              onTap: () {
                Navigator.pop(context);
                showVersionDialog(context);
              },
            ),
            ListTile(
              leading: SvgIcon(AppSvg.logout, color: Theme.of(context).colorScheme.error),
              title: Text('Đăng xuất', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                confirmLogout(context);
              },
            ),
          ]),
        ),
      ),
      body: IndexedStack(index: _index, children: [for (var i = 0; i < sections.length; i++) _visited.contains(i) ? sections[i].build() : const SizedBox.shrink()]),
    );
  }
}
