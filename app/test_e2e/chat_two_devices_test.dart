// Chat giữa hai thiết bị thật (mã app thật + máy chủ thật, không giả): kiểm tra gửi / nhận / xác nhận / offline / gửi lại
// và giới hạn "cùng một tài khoản trên hai máy". Chạy bằng tools/test_chat_e2e.sh (tự dựng máy chủ thử cô lập, KHÔNG đụng dữ liệu thật).
//   Android và iOS dùng cùng một mã Dart (mã hoá, kết nối, giao thức), nên "thiết bị" ở đây là hai phiên bản độc lập của
//   mã đó, mỗi bên có kho khoá và kho tin nhắn riêng, nối tới máy chủ qua WebSocket thật.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/config.dart';
import 'package:mamba_app/features/friends/chat_models.dart';
import 'package:mamba_app/features/friends/chat_service.dart';
import 'package:mamba_app/features/friends/chat_store.dart';
import 'package:mamba_app/features/friends/realtime_socket.dart';

final _run = DateTime.now().millisecondsSinceEpoch.toString().substring(6);

Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body, {String? token}) async {
  final r = await http.post(Uri.parse('${AppConfig.api}$path'), headers: {'content-type': 'application/json', if (token != null) 'authorization': 'Bearer $token'}, body: jsonEncode(body));
  final j = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
  if (r.statusCode >= 400) fail('POST $path -> ${r.statusCode} ${r.body}');
  return j;
}

class Account {
  Account(this.name, this.username, this.id, this.token);
  final String name, username, id, token;
}

Future<Account> _register(String name) async {
  final username = '${name.toLowerCase()}$_run';
  final reg = await _post('/auth/register', {'name': name, 'username': username, 'password': 'Mat-khau-1A', 'secondPassword': 'Lop-hai-2B'});
  final t = await _post('/auth/step2', {'pendingToken': reg['pendingToken'], 'password': 'Lop-hai-2B'});
  final token = t['token'] as String;
  final me = await http.get(Uri.parse('${AppConfig.api}/me'), headers: {'authorization': 'Bearer $token'});
  return Account(name, username, (jsonDecode(me.body) as Map)['id'] as String, token);
}

Future<void> _befriend(Account a, Account b) async {
  await _post('/me/friends', {'userId': b.id}, token: a.token);
  final inc = await http.get(Uri.parse('${AppConfig.api}/me/friend-requests'), headers: {'authorization': 'Bearer ${b.token}'});
  final id = ((jsonDecode(inc.body) as Map)['incoming'] as List).first['id'];
  await _post('/me/friend-requests/$id/accept', {}, token: b.token);
}

/// One phone: its own key vault + message store + WebSocket, signed in as [who].
class Device {
  Device(this.label, this.who);
  final String label;
  final Account who;
  late final auth = AuthStore()..token = who.token;
  late final api = ApiClient(auth);
  late final socket = RealtimeSocket(tokenProvider: () => who.token);
  final store = MemoryChatStore();
  final vault = MemoryKeyVault();
  late ChatService chat;
  StreamSubscription<Map<String, dynamic>>? _sub;

  Future<void> start({MemoryKeyVault? sharedVault}) async {
    chat = ChatService(api: api, userId: who.id, store: store, vault: sharedVault ?? vault, socket: socket, ackWait: const Duration(seconds: 5));
    _sub = socket.frames.listen(chat.onFrame);
    socket.start();
    await until(() => socket.ready, 'socket of $label');
    await chat.init();
    expect(chat.ready, isTrue, reason: '${chat.error}');
  }

  Future<void> stop() async {
    await _sub?.cancel();
    socket.stop();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<List<ChatMessage>> texts(String peer) async => (await chat.messages(peer)).where((m) => m.sys == null).toList();
}

Future<void> until(bool Function() ok, String what, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timeout: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Future<void> untilAsync(Future<bool> Function() ok, String what, {Duration timeout = const Duration(seconds: 10)}) async {
  final end = DateTime.now().add(timeout);
  while (!await ok()) {
    if (DateTime.now().isAfter(end)) fail('timeout: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  if (!AppConfig.apiBase.contains('localhost') && !AppConfig.apiBase.contains('127.0.0.1')) {
    test('needs API_BASE=http://localhost:<port> (tools/test_chat_e2e.sh)', () => fail('refusing to run against ${AppConfig.apiBase}'));
    return;
  }

  late Account huong, minh; // "huong" is on the Android phone, "minh" on the iPhone
  setUpAll(() async {
    huong = await _register('Huong');
    minh = await _register('Minh');
    await _befriend(huong, minh);
  });

  test('Android -> iPhone -> Android: text arrives decrypted, is acknowledged, and the reply comes back', () async {
    final android = Device('android', huong), ios = Device('ios', minh);
    await android.start();
    await ios.start();
    await android.chat.loadFriendKeys();
    await ios.chat.loadFriendKeys();

    final sent = await android.chat.send(minh.id, 'xin chào từ Android 12 x 5');
    await untilAsync(() async => (await ios.texts(huong.id)).any((m) => m.text == 'xin chào từ Android 12 x 5'), 'iPhone receives');
    await untilAsync(() async => (await android.texts(minh.id)).firstWhere((m) => m.id == sent.id).status == MsgStatus.delivered, 'Android sees the acknowledgement');

    final back = await ios.chat.send(huong.id, 'chào lại từ iPhone');
    await untilAsync(() async => (await android.texts(minh.id)).any((m) => !m.mine && m.text == 'chào lại từ iPhone'), 'Android receives the reply');
    await untilAsync(() async => (await ios.texts(huong.id)).firstWhere((m) => m.id == back.id).status == MsgStatus.delivered, 'iPhone sees the acknowledgement');

    await android.stop();
    await ios.stop();
  });

  test('a long message with accents and emoji survives the round trip unchanged', () async {
    final android = Device('android', huong), ios = Device('ios', minh);
    await android.start();
    await ios.start();
    await android.chat.loadFriendKeys();
    final text = 'Đề 12 x 5, xiên 23-45 x 10 💰\n' * 60;
    await android.chat.send(minh.id, text);
    await untilAsync(() async => (await ios.texts(huong.id)).any((m) => m.text == text), 'iPhone receives the long text');
    await android.stop();
    await ios.stop();
  });

  test('friend offline: the sender is told ("offline"), and Gửi lại works once the friend is back', () async {
    final android = Device('android', huong);
    await android.start();
    await android.chat.loadFriendKeys();
    final m = await android.chat.send(minh.id, 'gửi khi iPhone đang tắt');
    await untilAsync(() async => (await android.texts(minh.id)).firstWhere((x) => x.id == m.id).status == MsgStatus.failed, 'marked failed');
    expect((await android.texts(minh.id)).firstWhere((x) => x.id == m.id).reason, 'offline');

    final ios = Device('ios', minh);
    await ios.start();
    await android.chat.loadFriendKeys();
    await android.chat.retry(m.id);
    await untilAsync(() async => (await ios.texts(huong.id)).any((x) => x.text == 'gửi khi iPhone đang tắt'), 'iPhone gets the resent message');
    await untilAsync(() async => (await android.texts(minh.id)).firstWhere((x) => x.id == m.id).status == MsgStatus.delivered, 'resent message acknowledged');
    await android.stop();
    await ios.stop();
  });

  test('the same account on a SECOND phone replaces the key: the first phone can no longer read new messages (known limitation)', () async {
    final iosA = Device('ios-1', minh), android = Device('android', huong);
    await iosA.start();
    await android.start();
    await android.chat.loadFriendKeys();

    // a second phone (fresh key vault) signs in to the same account and publishes its own key
    final iosB = Device('ios-2', minh);
    await iosB.start();
    await android.chat.loadFriendKeys(); // Android now encrypts to the second phone's key

    await android.chat.send(minh.id, 'tin sau khi máy thứ hai đăng nhập');
    await untilAsync(() async => (await iosB.texts(huong.id)).any((m) => m.text == 'tin sau khi máy thứ hai đăng nhập'), 'second phone reads it');
    await Future<void>.delayed(const Duration(seconds: 1));
    expect((await iosA.texts(huong.id)).any((m) => m.text == 'tin sau khi máy thứ hai đăng nhập'), isFalse, reason: 'the first phone cannot decrypt (different key)');
    await iosA.stop();
    await iosB.stop();
    await android.stop();
  });
}
