import 'dart:async';
import '../../../core/widgets/svg_icon.dart';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api_client.dart';
import '../../../core/auth_store.dart';
import '../account_widgets.dart';
import 'privacy_store.dart';
import 'screen_secure.dart';
import '../../../core/widgets/app_button.dart';

/// Wraps the whole router (MaterialApp.router `builder`):
///  - FLAG_SECURE (screenshots/recording/recents thumbnail blocked) per `/me/policy`, ON by default,
///  - auto-lock overlay asking the password, after idle minutes / after being in the background,
///  - blur veil while the app is in the background (only when the policy `blurOnHideEnabled` allows it).
/// The content underneath stays mounted (only covered), so half-typed input survives a lock.
class PrivacyGate extends StatefulWidget {
  const PrivacyGate({super.key, required this.child});
  final Widget child;
  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> with WidgetsBindingObserver {
  late final PrivacyStore _store = context.read<PrivacyStore>();
  late final AuthStore _auth = context.read<AuthStore>();
  late final ApiClient _api = context.read<ApiClient>();
  Timer? _timer;
  bool? _secure;
  bool _wasSignedIn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth.addListener(_sync);
    _store.addListener(_sync);
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _store.checkIdle());
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.removeListener(_sync);
    _store.removeListener(_sync);
    _timer?.cancel();
    super.dispose();
  }

  void _sync() {
    if (!mounted) return;
    final signedIn = _auth.ready && _auth.signedIn;
    if (signedIn && !_wasSignedIn) {
      _wasSignedIn = true;
      unawaited(_store.start(_api));
    } else if (!signedIn && _auth.ready && _wasSignedIn) {
      _wasSignedIn = false;
      unawaited(_store.stop());
    }
    // Secure by default (also on the login screens); only an explicit policy `false` lifts it.
    final secure = signedIn ? _store.screenshotGuardOn : true;
    if (secure != _secure) {
      _secure = secure;
      unawaited(ScreenSecure.set(secure));
    }
    if (_store.locked && mounted) FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_auth.signedIn) return;
    _store.onLifecycle(state);
    if (state == AppLifecycleState.resumed) unawaited(_store.refreshPolicy(_api));
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = context.select<AuthStore, bool>((a) => a.ready && a.signedIn);
    final locked = context.select<PrivacyStore, bool>((s) => s.locked);
    final ready = context.select<PrivacyStore, bool>((s) => s.ready);
    final veiled = context.select<PrivacyStore, bool>((s) => s.veiled);
    final showLock = signedIn && locked;
    final cover = signedIn && !ready; // saved lock state not read yet: never flash the content
    Widget content = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _store.touch(),
      onPointerMove: (_) => _store.touch(),
      child: widget.child,
    );
    if (veiled) {
      content = IgnorePointer(child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: content));
    }
    return Stack(fit: StackFit.expand, children: [
      ExcludeFocus(excluding: showLock, child: ExcludeSemantics(excluding: showLock, child: content)),
      if (veiled) IgnorePointer(child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.55))),
      if (cover) ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
      if (showLock) Positioned.fill(child: _LockOverlay(store: _store, api: _api, auth: _auth)),
    ]);
  }
}

class _LockOverlay extends StatelessWidget {
  const _LockOverlay({required this.store, required this.api, required this.auth});
  final PrivacyStore store;
  final ApiClient api;
  final AuthStore auth;

  // Own Overlay: the gate sits above the Navigator, and text fields need one for their selection toolbar.
  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [OverlayEntry(builder: (_) => _LockForm(store: store, api: api, auth: auth))]);
}

class _LockForm extends StatefulWidget {
  const _LockForm({required this.store, required this.api, required this.auth});
  final PrivacyStore store;
  final ApiClient api;
  final AuthStore auth;
  @override
  State<_LockForm> createState() => _LockFormState();
}

/// "45 giây", "1 phút 05 giây", "15 phút".
String formatLockWait(int seconds) {
  if (seconds < 60) return '$seconds giây';
  final m = seconds ~/ 60, r = seconds % 60;
  return r == 0 ? '$m phút' : '$m phút ${r.toString().padLeft(2, '0')} giây';
}

class _LockFormState extends State<_LockForm> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  /// While the server has locked the unlock attempts: the seconds left, counted down live (each second), and the deadline as a second
  /// check (a timer stops while the app is in the background).
  int _lockLeft = 0;
  DateTime? _lockUntil;
  Timer? _tick;

  bool get _locked => _lockLeft > 0;

  @override
  void dispose() {
    _tick?.cancel();
    _password.dispose();
    super.dispose();
  }

  void _startLock(int seconds) {
    _tick?.cancel();
    _lockLeft = seconds < 1 ? 1 : seconds;
    _lockUntil = DateTime.now().add(Duration(seconds: _lockLeft));
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      final byClock = _lockUntil!.difference(DateTime.now()).inSeconds;
      final next = (_lockLeft - 1) < byClock ? _lockLeft - 1 : byClock; // whichever says less is left
      setState(() => _lockLeft = next < 0 ? 0 : next);
      if (_lockLeft == 0) {
        t.cancel();
        _lockUntil = null;
        _error = null;
      }
    });
  }

  /// What a refused unlock tells the person: how many wrong tries so far and how many are left before the temporary lock.
  static String wrongMessage(ApiError e) {
    final d = e.data;
    final failed = d?['failedAttempts'], max = d?['maxAttempts'], left = d?['attemptsLeft'];
    if (failed is! num || max is! num || left is! num) return e.message;
    final tail = left <= 0 ? 'Lần sai tiếp theo sẽ bị khoá tạm.' : 'Còn ${left.toInt()} lần thử trước khi bị khoá tạm.';
    return '${e.message}. Đã sai ${failed.toInt()}/${max.toInt()} lần. $tail';
  }

  Future<void> _unlock() async {
    if (_locked) return;
    if (_password.text.isEmpty) {
      setState(() => _error = 'Vui lòng nhập mật khẩu');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.unlock(widget.api, _password.text);
      _password.clear();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.status == 429) {
        final secs = e.data?['retryAfterSeconds'];
        setState(() {
          _error = null;
          _password.clear();
          _startLock(secs is num ? secs.toInt() : (int.tryParse(RegExp(r'(\d+) giây').firstMatch(e.message)?.group(1) ?? '') ?? 30));
        });
      } else {
        setState(() => _error = e.status == 403 ? wrongMessage(e) : e.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Đã xảy ra lỗi, vui lòng thử lại');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SvgIcon(AppSvg.lock, size: 44),
                const SizedBox(height: 12),
                const Text('Ứng dụng đã khoá', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('Để bảo vệ dữ liệu, ứng dụng đã khoá. Nhập mật khẩu (hoặc mật khẩu lớp hai) để tiếp tục. Dữ liệu bạn đang nhập vẫn được giữ nguyên.', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (_locked)
                  NoticeBox('Đã nhập sai quá nhiều lần. Vui lòng thử lại sau ${formatLockWait(_lockLeft)}.', key: const ValueKey('lock-countdown'))
                else if (_error != null)
                  NoticeBox(_error!),
                PasswordField(controller: _password, label: 'Mật khẩu', enabled: !_busy && !_locked, autofocus: true, onSubmitted: (_) => _unlock()),
                const SizedBox(height: 14),
                AppButton(label: _locked ? 'Thử lại sau ${formatLockWait(_lockLeft)}' : 'Mở khoá', variant: AppButtonVariant.primary, loading: _busy, onPressed: _busy || _locked ? null : _unlock),
                AppButton(label: 'Đăng xuất', variant: AppButtonVariant.ghost, onPressed: _busy ? null : widget.auth.clear),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
