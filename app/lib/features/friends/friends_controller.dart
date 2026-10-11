import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import '../../core/auth_store.dart';
import 'call_service.dart';
import 'chat_service.dart';
import 'chat_store.dart';
import 'realtime_socket.dart';

class Friend {
  Friend({required this.id, required this.name, required this.username, this.isAdmin = false, this.lastMessage, this.lastMessageAt = 0});
  final String id;
  final String name;
  final String username;
  final bool isAdmin;
  String? lastMessage;
  int lastMessageAt;

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

/// Everything behind the Bạn bè screen: the account, friend list, search/add, E2EE chat, calls and the one WebSocket
/// that serves them. Created when the screen opens; [dispose] closes the socket.
class FriendsController extends ChangeNotifier {
  FriendsController({required this.api, required this.auth});
  final ApiClient api;
  final AuthStore auth;

  late final RealtimeSocket socket = RealtimeSocket(tokenProvider: () => auth.token);
  ChatService? chat;
  CallService? call;
  String userId = '';
  String userName = '';
  bool loading = true;
  String loadError = '';
  List<Friend> friends = [];
  String myCode = '';
  bool noMyCode = false;
  Map<String, int> unseenMissed = {};
  int supportUnread = 0;
  String searchQuery = '';
  List<SearchResult> results = [];
  bool searching = false;
  String searchError = '';
  String? addingId;
  ({String friendId, String name, String preview})? lastIncoming;

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
      chat = ChatService(api: api, userId: userId, store: store, vault: vault, socket: socket)
        ..onIncoming = (id, name, preview) {
          lastIncoming = (friendId: id, name: name ?? friends.where((f) => f.id == id).map((f) => f.name).firstOrNull ?? 'Bạn bè', preview: preview);
          _changed();
        };
      call = CallService(api: api, socket: socket, canCall: !isAdmin);
      chat!.addListener(_onChat);
      call!.addListener(_onCall);
      socket.addListener(_onSocket);
      _frames = socket.frames.listen((m) {
        if (call!.onFrame(m)) return;
        chat!.onFrame(m);
      });
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

  int _lastEnded = 0;
  void _onCall() {
    final c = call!;
    if (c.endedTick != _lastEnded) {
      _lastEnded = c.endedTick;
      loadUnseenMissed();
    }
    _changed();
  }

  void _onSocket() {
    if (socket.ready) {
      if (!_wasReady) pollUnread(); // messages may have arrived while the socket was down
      chat?.loadFriendKeys().catchError((_) => <Map<String, dynamic>>[]);
    } else {
      call?.onSocketLost();
    }
    _wasReady = socket.ready;
    _changed();
  }

  /// App to the background: close the socket unless a call is running; foreground: reconnect.
  void setForeground(bool fg) {
    if (fg) {
      socket.start();
      socket.reconnectNow();
      pollUnread();
    } else if (call == null || call!.status == CallStatus.idle) {
      socket.stop();
    }
  }

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
      unseenMissed = {for (final e in ((res['unseenMissed'] as Map?) ?? {}).entries) e.key as String: (e.value as num).toInt()};
      _changed();
    } catch (_) {/* nicety */}
  }

  /// Fallback poll of the server's counters (web: notify.refresh): support replies from Admin.
  Future<void> pollUnread() async {
    try {
      final res = await api.get('/me/unread') as Map;
      supportUnread = (res['support'] as num?)?.toInt() ?? 0;
      _changed();
    } catch (_) {/* badges are a nicety */}
  }

  // ---- search / add / remove -------------------------------------------------------------------------------------------

  List<Friend> get filteredFriends {
    final q = foldVi(searchQuery.trim());
    if (q.isEmpty) return friends;
    final byId = results.where((r) => r.isFriend).map((r) => r.id).toSet();
    return friends.where((f) => foldVi(f.name).contains(q) || foldVi(f.username).contains(q) || byId.contains(f.id)).toList();
  }

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

  @override
  void dispose() {
    _disposed = true;
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
