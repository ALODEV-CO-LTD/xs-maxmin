import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/package_events.dart';
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
  SearchResult({required this.id, required this.name, required this.username, required this.isFriend, this.isAdmin = false, this.requestState = 'none'});
  final String id;
  final String name;
  final String username;
  final bool isAdmin;
  bool isFriend;

  /// 'none' | 'outgoing' (I already asked them) | 'incoming' (they asked me: accepting adds them at once).
  String requestState;
}

/// A pending friend request. [incoming]: someone asked me; otherwise I asked them. [userId]/[name]/[username] are the
/// OTHER person's.
class FriendRequest {
  const FriendRequest({required this.id, required this.userId, required this.name, required this.username, required this.incoming, this.createdAt = 0});
  final String id;
  final String userId;
  final String name;
  final String username;
  final bool incoming;
  final Object createdAt;

  factory FriendRequest.incomingFrom(Map j) => FriendRequest(id: '${j['id']}', userId: '${j['fromId']}', name: (j['fromName'] ?? '') as String, username: (j['fromUsername'] ?? '') as String, incoming: true, createdAt: j['createdAt'] ?? 0);
  factory FriendRequest.outgoingTo(Map j) => FriendRequest(id: '${j['id']}', userId: '${j['toId']}', name: (j['toName'] ?? '') as String, username: (j['toUsername'] ?? '') as String, incoming: false, createdAt: j['createdAt'] ?? 0);
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

/// Red number on the Bạn bè entry: how many CONVERSATIONS need a look (a chat with unread messages or an unseen missed
/// call counts once, however many messages it holds), plus 1 when Admin has replied and one per pending friend request.
int unreadBadgeCount({Map<String, int> chat = const {}, Map<String, int> missed = const {}, int support = 0, int friendRequests = 0}) {
  final ids = <String>{
    for (final e in chat.entries) if (e.value > 0) e.key,
    for (final e in missed.entries) if (e.value > 0) e.key,
  };
  return ids.length + (support > 0 ? 1 : 0) + (friendRequests < 0 ? 0 : friendRequests);
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
  FriendsController({required this.api, required this.auth, AppNotifier? notifier, CallRinger? ringer, BackgroundService? background, RealtimeSocket? socket}) : notifier = notifier ?? const NoopNotifier(), ringer = ringer ?? SilentRinger(), background = background ?? const NoopBackgroundService(), socket = socket ?? RealtimeSocket(tokenProvider: () => auth.token) {
    this.socket.deviceIdProvider ??= () => chat?.myDeviceId;
    // Server closed the socket with 4401 (session revoked): sign out, do not reconnect in a loop.
    this.socket.onSessionRevoked ??= auth.clear;
    screenshots = ScreenshotBridge(openPeer: () => chat?.openPeer, isForeground: () => foreground, canNotify: (id) => !(friends.where((f) => f.id == id).firstOrNull?.isAdmin ?? false), notify: (id) async => chat?.notifyScreenshot(id));
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

  /// Friend requests: who asked me (incoming) and whom I asked (outgoing). [pendingIncoming] is the red badge: the
  /// server's counter from `/me/unread`, bumped at once by a live `friend-request` event.
  List<FriendRequest> incomingRequests = [];
  List<FriendRequest> outgoingRequests = [];
  int pendingIncoming = 0;

  /// Result of the last add: "Đã gửi lời mời kết bạn tới X. Họ cần chấp nhận."
  String addNotice = '';
  String? requestBusyId;

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
        if (m['type'] == 'friend-request') {
          _onFriendRequest(m);
          return;
        }
        if (m['type'] == 'friend-accepted') {
          _onFriendAccepted(m);
          return;
        }
        if (m['type'] == 'payment-decided') {
          _onPaymentDecided(m);
          return;
        }
        chat!.onFrame(m);
      });
      screenshots.attach();
      await _loadSettings();
      await chat!.prepareDevice(); // the socket must open with this install's device id
      socket.start();
      await Future.wait([chat!.init(), _loadFriends(), if (!isAdmin) _loadMyCode(), if (!isAdmin) loadUnseenMissed(), loadRequests()]);
      await refreshFriendList(quiet: true);
      unawaited(pollUnread());
      _poll = Timer.periodic(const Duration(seconds: 60), (_) => pollUnread());
    } catch (e) {
      loadError = e is ApiError ? e.message : 'Không tải được danh sách bạn bè';
    }
    loading = false;
    _changed();
  }

  // Never re-download the list from here: loading friends notifies the chat, which would loop forever for an empty list.
  void _onChat() => refreshFriendList(quiet: true, reload: false);

  Future<void> _loadSettings() async {
    keepAlive = await KeepAliveSettings.load();
    try {
      _notifAsked = (await SharedPreferences.getInstance()).getBool('mamba_notif_asked') ?? false;
    } catch (_) {
      /* ask again */
    }
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

  /// `friend-request` event: someone asked to be my friend. Like a new message: a banner on screen, a notification in the
  /// background; the list and the badge refresh.
  void _onFriendRequest(Map<String, dynamic> m) {
    final from = (m['fromId'] ?? '') as String;
    final name = ((m['fromName'] ?? '') as String).trim().isEmpty ? 'Một người' : (m['fromName'] as String).trim();
    final known = incomingRequests.any((r) => r.id == '${m['requestId']}');
    if (!known) pendingIncoming++;
    if (foreground) {
      _banner(AppBanner(title: 'Lời mời kết bạn', body: '$name gửi lời mời kết bạn', route: '/friends'));
    } else {
      unawaited(notifier.show(friendRequestNotice(from, name)));
    }
    _changed();
    unawaited(loadRequests());
  }

  /// `payment-decided` event: Admin approved or rejected the package payment. Tell the customer and make the screens that show the
  /// package read it again (the card on Tổng quan, Gói & Thanh toán).
  void _onPaymentDecided(Map<String, dynamic> m) {
    final approved = m['status'] == 'approved';
    final reason = (m['reason'] as String?)?.trim() ?? '';
    PackageEvents.instance.bump();
    if (foreground) {
      _banner(AppBanner(
        title: 'Gói dịch vụ',
        body: approved ? 'Gói của bạn đã được gia hạn' : 'Yêu cầu gói chưa được duyệt${reason.isEmpty ? '' : ': $reason'}',
        route: approved ? '/overview' : '/account?tab=packages',
      ));
    } else {
      unawaited(notifier.show(paymentNotice(approved: approved)));
    }
    _changed();
  }

  /// `friend-accepted` event: they accepted my request. Reload the list (and the keys) so the chat works.
  void _onFriendAccepted(Map<String, dynamic> m) {
    final id = (m['friendId'] ?? '') as String;
    final name = ((m['name'] ?? '') as String).trim().isEmpty ? 'Một người' : (m['name'] as String).trim();
    outgoingRequests.removeWhere((r) => r.userId == id);
    if (foreground) {
      _banner(AppBanner(title: 'Kết bạn', body: '$name đã chấp nhận lời mời', route: '/friends'));
    } else {
      unawaited(notifier.show(friendAcceptedNotice(id, name)));
    }
    _changed();
    unawaited(_reloadFriends());
    unawaited(loadRequests());
  }

  /// Full reload of the friend rows and keys (a friend was added on the other side).
  Future<void> _reloadFriends() async {
    if (chat == null) return;
    try {
      await _loadFriends();
    } catch (_) {
      /* the next refresh retries */
    }
    await refreshFriendList(quiet: true);
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
    } catch (_) {
      /* fine */
    }
    _changed();
  }

  /// Asks for the notification permission (Android 13+). Without `force` it asks only once per install, at the first
  /// visit to Bạn bè, not at launch.
  Future<bool> requestNotificationPermission({bool force = false}) async {
    if (!force && _notifAsked) return notifier.allowed;
    _notifAsked = true;
    try {
      await (await SharedPreferences.getInstance()).setBool('mamba_notif_asked', true);
    } catch (_) {
      /* fine */
    }
    if (await notifier.allowed) return true;
    return notifier.requestPermission();
  }

  void _onSocket() {
    if (socket.ready) {
      if (!_wasReady) {
        pollUnread(); // messages may have arrived while the socket was down
        loadUnseenMissed();
        loadRequests();
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
      loadRequests();
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
  int get unreadTotal => unreadBadgeCount(chat: chat?.unread ?? const {}, missed: unseenMissed, support: supportUnread, friendRequests: pendingIncoming);

  Future<void> _loadFriends() async {
    final list = await chat!.loadFriendKeys();
    friends = [for (final f in list) Friend.fromJson(f)];
  }

  /// Reloads the list from the server and merges the local last-message previews.
  Future<void> refreshFriendList({bool quiet = false, bool reload = true}) async {
    final c = chat;
    if (c == null) return;
    try {
      if (!quiet) loading = true;
      final prev = await c.previews();
      if (reload && (!quiet || friends.isEmpty)) await _loadFriends();
      for (final f in friends) {
        f.lastMessage = prev[f.id]?.preview;
        f.lastMessageAt = prev[f.id]?.createdAt ?? 0;
      }
      friends.sort((a, b) => b.lastMessageAt != a.lastMessageAt ? b.lastMessageAt.compareTo(a.lastMessageAt) : foldVi(a.name).compareTo(foldVi(b.name)));
      groups = [for (final g in c.groups.values) Friend(id: g.id, name: g.name, username: '', isGroup: true, memberCount: g.members.length, lastMessage: prev[g.id] == null ? null : '${prev[g.id]!.mine ? 'Bạn' : c.memberName(g, prev[g.id]!.fromId ?? '')}: ${prev[g.id]!.preview}', lastMessageAt: prev[g.id]?.createdAt ?? g.updatedAt)]..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
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
    } catch (_) {
      /* the card simply stays hidden */
    }
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
    } catch (_) {
      /* nicety */
    }
  }

  /// Fallback poll of the server's counters (web: notify.refresh): support replies from Admin.
  Future<void> pollUnread() async {
    try {
      final res = await api.get('/me/unread') as Map;
      supportUnread = supportVisible ? 0 : (res['support'] as num?)?.toInt() ?? 0;
      final fr = (res['friendRequests'] as num?)?.toInt();
      if (fr != null) {
        final changed = fr != pendingIncoming || fr != incomingRequests.length;
        pendingIncoming = fr < 0 ? 0 : fr;
        if (changed) unawaited(loadRequests());
      }
      if (supportVisible && ((res['support'] as num?)?.toInt() ?? 0) > 0) unawaited(markSupportRead());
      _changed();
    } catch (_) {
      /* badges are a nicety */
    }
  }

  /// The Admin thread is being read: drop its badge and tell the server so it stays read (web: notify.clear('support')).
  Future<void> markSupportRead() async {
    if (supportUnread != 0) {
      supportUnread = 0;
      _changed();
    }
    try {
      await api.post('/me/unread/read', {'peerId': 'support'});
    } catch (_) {
      /* a nicety: the next poll corrects it */
    }
  }

  // ---- friend requests --------------------------------------------------------------------------------------------------

  Future<void> loadRequests() async {
    try {
      final res = await api.get('/me/friend-requests') as Map;
      incomingRequests = [for (final r in ((res['incoming'] as List?) ?? const []).cast<Map>()) FriendRequest.incomingFrom(r)];
      outgoingRequests = [for (final r in ((res['outgoing'] as List?) ?? const []).cast<Map>()) FriendRequest.outgoingTo(r)];
      pendingIncoming = incomingRequests.length;
      _changed();
    } catch (_) {
      /* the block stays as it was */
    }
  }

  /// Adds [f] (from the answer of accept / add) to the list and remembers its key. The E2EE key comes with the row.
  Future<void> _gotFriend(Map f) async {
    final row = Map<String, dynamic>.from(f);
    if (!friends.any((x) => x.id == row['id'])) friends.insert(0, Friend.fromJson(row));
    await chat?.rememberFriends([row]);
  }

  /// Accepts a request. Returns an error message, or null.
  Future<String?> acceptRequest(FriendRequest r) async {
    requestBusyId = r.id;
    _changed();
    try {
      final res = await api.post('/me/friend-requests/${Uri.encodeComponent(r.id)}/accept') as Map;
      final f = res['friend'];
      if (f is Map) {
        await _gotFriend(f);
      } else {
        await _reloadFriends();
      }
      _dropIncoming(r);
      requestBusyId = null;
      _changed();
      return null;
    } catch (e) {
      requestBusyId = null;
      _changed();
      unawaited(loadRequests());
      return e is ApiError ? e.message : 'Không chấp nhận được lời mời';
    }
  }

  Future<String?> declineRequest(FriendRequest r) async {
    requestBusyId = r.id;
    _changed();
    try {
      await api.post('/me/friend-requests/${Uri.encodeComponent(r.id)}/decline');
      _dropIncoming(r);
      requestBusyId = null;
      _changed();
      return null;
    } catch (e) {
      requestBusyId = null;
      _changed();
      unawaited(loadRequests());
      return e is ApiError ? e.message : 'Không từ chối được lời mời';
    }
  }

  /// Cancels a request I sent.
  Future<String?> cancelRequest(FriendRequest r) async {
    requestBusyId = r.id;
    _changed();
    try {
      await api.delete('/me/friend-requests/${Uri.encodeComponent(r.id)}');
      outgoingRequests.removeWhere((x) => x.id == r.id);
      for (final s in results) {
        if (s.id == r.userId) s.requestState = 'none';
      }
      requestBusyId = null;
      _changed();
      return null;
    } catch (e) {
      requestBusyId = null;
      _changed();
      unawaited(loadRequests());
      return e is ApiError ? e.message : 'Không huỷ được lời mời';
    }
  }

  void _dropIncoming(FriendRequest r) {
    incomingRequests.removeWhere((x) => x.id == r.id);
    pendingIncoming = incomingRequests.length;
    for (final s in results) {
      if (s.id == r.userId) {
        s.isFriend = true;
        s.requestState = 'none';
      }
    }
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
    addNotice = '';
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
        results = [for (final r in (res['results'] as List).cast<Map>()) SearchResult(id: r['id'] as String, name: (r['name'] ?? '') as String, username: (r['username'] ?? '') as String, isFriend: r['isFriend'] == true, isAdmin: r['isAdmin'] == true, requestState: _requestState(r['requestState']))];
      } catch (e) {
        searchError = e is ApiError ? e.message : 'Không tìm kiếm được';
      }
      searching = false;
      _changed();
    });
  }

  static String _requestState(Object? v) => v == 'outgoing' || v == 'incoming' ? v as String : 'none';

  /// "Kết bạn": the other person must accept, so this normally only SENDS a request (`status: pending`). `status: friends`
  /// (already friends, or they had asked me first) adds the friend at once.
  Future<void> addFriend(SearchResult r) async {
    addingId = r.id;
    addNotice = '';
    searchError = '';
    _changed();
    try {
      final res = await api.post('/me/friends', {'userId': r.id}) as Map;
      final friend = res['friend'] is Map ? res['friend'] as Map : null;
      if (res['status'] == 'friends' || (res['status'] == null && friend != null)) {
        if (friend != null) await _gotFriend(friend);
        r.isFriend = true;
        r.requestState = 'none';
        incomingRequests.removeWhere((x) => x.userId == r.id);
        pendingIncoming = incomingRequests.length;
        if (friend == null) unawaited(_reloadFriends());
      } else {
        r.requestState = 'outgoing';
        addNotice = 'Đã gửi lời mời kết bạn tới ${r.name}. Họ cần chấp nhận.';
        unawaited(loadRequests());
      }
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
