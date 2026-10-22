import 'dart:async';
import '../../core/widgets/svg_icon.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import '../account/privacy/privacy_store.dart';
import 'call_panel.dart';
import 'call_state.dart';
import 'call_ringer.dart';
import 'friends_controller.dart';
import 'keep_alive.dart';
import 'notifications.dart';

typedef HubFactory = FriendsController Function(ApiClient api, AuthStore auth);

/// Gives every screen the app-level messaging hub (null for Admin accounts and when signed out).
class MessagingScope extends InheritedWidget {
  const MessagingScope({super.key, required this.hub, required super.child});
  final FriendsController? hub;

  static FriendsController? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<MessagingScope>()?.hub;

  @override
  bool updateShouldNotify(MessagingScope old) => !identical(old.hub, hub);
}

/// Owns the messaging hub for the signed-in CUSTOMER and puts the incoming-call / in-call UI and in-app banners above
/// every screen. Place it in `MaterialApp.router(builder:)`.
///
///  - customer signs in (role `user`)  -> the hub is created and started (socket, chat, calls, notifications);
///  - logout (or the server revokes the session) -> the hub is disposed and wiped; nothing stays connected;
///  - Admin accounts never get one (calls and friend chat are customer-to-customer).
class MessagingHost extends StatefulWidget {
  const MessagingHost({
    super.key,
    required this.auth,
    required this.api,
    required this.child,
    this.router,
    this.privacy,
    this.notifier,
    this.ringer,
    this.background,
    this.factory,
  });

  final AuthStore auth;
  final ApiClient api;
  final Widget child;
  final GoRouter? router;
  final PrivacyStore? privacy;
  final AppNotifier? notifier;
  final CallRinger? ringer;
  final BackgroundService? background;

  /// Test hook: builds the hub instead of the real one.
  final HubFactory? factory;

  /// Customers get the hub; Admins and signed-out users do not.
  static bool wantsHub(AuthStore a) => a.ready && a.signedIn && a.role == 'user';

  @override
  State<MessagingHost> createState() => _MessagingHostState();
}

class _MessagingHostState extends State<MessagingHost> with WidgetsBindingObserver {
  FriendsController? _hub;
  AppBanner? _banner;
  int _shownTick = 0;
  Timer? _bannerTimer;
  bool _launchHandled = false;

  AppNotifier get _notifier => widget.notifier ?? const NoopNotifier();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.auth.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(MessagingHost old) {
    super.didUpdateWidget(old);
    if (old.auth != widget.auth) {
      old.auth.removeListener(_sync);
      widget.auth.addListener(_sync);
      _sync();
    }
  }

  void _sync() {
    final want = MessagingHost.wantsHub(widget.auth);
    if (want && _hub == null) {
      _create();
    } else if (!want && _hub != null) {
      _destroy();
    }
  }

  void _create() {
    final hub = widget.factory?.call(widget.api, widget.auth) ??
        FriendsController(api: widget.api, auth: widget.auth, notifier: _notifier, ringer: widget.ringer ?? SilentRinger(), background: widget.background ?? const NoopBackgroundService());
    _hub = hub;
    _shownTick = hub.bannerTick;
    hub.addListener(_onHub);
    widget.privacy?.isBusy = () => hub.callBusy;
    unawaited(_notifier.init(onTap: _onNoticeTap).then((_) => _handleLaunchNotice()));
    unawaited(hub.start());
    if (mounted) setState(() {});
  }

  void _destroy() {
    final hub = _hub;
    if (hub == null) return;
    _hub = null;
    _bannerTimer?.cancel();
    _banner = null;
    hub.removeListener(_onHub);
    final p = widget.privacy;
    if (p != null) p.isBusy = null;
    _launchHandled = false;
    if (!mounted) {
      hub.dispose();
      return;
    }
    setState(() {});
    // The screens that listen to the hub are rebuilt without it in the coming frame (the router also leaves them for the login
    // screen). Disposing it right here, inside the sign-out notification, made a screen that was still on the page add a listener
    // to a disposed hub - a framework error instead of the login screen when another device ended this session.
    WidgetsBinding.instance.addPostFrameCallback((_) => hub.dispose());
  }

  Future<void> _handleLaunchNotice() async {
    if (_launchHandled) return;
    _launchHandled = true;
    final payload = await _notifier.launchPayload();
    if (payload != null) WidgetsBinding.instance.addPostFrameCallback((_) => _onNoticeTap(payload));
  }

  /// A chat page is pushed above the tabs; any other route is a tab and is switched to.
  void _open(String route) {
    final r = widget.router;
    if (r == null) return;
    if (route.startsWith('/friends/chat/')) {
      r.push(route);
    } else {
      r.go(route);
    }
  }

  void _onNoticeTap(String? payload) {
    final hub = _hub;
    final t = parseNoticePayload(payload);
    if (hub == null || t == null) return;
    final route = routeForTarget(t);
    if (route == null) return;
    if (t.friendId != null && hub.chat?.openPeer == t.friendId) return; // already looking at it
    _open(route);
  }

  void _onHub() {
    final hub = _hub;
    if (hub == null || !mounted) return;
    if (hub.bannerTick != _shownTick) {
      _shownTick = hub.bannerTick;
      if (widget.privacy?.locked != true) {
        setState(() => _banner = hub.banner);
        _bannerTimer?.cancel();
        _bannerTimer = Timer(const Duration(seconds: 6), () {
          if (mounted) setState(() => _banner = null);
        });
      }
    }
    setState(() {}); // the call layer follows the call status
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _hub?.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.auth.removeListener(_sync);
    _bannerTimer?.cancel();
    final hub = _hub;
    if (hub != null) {
      hub.removeListener(_onHub);
      final p = widget.privacy;
      if (p != null) p.isBusy = null;
      hub.dispose();
    }
    super.dispose();
  }

  void _openBanner(AppBanner b) {
    setState(() => _banner = null);
    _bannerTimer?.cancel();
    if (b.route != null) _open(b.route!);
  }

  @override
  Widget build(BuildContext context) {
    final hub = _hub;
    final call = hub?.call;
    return MessagingScope(
      hub: hub,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_banner != null)
            Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: Padding(padding: const EdgeInsets.all(8), child: BannerCard(banner: _banner!, onTap: () => _openBanner(_banner!), onClose: () => setState(() => _banner = null))))),
          if (call != null)
            Positioned.fill(
              child: ListenableBuilder(
                listenable: call,
                builder: (context, _) {
                  if (call.status == CallStatus.idle) return const SizedBox.shrink();
                  final panel = CallPanel(call: call);
                  // While a call is up the back key must not pop the screens underneath.
                  return Router.maybeOf(context) == null ? panel : BackButtonListener(onBackButtonPressed: () async => true, child: panel);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// The in-app message banner.
class BannerCard extends StatelessWidget {
  const BannerCard({super.key, required this.banner, required this.onTap, required this.onClose});
  final AppBanner banner;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            SvgIcon(AppSvg.friends, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(banner.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(banner.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            IconButton(icon: const SvgIcon(AppSvg.close, size: 20), tooltip: 'Đóng', onPressed: onClose),
          ]),
        ),
      ),
    );
  }
}
