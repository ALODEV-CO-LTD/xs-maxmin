import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/api_client.dart';
import 'core/auth_store.dart';
import 'core/lottery_stations.dart';
import 'core/mask_store.dart';
import 'core/theme.dart';
import 'features/account/account_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/recover_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/customers/customers_screen.dart';
import 'features/entries/entries_screen.dart';
import 'features/friends/friends_screen.dart';
import 'features/results/results_screen.dart';
import 'features/scoring/scoring_screen.dart';
import 'features/shell/admin_notice_screen.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/more_screen.dart';

const _authRoutes = {'/login', '/register', '/recover'};

GoRouter buildRouter(AuthStore auth) => GoRouter(
      initialLocation: '/entries',
      refreshListenable: auth,
      redirect: (context, state) {
        if (!auth.ready) return null;
        final loc = state.matchedLocation;
        if (!auth.signedIn) return _authRoutes.contains(loc) ? null : '/login';
        if (auth.isAdmin) return loc == '/admin' ? null : '/admin';
        if (_authRoutes.contains(loc) || loc == '/admin' || loc == '/') return '/entries';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
        GoRoute(path: '/recover', builder: (_, _) => const RecoverScreen()),
        GoRoute(path: '/admin', builder: (_, _) => const AdminNoticeScreen()),
        GoRoute(path: '/friends', builder: (_, _) => const FriendsScreen()),
        GoRoute(path: '/account', builder: (_, _) => const AccountScreen()),
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/entries', builder: (_, _) => const EntriesScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/results', builder: (_, _) => const ResultsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/scoring', builder: (_, _) => const ScoringScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/more', builder: (_, _) => const MoreScreen())]),
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
  late final GoRouter _router = buildRouter(_auth);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthStore>.value(value: _auth),
        Provider<ApiClient>.value(value: _api),
        ChangeNotifierProvider<LotteryStations>.value(value: _stations),
        ChangeNotifierProvider<MaskStore>.value(value: _mask),
      ],
      child: MaterialApp.router(
        title: 'MAMBA',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: ThemeMode.dark,
        routerConfig: _router,
        locale: const Locale('vi'),
        supportedLocales: const [Locale('vi')],
      ),
    );
  }
}
