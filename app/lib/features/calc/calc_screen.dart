import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'calc_sync.dart';

import '../customers/customers_screen.dart';
import '../entries/entries_screen.dart';
import '../results/results_screen.dart';
import '../scoring/scoring_screen.dart';

/// The sub-tabs of Tính toán, in order, with the `tab` value used in the route (`/calc?tab=results&date=...`).
const calcTabs = [
  (id: 'entries', label: 'Nhập số'),
  (id: 'results', label: 'Kết quả'),
  (id: 'scoring', label: 'Tính điểm'),
  (id: 'customers', label: 'Khách hàng'),
];

int _nonce = 0;

/// Where to go to open a sub-tab of Tính toán. The `n` makes every link a new location, so opening the same tab twice still
/// moves to it after the user switched tabs by hand.
///
/// Tính điểm can also be opened on one [customer] and [date] with a note "Đã thêm [added] số liệu" (after the numbers of a
/// chat were saved in Nhập số).
String calcLocation(String tab, {String? date, String? customer, int? added}) =>
    '/calc?tab=$tab${date == null ? '' : '&date=$date'}${customer == null ? '' : '&customer=${Uri.encodeQueryComponent(customer)}'}${added == null ? '' : '&added=$added'}&n=${++_nonce}';

/// Tính toán: Nhập số | Kết quả | Tính điểm | Khách hàng as tabs; each keeps its state while another is shown.
class CalcScreen extends StatefulWidget {
  const CalcScreen({super.key});
  @override
  State<CalcScreen> createState() => _CalcScreenState();
}

class _CalcScreenState extends State<CalcScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: calcTabs.length, vsync: this);
  final CalcSync _sync = CalcSync();
  String? _routeUri;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) _sync.tabActivated(calcTabs[_tabs.index].id);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _sync.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A link such as /calc?tab=results&date=... opens that sub-tab.
    Uri? uri;
    try {
      uri = GoRouterState.of(context).uri;
    } catch (_) {/* not under a router (tests) */}
    if (uri == null || uri.toString() == _routeUri) return;
    _routeUri = uri.toString();
    final i = calcTabs.indexWhere((t) => t.id == uri!.queryParameters['tab']);
    if (i >= 0 && i != _tabs.index) _tabs.animateTo(i);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CalcSync>.value(value: _sync, child: _scaffold(context));
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      // The TabBar is the heading of Tính toán (the screens inside do not draw their own title).
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabs,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          tabs: [for (final t in calcTabs) Tab(text: t.label)],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _KeepAlive(child: EntriesScreen()),
          _KeepAlive(child: ResultsScreen()),
          _KeepAlive(child: ScoringScreen()),
          _KeepAlive(child: CustomersScreen()),
        ],
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});
  final Widget child;
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
