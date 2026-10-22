import 'package:flutter/material.dart';
import '../../core/widgets/svg_icon.dart';

import 'package:go_router/go_router.dart';

import '../account/account_stats_tab.dart';
import '../friends/messaging_host.dart';
import 'package_card.dart';

/// Tổng quan: the home tab. The statistics (customers, plays, points in/out, profit, chart by day/month/year).
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Tổng quan'), actions: const [_SupportButton()]),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [PackageCard(), AccountStatsTab()]),
          ),
        ),
      ),
    );
  }
}

/// Opens "Hỗ trợ từ Admin" (web: the button in the top bar), with the count of unread replies.
class _SupportButton extends StatelessWidget {
  const _SupportButton();
  @override
  Widget build(BuildContext context) {
    final hub = MessagingScope.maybeOf(context);
    Widget button(int n) => IconButton(
          tooltip: 'Hỗ trợ từ Admin',
          icon: Badge(isLabelVisible: n > 0, label: Text(n > 9 ? '9+' : '$n'), child: const SvgIcon(AppSvg.support)),
          onPressed: () => context.push('/support'),
        );
    if (hub == null) return button(0);
    return ListenableBuilder(listenable: hub, builder: (_, _) => button(hub.supportUnread));
  }
}
