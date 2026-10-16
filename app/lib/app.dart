import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/admin_session.dart';
import 'core/api_client.dart';
import 'core/auth_store.dart';
import 'core/lottery_stations.dart';
import 'core/mask_store.dart';
import 'core/scoring_config_bus.dart';
import 'core/theme.dart';
import 'features/account/account_screen.dart';
import 'features/account/privacy/privacy_gate.dart';
import 'features/account/privacy/privacy_store.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/recover_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/calc/calc_screen.dart';
import 'features/customers/customer_config_screen.dart';
import 'features/friends/call_ringer.dart';
import 'features/friends/chat_route.dart';
import 'features/friends/friends_screen.dart';
import 'features/friends/keep_alive.dart';
import 'features/friends/messaging_host.dart';
import 'features/friends/notifications.dart';
import 'features/friends/push_registrar.dart';
import 'features/overview/overview_screen.dart';
import 'features/admin/admin_shell.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/update_gate.dart';

const _authRoutes = {'/login', '/register', '/recover'};

/// The home tab of a customer.
const homeRoute = '/overview';

// Paths of the older navigation (Nhập số / Kết quả / Tính điểm / Khách hàng were bottom tabs, Thêm held the rest) still work:
// they open the matching sub-tab of Tính toán.
const _legacyCalc = {'/entries': 'entries', '/results': 'results', '/scoring': 'scoring', '/customers': 'customers'};

/// Opens an in-app route: a chat page goes on top of the tabs (push), a tab is switched to (go) so it is not stacked twice.
void openAppRoute(GoRouter router, String route) {
  if (route.startsWith('/friends/chat/')) {
    router.push(route);
  } else {
    router.go(route);
  }
}

GoRouter buildRouter(AuthStore auth) => GoRouter(
      initialLocation: homeRoute,
      refreshListenable: auth,
      redirect: (context, state) {
        if (!auth.ready) return null;
        final loc = state.matchedLocation;
        if (!auth.signedIn) return _authRoutes.contains(loc) ? null : '/login';
        if (auth.isAdmin) return (loc == '/admin' || loc == '/admin/account') ? null : '/admin';
        if (_authRoutes.contains(loc) || loc == '/admin' || loc == '/admin/account' || loc == '/' || loc == '/more') return homeRoute;
        final legacy = _legacyCalc[loc];
        if (legacy != null) {
          final q = state.uri.queryParameters;
          return '/calc?tab=$legacy${q['date'] == null ? '' : '&date=${q['date']}'}';
        }
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
        GoRoute(path: '/recover', builder: (_, _) => const RecoverScreen()),
        GoRoute(path: '/admin', builder: (_, _) => const AdminShell()),
        // The Admin opens the account screen from the drawer (a pushed page with a back arrow, no customer tab bar).
        GoRoute(path: '/admin/account', builder: (_, _) => const AccountScreen()),
        GoRoute(path: '/friends/chat/:id', builder: (_, state) => ChatRoutePage(friendId: state.pathParameters['id'] ?? '')),
        for (final p in [..._legacyCalc.keys, '/more']) GoRoute(path: p, builder: (_, _) => const SizedBox.shrink()),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/overview', builder: (_, _) => const OverviewScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/calc', builder: (_, _) => const CalcScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/friends', builder: (_, _) => const FriendsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/config', builder: (_, _) => const DefaultConfigScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen(embedded: true))]),
          ],
        ),
      ],
    );

/// Root widget: providers (auth, API client, lottery catalog) + the router.
class MambaApp extends StatefulWidget {
  const MambaApp({super.key});
  @override
  State<MambaApp> createState() => _MambaAppState();
}

class _MambaAppState extends State<MambaApp> {
  late final AuthStore _auth = AuthStore()..init();
  late final ApiClient _api = ApiClient(_auth);
  final LotteryStations _stations = LotteryStations();
  final MaskStore _mask = MaskStore()..load();
  final AdminSession _admin = AdminSession();
  final PrivacyStore _privacy = PrivacyStore();
  final ScoringConfigBus _configBus = ScoringConfigBus();
  late final GoRouter _router = buildRouter(_auth);
  // Messaging pieces that live as long as the app (the hub itself is per signed-in customer, see MessagingHost).
  final LocalNotifier _notifier = LocalNotifier();
  final SystemCallRinger _ringer = SystemCallRinger();
  final ForegroundTaskService _background = ForegroundTaskService();
  // Push notifications: APNs on iOS, FCM on Android (a no-op when FCM is not configured); nothing elsewhere.
  late final PushRegistrar _push = PushRegistrar(
    auth: _auth,
    api: _api,
    openRoute: (r) => openAppRoute(_router, r),
    explain: _explainPush,
  );

  @override
  void initState() {
    super.initState();
    _push.start();
  }

  @override
  void dispose() {
    _push.dispose();
    super.dispose();
  }

  Future<bool> _explainPush() async {
    final ctx = _router.routerDelegate.navigatorKey.currentState?.overlay?.context;
    if (ctx == null) return false;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('Bật thông báo?'),
        content: const Text('Tin nhắn được mã hoá 2 đầu và không lưu trên máy chủ. Thông báo chỉ báo "có người nhắn / gọi bạn" (kèm tên), không hiện nội dung; bạn cần mở MAMBA để nhận tin.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Để sau')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Bật thông báo')),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthStore>.value(value: _auth),
        Provider<ApiClient>.value(value: _api),
        ChangeNotifierProvider<LotteryStations>.value(value: _stations),
        ChangeNotifierProvider<MaskStore>.value(value: _mask),
        ChangeNotifierProvider<AdminSession>.value(value: _admin),
        ChangeNotifierProvider<PrivacyStore>.value(value: _privacy),
        ChangeNotifierProvider<ScoringConfigBus>.value(value: _configBus),
      ],
      child: MaterialApp.router(
        title: 'MAMBA',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        // Always the light theme (white, green accents): the customer's design has no dark mode.
        themeMode: ThemeMode.light,
        routerConfig: _router,
        builder: (context, child) => MessagingHost(
          auth: _auth,
          api: _api,
          router: _router,
          privacy: _privacy,
          notifier: _notifier,
          ringer: _ringer,
          background: _background,
          child: PushBinding(registrar: _push, child: UpdateGate(api: _api, child: PrivacyGate(child: child ?? const SizedBox.shrink()))),
        ),
        locale: const Locale('vi'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('vi')],
      ),
    );
  }
}
