import 'package:flutter/material.dart';

import '../account/account_stats_tab.dart';

/// Tổng quan: the home tab. The statistics (customers, plays, points in/out, profit, chart by day/month/year).
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Tổng quan')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
        child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: const AccountStatsTab())),
      ),
    );
  }
}
