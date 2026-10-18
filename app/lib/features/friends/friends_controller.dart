import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import 'call_ringer.dart';
import 'call_service.dart';
import 'chat_service.dart';
import 'chat_store.dart';
import 'keep_alive.dart';
import 'notifications.dart';
import 'realtime_socket.dart';
import 'screenshot_bridge.dart';

class Friend {
  Friend({required this.id, required this.name, required this.username, this.isAdmin = false, this.lastMessage, this.lastMessageAt = 0, this.isGroup = false, this.memberCount = 0});
  final String id;
  final String name;
  final String username;
  final bool isAdmin;
  String? lastMessage;
  int lastMessageAt;

  /// A group chat shown in the same list (id `g-…`): its name is the group's name.
  final bool isGroup;
  final int memberCount;

  factory Friend.fromJson(Map<String, dynamic> j) => Friend(id: j['id'] as String, name: (j['name'] ?? '') as String, username: (j['username'] ?? '') as String, isAdmin: j['isAdmin'] == true);
}

class SearchResult {
  SearchResult({required this.id, required this.name, required this.username, required this.isFriend, this.isAdmin = false});
  final String id;
  final String name;
  final String username;
  final bool isAdmin;
  bool isFriend;
}

/// Lower-case, accent-free text for friend filtering ("do ngoc" finds "Đỗ Ngọc Mai"); messageParser.js `fold`.
String foldVi(String s) {
  const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString();
}

/// Total shown on the "Thêm" tab and the Bạn bè entry: unread chat messages + unseen missed calls + unread replies
/// from Admin.
int unreadBadgeCount({Map<String, int> chat = const {}, Map<String, int> missed = const {}, int support = 0}) {
  var n = support < 0 ? 0 : support;
  for (final v in chat.values) {
    if (v > 0) n += v;
  }
  for (final v in missed.values) {
    if (v > 0) n += v;
  }
  return n;
}

/// A short in-app message shown over any screen (new message while you are not in that chat, call problems, ...).
class AppBanner {
  const AppBanner({required this.title, required this.body, this.friendId, this.route});
  final String title;
  final String body;
  final String? friendId;

  /// go_router location to open when tapped.
  final String? route;
}

/// The app-level messaging hub. It owns the one WebSocket, the E2EE [ChatService], the [CallService], the unread
/// counters, the notifications, the ringtone and the optional Android foreground service. It is created ONCE when a
/// customer is signed in (see MessagingHost) and disposed on logout, so messages and calls are received on every
/// screen, not only on Bạn bè. The screens consume it; none opens a second socket.
class FriendsController extends ChangeNotifier {
  FriendsController({required this.api, required this.auth, AppNotifier? notifier, CallRinger? ringer, BackgroundService? background, RealtimeSocket? socket})
      : notifier = notifier ?? const NoopNotifier(),
        ringer = ringer ?? SilentRinger(),
        background = background ?? const NoopBackgroundService(),
        socket = socket ?? RealtimeSocket(tokenProvider: () => auth.token) {
    screenshots = ScreenshotBridge(
      openPeer: () => chat?.openPeer,
      isForeground: () => foreground,
      canNotify: (id) => !(friends.where((f) => f.id == id).firstOrNull?.isAdmin ?? false),
      notify: (id) async => chat?.notifyScreenshot(id),
    );
  }
  final ApiClient api;
  final AuthStore auth;
  final AppNotifier notifier;
  final CallRinger ringer;
  final BackgroundService background;
  late final ScreenshotBridge screenshots;

  final RealtimeSocket socket;
  ChatService? chat;
  CallService? call;
  String userId = '';
  String userName = '';
  bool loading = true;
  String loadError = '';
  List<Friend> friends = [];

  /// Group chats of this device as list rows (built from the stored groups; the server knows none).
  List<Friend> groups = [];
  String myCode = '';
  bool noMyCode = false;
  Map<String, int> unseenMissed = {};
  int supportUnread = 0;

  /// The "Hỗ trợ từ Admin" page is on screen (web: notify.supportVisible): anything new there counts as read at once.
  bool supportVisible = false;
  String searchQuery = '';
  List<SearchResult> results = [];
  bool searching = false;
  String searchError = '';
  String? addingId;
  ({String friendId, String name, String preview})? lastIncoming;

  /// The app is on screen (resumed). Notifications are for the background; banners for the foreground.
  bool foreground = true;

  /// Newest in-app banner; [bannerTick] bumps so the host shows it once.
  AppBanner? banner;
  int bannerTick = 0;

  /// "Giữ kết nối khi thoát app" (default off).
  bool keepAlive = false;
  bool get notificationsAsked => _notifAsked;
  bool _notifAsked = false;
  CallStatus _prevCall = CallStatus.idle;
  ServiceMode _mode = ServiceMode.off;
  bool _missedLoaded = false;

  StreamSubscription<Map<String, dynamic>>? _frames;
  Timer? _poll, _searchTimer;
  bool _disposed = false;
  bool _wasReady = false;

  /// Test hook / override: build the store (defaults to sqflite).
  Future<ChatStore> Function(String userId) storeFactory = SqliteChatStore.open;
  KeyVault vault = const SecureKeyVault();

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    try {
      final me = await api.get('/me') as Map;
      userId = me['id'] as String;
      userName = (me['name'] ?? '') as String;
      final isAdmin = me['role'] == 'admin' || auth.isAdmin;
      final store = await storeFactory(userId);
      if (_disposed) {
        await store.close();
        return;
      }
      chat = ChatService(api: api, userId: userId, store: store, vault: vault, socket: socket)
        ..foreground = foreground
        ..onIncoming = _onIncoming;
      call = CallService(api: api, socket: socket, canCall: !isAdmin)..onBusyMissed = _onBusyMissed;
      chat!.addListener(_onChat);
      call!.addListener(_onCall);
      socket.addListener(_onSocket);
      _frames = socket.frames.listen((m) {
        if (call!.onFrame(m)) return;
        if (m['type'] == 'new-message') {
          _onPush(m);
          return;
        }
        chat!.onFrame(m);
      });
      screenshots.attach();
      await _loadSettings();
      socket.start();
      await Future.wait([chat!.init(), _loadFriends(), if (!isAdmin) _loadMyCode(), if (!isAdmin) loadUnseenMissed()]);
      await refreshFriendList(quiet: true);
      unawaited(pollUnread());
      _poll = Timer.periodic(const Duration(seconds: 60), (_) => pollUnread());
    } catch (e) {
      loadError = e is ApiError ? e.message : 'Không tải được danh sách bạn bè';
    }
    loading = false;
    _changed();
  }

  void _onChat() => refreshFriendList(quiet: true);

  Future<void> _loadSettings() async {
    keepAlive = await KeepAliveSettings.load();
    try {
      _notifAsked = (await SharedPreferences.getInstance()).getBool('mamba_notif_asked') ?? false;
    } catch (_) {/* ask again */}
    _syncService();
  }

  // ---- incoming messages / push events -----------------------------------------------------------------------------

  String _nameOf(String id, String? given) => friends.where((f) => f.id == id).map((f) => f.name).firstOrNull ?? given ?? 'Bạn bè';

  void _onIncoming(String friendId, String? friendName, String preview) {
    final name = _nameOf(friendId, friendName);
    lastIncoming = (friendId: friendId, name: name, preview: preview);
    switch (alertForMessage(foreground: foreground, openPeer: chat?.openPeer, friendId: friendId)) {
      case MessageAlert.banner:
        _banner(AppBanner(title: name, body: preview, friendId: friendId, route: chatRoute(friendId)));
      case MessageAlert.notification:
        // The OS notification never carries the message text.
        unawaited(notifier.show(messageNotice(friendId, name)));
      case MessageAlert.none:
    }
    _changed();
  }

  /// `new-message` push: a reply from Admin in Phản hồi (stored on the server, so only its counter is fetched).
  void _onPush(Map<String, dynamic> m) {
    unawaited(pollUnread());
    if (m['source'] != 'support') return;
    if (supportVisible) return;
    if (foreground) {
      _banner(AppBanner(title: 'Admin', body: (m['preview'] as String?) ?? 'Có phản hồi mới từ Admin', route: '/support'));
    } else {
      unawaited(notifier.show(supportNotice()));
    }
  }

  void _banner(AppBanner b) {
    banner = b;
    bannerTick++;
    _changed();
  }

  /// Shows an arbitrary in-app banner (used by the host for call problems).
  void showBanner(AppBanner b) => _banner(b);

  static String chatRoute(String friendId) => '/friends/chat/${Uri.encodeComponent(friendId)}';

  // ---- calls: ringing, notifications, missed calls ----------------------------------------------------------------

  void _onBusyMissed(String friendId, String name) {
    if (foreground) {
      _banner(AppBanner(title: 'Cuộc gọi nhỡ', body: 'Cuộc gọi nhỡ từ $name (bạn đang bận)', friendId: friendId, route: chatRoute(friendId)));
    } else {
      unawaited(notifier.show(missedCallNotice(friendId, name)));
    }
    unawaited(loadUnseenMissed());
  }

  int _lastEnded = 0;
  void _onCall() {
    final c = call!;
    final prev = _prevCall;
    final now = c.status;
    _prevCall = now;
    if (now == CallStatus.incoming && prev != CallStatus.incoming) _incomingStarted(c);
    if (prev == CallStatus.incoming && now != CallStatus.incoming) _incomingStopped();
    if (c.endedTick != _lastEnded) {
      _lastEnded = c.endedTick;
      final end = c.lastEnd;
      if (end != null && end.missedIncoming && !foreground) unawaited(notifier.show(missedCallNotice(end.peerId, end.peerName)));
      loadUnseenMissed();
    }
    _syncService();
    if (c.error.isNotEmpty && !c.busy) {
      final msg = c.error;
      c.clearError();
      _banner(AppBanner(title: 'Cuộc gọi', body: msg));
    }
    _changed();
  }

  /// Rings an incoming call: the ringing notification (the phone's ringtone, repeating) - a quiet in-app variant while
  /// the app is on screen, a full-screen one in the background. With notifications off, the app rings itself.
  Future<void> _ring(CallPeer p) async {
    if (await notifier.allowed) {
      await notifier.show(incomingCallNotice(p.id, p.name, inApp: foreground));
    } else if (foreground) {
      await ringer.start();
    }
  }

  void _incomingStarted(CallService c) {
    final p = c.peer;
    if (p == null) return;
    unawaited(_ring(p));
  }

  void _incomingStopped() {
    unawaited(ringer.stop());
    unawaited(notifier.cancel(incomingCallNoticeId));
  }

  /// A call in progress is never auto-locked / blurred (PrivacyStore.isBusy) and needs the microphone foreground
  /// service when the app is left.
  bool get callBusy => call?.busy ?? false;

  void _syncService() {
    final st = call?.status ?? CallStatus.idle;
    final inCall = st != CallStatus.idle && st != CallStatus.incoming;
    final want = desiredServiceMode(keepAlive: keepAlive, inCall: inCall);
    if (want == _mode) return;
    _mode = want;
    unawaited(background.apply(want));
  }

  // ---- settings -----------------------------------------------------------------------------------------------------

  Future<void> setKeepAlive(bool on) async {
    keepAlive = on;
    await KeepAliveSettings.save(on);
    if (on) await requestNotificationPermission(force: true);
    _syncService();
    _changed();
  }

  /// The user declined the explanation dialog: do not ask again on every visit.
  Future<void> skipNotificationPrompt() async {
    _notifAsked = true;
    try {
      await (await SharedPreferences.getInstance()).setBool('mamba_notif_asked', true);
    } catch (_) {/* fine */}
    _changed();
  }

  /// Asks for the notification permission (Android 13+). Without `force` it asks only once per install, at the first
  /// visit to Bạn bè, not at launch.
  Future<bool> requestNotificationPermission({bool force = false}) async {
    if (!force && _notifAsked) return notifier.allowed;
    _notifAsked = true;
    try {
      await (await SharedPreferences.getInstance()).setBool('mamba_notif_asked', true);
    } catch (_) {/* fine */}
    if (await notifier.allowed) return true;
    return notifier.requestPermission();
  }

  void _onSocket() {
    if (socket.ready) {
      if (!_wasReady) {
        pollUnread(); // messages may have arrived while the socket was down
        loadUnseenMissed();
      }
      chat?.loadFriendKeys().catchError((_) => <Map<String, dynamic>>[]);
    } else {
      call?.onSocketLost();
    }
    _wasReady = socket.ready;
    _changed();
  }

  /// App to the background / foreground. The socket stays up in both (it reconnects with backoff while the process
  /// lives); only the way news is shown changes.
  void setForeground(bool fg) {
    if (fg == foreground) {
      if (fg) socket.reconnectNow();
      return;
    }
    foreground = fg;
    chat?.foreground = fg;
    if (fg) {
      unawaited(notifier.cancelAll());
      final c = call;
      final p = c?.peer;
      if (c != null && c.status == CallStatus.incoming && p != null) unawaited(_ring(p)); // ring in the app now
      socket.reconnectNow();
      pollUnread();
      loadUnseenMissed();
      final open = chat?.openPeer;
      if (open != null) chat?.markRead(open);
    } else {
      final c = call;
      final p = c?.peer;
      if (c != null && c.status == CallStatus.incoming && p != null) {
        unawaited(ringer.stop());
        unawaited(_ring(p));
      }
    }
    _changed();
  }

  /// Sum shown on badges.
  int get unreadTotal => unreadBadgeCount(chat: chat?.unread ?? const {}, missed: unseenMissed, support: supportUnread);

  Future<void> _loadFriends() async {
    final list = await chat!.loadFriendKeys();
    friends = [for (final f in list) Friend.fromJson(f)];
  }

  /// Reloads the list from the server and merges the local last-message previews.
  Future<void> refreshFriendList({bool quiet = false}) async {
    final c = chat;
    if (c == null) return;
    try {
      if (!quiet) loading = true;
      final prev = await c.previews();
      if (!quiet || friends.isEmpty) await _loadFriends();
      for (final f in friends) {
        f.lastMessage = prev[f.id]?.preview;
        f.lastMessageAt = prev[f.id]?.createdAt ?? 0;
      }
      friends.sort((a, b) => b.lastMessageAt != a.lastMessageAt ? b.lastMessageAt.compareTo(a.lastMessageAt) : foldVi(a.name).compareTo(foldVi(b.name)));
      groups = [
        for (final g in c.groups.values)
          Friend(
            id: g.id,
            name: g.name,
            username: '',
            isGroup: true,
            memberCount: g.members.length,
            lastMessage: prev[g.id] == null ? null : '${prev[g.id]!.mine ? 'Bạn' : c.memberName(g, prev[g.id]!.fromId ?? '')}: ${prev[g.id]!.preview}',
            lastMessageAt: prev[g.id]?.createdAt ?? g.updatedAt,
          ),
      ]..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      loadError = '';
    } catch (e) {
      if (!quiet) loadError = e is ApiError ? e.message : 'Không tải được danh sách bạn bè';
    }
    loading = false;
    _changed();
  }

  Future<void> _loadMyCode() async {
    try {
      final res = await api.get('/me/customer-codes') as Map;
      final codes = res['codes'] as List?;
      myCode = codes != null && codes.isNotEmpty ? (codes.first as Map)['code'] as String : '';
      noMyCode = myCode.isEmpty;
    } catch (_) {/* the card simply stays hidden */}
  }

  Future<void> loadUnseenMissed() async {
    if (call?.canCall != true) return;
    try {
      final res = await api.get('/me/calls?limit=1') as Map;
      final next = {for (final e in ((res['unseenMissed'] as Map?) ?? {}).entries) e.key as String: (e.value as num).toInt()};
      if (_missedLoaded && !foreground) {
        for (final e in next.entries) {
          if (e.value > (unseenMissed[e.key] ?? 0)) unawaited(notifier.show(missedCallNotice(e.key, _nameOf(e.key, null))));
        }
      }
      _missedLoaded = true;
      unseenMissed = next;
      _changed();
    } catch (_) {/* nicety */}
  }

  /// Fallback poll of the server's counters (web: notify.refresh): support replies from Admin.
  Future<void> pollUnread() async {
    try {
      final res = await api.get('/me/unread') as Map;
      supportUnread = supportVisible ? 0 : (res['support'] as num?)?.toInt() ?? 0;
      if (supportVisible && ((res['support'] as num?)?.toInt() ?? 0) > 0) unawaited(markSupportRead());
      _changed();
    } catch (_) {/* badges are a nicety */}
  }

  /// The Admin thread is being read: drop its badge and tell the server so it stays read (web: notify.clear('support')).
  Future<void> markSupportRead() async {
    if (supportUnread != 0) {
      supportUnread = 0;
      _changed();
    }
    try {
      await api.post('/me/unread/read', {'peerId': 'support'});
    } catch (_) {/* a nicety: the next poll corrects it */}
  }

  // ---- search / add / remove -------------------------------------------------------------------------------------------

  /// Every conversation of the list: friends and groups, the most recent first.
  List<Friend> get conversations => [...friends, ...groups]..sort((a, b) => b.lastMessageAt != a.lastMessageAt ? b.lastMessageAt.compareTo(a.lastMessageAt) : foldVi(a.name).compareTo(foldVi(b.name)));

  List<Friend> get filteredFriends {
    final q = foldVi(searchQuery.trim());
    if (q.isEmpty) return conversations;
    final byId = results.where((r) => r.isFriend).map((r) => r.id).toSet();
    return conversations.where((f) => foldVi(f.name).contains(q) || foldVi(f.username).contains(q) || byId.contains(f.id)).toList();
  }

  /// Name shown for [f]: the own display name set on this device, else the real name.
  String nameOf(Friend f) => chat?.displayName(f.id, f.name) ?? f.name;

  List<SearchResult> get newPeople => results.where((r) => !r.isFriend).toList();

  void setSearch(String q) {
    searchQuery = q;
    _searchTimer?.cancel();
    final query = q.trim();
    searchError = '';
    if (query.isEmpty) {
      results = [];
      searching = false;
      _changed();
      return;
    }
    searching = true;
    _changed();
    _searchTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await api.get('/me/friends/search?q=${Uri.encodeQueryComponent(query)}') as Map;
        if (searchQuery.trim() != query) return;
        results = [
          for (final r in (res['results'] as List).cast<Map>())
            SearchResult(id: r['id'] as String, name: (r['name'] ?? '') as String, username: (r['username'] ?? '') as String, isFriend: r['isFriend'] == true, isAdmin: r['isAdmin'] == true),
        ];
      } catch (e) {
        searchError = e is ApiError ? e.message : 'Không tìm kiếm được';
      }
      searching = false;
      _changed();
    });
  }

  Future<void> addFriend(SearchResult r) async {
    addingId = r.id;
    _changed();
    try {
      final f = await api.post('/me/friends', {'userId': r.id}) as Map<String, dynamic>;
      if (!friends.any((x) => x.id == f['id'])) friends.insert(0, Friend.fromJson(f));
      r.isFriend = true;
      await chat?.rememberFriends([f]);
    } catch (e) {
      searchError = e is ApiError ? e.message : 'Không thêm được bạn bè';
    }
    addingId = null;
    _changed();
  }

  /// Returns an error message, or null on success.
  Future<String?> removeFriend(Friend f) async {
    try {
      await api.delete('/me/friends/${f.id}');
      friends.removeWhere((x) => x.id == f.id);
      _changed();
      return null;
    } catch (e) {
      return e is ApiError ? e.message : 'Không xoá được bạn bè';
    }
  }

  // ---- call history -----------------------------------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> callsWith(String friendId) async {
    if (call?.canCall != true) return const [];
    try {
      final res = await api.get('/me/calls?friendId=${Uri.encodeQueryComponent(friendId)}&limit=50') as Map;
      final list = [for (final c in (res['calls'] as List).cast<Map>()) Map<String, dynamic>.from(c)];
      unseenMissed = {for (final e in ((res['unseenMissed'] as Map?) ?? {}).entries) e.key as String: (e.value as num).toInt()};
      if (unseenMissed.containsKey(friendId)) {
        await api.post('/me/calls/seen', {'friendId': friendId});
        unseenMissed.remove(friendId);
      }
      _changed();
      return list;
    } catch (_) {
      return const []; // history is a nicety
    }
  }

  /// Opens a friend's chat state-wise: drops the badge and the notification.
  void markChatSeen(String friendId) {
    chat?.markRead(friendId);
    unawaited(notifier.cancel(noticeIdFor('msg:$friendId')));
    unawaited(notifier.cancel(noticeIdFor('missed:$friendId')));
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    screenshots.detach();
    unawaited(ringer.stop());
    unawaited(notifier.cancelAll());
    unawaited(background.apply(ServiceMode.off));
    _poll?.cancel();
    _searchTimer?.cancel();
    _frames?.cancel();
    socket.removeListener(_onSocket);
    chat?.removeListener(_onChat);
    call?.removeListener(_onCall);
    call?.dispose();
    socket.dispose();
    chat?.dispose();
    super.dispose();
  }
}
