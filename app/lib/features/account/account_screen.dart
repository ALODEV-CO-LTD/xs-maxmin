import 'package:flutter/material.dart';
import '../../core/widgets/logout.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import 'account_controller.dart';
import 'account_data_tab.dart';
import 'account_devices_tab.dart';
import 'account_packages_tab.dart';
import 'account_profile_tab.dart';
import 'account_stats_tab.dart';
import 'account_widgets.dart';

enum AccountTab { stats, profile, devices, packages, data }

const _tabLabels = {
  AccountTab.stats: 'Thống kê',
  AccountTab.profile: 'Hồ sơ',
  AccountTab.devices: 'Thiết bị & riêng tư',
  AccountTab.packages: 'Gói & Thanh toán',
  AccountTab.data: 'Dữ liệu',
};

/// Tài khoản: tabs shown as separate pill buttons (Thống kê, Hồ sơ, Thiết bị & riêng tư, Gói & Thanh toán, Dữ liệu).
/// Thống kê and Gói & Thanh toán are for customer accounts only, like the web.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.initialTab});
  final AccountTab? initialTab;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  late final AccountController _ctl = AccountController(context.read<ApiClient>());
  late AccountTab _tab = widget.initialTab ?? AccountTab.stats;
  final _scroll = ScrollController();
  final _keys = {for (final t in AccountTab.values) t: GlobalKey()};

  @override
  void initState() {
    super.initState();
    _ctl.load();
  }

  @override
  void dispose() {
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<AccountTab> get _tabs => [
        for (final t in AccountTab.values)
          if (!(context.read<AuthStore>().isAdmin && (t == AccountTab.stats || t == AccountTab.packages))) t,
      ];

  void _select(AccountTab t) {
    setState(() => _tab = t);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _keys[t]?.currentContext;
      if (c != null) Scrollable.ensureVisible(c, alignment: 0.5, duration: const Duration(milliseconds: 200));
    });
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    if (!tabs.contains(_tab)) _tab = tabs.first;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tài khoản'),
        actions: [IconButton(icon: const Icon(Icons.logout), tooltip: 'Đăng xuất', onPressed: () => confirmLogout(context))],
        leading: context.canPop() ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/more')),
      ),
      body: ListenableBuilder(
        listenable: _ctl,
        builder: (context, _) {
          return Column(children: [
            SizedBox(
              height: 60,
              child: ListView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: [
                  for (final t in tabs)
                    Padding(
                      key: _keys[t],
                      padding: const EdgeInsets.only(right: 8),
                      child: _TabPill(label: _tabLabels[t]!, selected: t == _tab, onTap: () => _select(t)),
                    ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ]);
        },
      ),
    );
  }

  Widget _body() {
    if (_ctl.loading && _ctl.me == null) return const Center(child: CircularProgressIndicator());
    if (_ctl.me == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            NoticeBox(_ctl.error ?? 'Không tải được thông tin tài khoản'),
            OutlinedButton(onPressed: _ctl.load, child: const Text('Thử lại')),
          ]),
        ),
      );
    }
    final tab = switch (_tab) {
      AccountTab.stats => const AccountStatsTab(),
      AccountTab.profile => AccountProfileTab(ctl: _ctl),
      AccountTab.devices => const AccountDevicesTab(),
      AccountTab.packages => AccountPackagesTab(ctl: _ctl),
      AccountTab.data => AccountDataTab(ctl: _ctl),
    };
    return RefreshIndicator(
      onRefresh: () => _ctl.load(silent: true),
      child: SingleChildScrollView(
        key: PageStorageKey('account-${_tab.name}'),
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 32),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: KeyedSubtree(key: ValueKey(_tab), child: tab))),
      ),
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: selected ? cs.primary : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(99), border: Border.all(color: selected ? cs.primary : cs.outlineVariant)),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: selected ? cs.onPrimary : cs.onSurface)),
        ),
      ),
    );
  }
}
