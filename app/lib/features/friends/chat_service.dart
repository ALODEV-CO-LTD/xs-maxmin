import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/api_client.dart';
import 'chat_models.dart';
import 'chat_store.dart';
import 'e2ee_crypto.dart';
import 'realtime_socket.dart';

/// Where the private key lives (Android keystore-backed secure storage; a map in tests).
abstract class KeyVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class SecureKeyVault implements KeyVault {
  const SecureKeyVault([this._s = const FlutterSecureStorage()]);
  final FlutterSecureStorage _s;
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) => _s.write(key: key, value: value);
}

class MemoryKeyVault implements KeyVault {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

/// A picture ready to send: already re-encoded without metadata (see image_scrub.dart).
class OutgoingImage {
  const OutgoingImage(this.bytes, this.type);
  final Uint8List bytes;
  final String type;
}

/// End-to-end encrypted friend chat, a port of frontend/src/e2ee/chat.js. Messages are encrypted here, relayed over
/// the signalling WebSocket to a friend who is ONLINE (the server stores nothing; an offline friend means "not
/// sent") and kept only in the local store.
class ChatService extends ChangeNotifier {
  ChatService({
    required this.api,
    required this.userId,
    required this.store,
    required this.vault,
    required this.socket,
    this.ackWait = const Duration(seconds: 15),
    this.onIncoming,
  });

  final ApiClient api;
  final String userId;
  final ChatStore store;
  final KeyVault vault;
  final FrameSink socket;
  final Duration ackWait;

  /// Called for every message / notice received from a friend (friendId, preview) so the UI can show a banner.
  void Function(String friendId, String? friendName, String preview)? onIncoming;

  bool ready = false;
  String error = '';
  String myFingerprint = '';
  int tick = 0; // bumps whenever stored messages / statuses change
  final Map<String, PeerInfo> peerInfo = {};
  final Map<String, Map<String, dynamic>> friendKeys = {};
  final Map<String, int> unread = {};

  /// The friend whose conversation is on screen: its incoming messages are not counted as unread.
  String? openPeer;

  /// False while the app is in the background: then no conversation counts as "being read".
  bool foreground = true;

  E2eeIdentity? _identity;
  bool _disposed = false;
  final Map<String, ({Map<String, dynamic> jwk, Uint8List key})> _sessions = {};
  final Map<String, Timer> _ackTimers = {};
  final PartAssembler _assembler = PartAssembler();
  final Map<String, DateTime> _lastShot = {};
  Future<void> _inbox = Future.value(); // incoming frames are handled one at a time, in order

  String get _vaultKey => 'mamba_e2ee_identity_$userId';

  void _bump() {
    tick++;
    if (!_disposed) notifyListeners();
  }

  /// Creates the key pair on first use, publishes the public key if the server has a different one, loads the
  /// friends' keys. Safe to call again.
  Future<void> init() async {
    try {
      var id = E2eeIdentity.fromStorage(await _readKey());
      if (id == null) {
        id = E2eeIdentity.generate();
        await vault.write(_vaultKey, id.toStorage());
      }
      _identity = id;
      myFingerprint = await fingerprint(id.publicJwk);
      final remote = (await api.get('/me/e2ee-key') as Map)['publicKey'];
      if (!samePublicKey(id.publicJwk, remote is Map<String, dynamic> ? remote : null)) {
        await api.put('/me/e2ee-key', {'publicKey': id.publicJwk});
      }
      await _restoreUnread();
      await restorePrefs();
      ready = true;
      error = '';
      await loadFriendKeys();
      await applyRetentionAll();
    } catch (e) {
      ready = false;
      error = e is ApiError ? e.message : 'Không khởi tạo được mã hoá 2 đầu trên thiết bị này.';
    }
    if (!_disposed) notifyListeners();
  }

  Future<String?> _readKey() async {
    try {
      return await vault.read(_vaultKey);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> loadFriendKeys() async {
    final res = await api.get('/me/friends') as Map;
    final friends = [for (final f in (res['friends'] as List)) Map<String, dynamic>.from(f as Map)];
    await rememberFriends(friends);
    return friends;
  }

  /// Remembers each friend's public key and flags one that changed since we last saw it.
  Future<void> rememberFriends(List<Map<String, dynamic>> friends) async {
    for (final f in friends) {
      final id = f['id'] as String;
      final raw = f['publicKey'];
      if (raw is! Map || !isValidPublicJwk(raw)) {
        friendKeys.remove(id);
        continue;
      }
      final jwk = pickPublic(Map<String, dynamic>.from(raw));
      friendKeys[id] = jwk;
      final known = await store.peer(id);
      final fp = await fingerprint(jwk);
      if (known == null) {
        await store.putPeer(PeerRecord(id: id, jwk: jwk, fingerprint: fp, changed: false));
        peerInfo[id] = PeerInfo(fingerprint: fp, changed: false);
      } else if (!samePublicKey(known.jwk, jwk)) {
        await store.putPeer(PeerRecord(id: id, jwk: jwk, fingerprint: fp, changed: true));
        _sessions.remove(id);
        peerInfo[id] = PeerInfo(fingerprint: fp, changed: true);
      } else {
        peerInfo[id] = PeerInfo(fingerprint: fp, changed: known.changed);
      }
    }
    if (!_disposed) notifyListeners();
  }

  /// The user saw the "key changed" warning for this friend.
  Future<void> acceptKeyChange(String friendId) async {
    final known = await store.peer(friendId);
    if (known != null) await store.putPeer(PeerRecord(id: known.id, jwk: known.jwk, fingerprint: known.fingerprint, changed: false));
    final info = peerInfo[friendId];
    if (info != null) peerInfo[friendId] = PeerInfo(fingerprint: info.fingerprint, changed: false);
    if (!_disposed) notifyListeners();
  }

  Future<Uint8List?> _session(String friendId) async {
    final jwk = friendKeys[friendId];
    final id = _identity;
    if (jwk == null || id == null) return null;
    final cached = _sessions[friendId];
    if (cached != null && samePublicKey(cached.jwk, jwk)) return cached.key;
    final key = await deriveSessionKey(id, jwk, userId, friendId);
    _sessions[friendId] = (jwk: jwk, key: key);
    return key;
  }

  Future<List<ChatMessage>> messages(String friendId) async {
    await applyRetention(friendId); // messages that expired while the screen stayed open
    return store.messagesOf(friendId);
  }

  Future<Map<String, ChatMessage>> previews() => store.lastMessages();

  // ---- sending -----------------------------------------------------------------------------------------------

  /// Tells the friend (end-to-end encrypted like any message) that we took a screenshot; at most once per 20 s.
  Future<void> notifyScreenshot(String friendId) async {
    if (!ready || !friendKeys.containsKey(friendId)) return;
    final last = _lastShot[friendId];
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 20)) return;
    _lastShot[friendId] = DateTime.now();
    final msg = ChatMessage(id: newMessageId(), peerId: friendId, mine: true, text: '', createdAt: DateTime.now().millisecondsSinceEpoch, status: MsgStatus.sending, sys: SysKind.screenshotSent);
    await store.putMessage(msg);
    _bump();
    await _transmit(msg, null, null);
  }

  /// Sends [text] and/or one [image] to [friendId]. Throws a Vietnamese-message [Exception] for invalid input.
  Future<ChatMessage> send(String friendId, String text, {OutgoingImage? image}) async {
    if (!ready) throw Exception('Mã hoá 2 đầu chưa sẵn sàng trên thiết bị này.');
    final id = newMessageId();
    ChatAttachment? att;
    String? ext;
    if (image != null) {
      if (!allowedImageTypes.contains(image.type)) throw Exception(imageOnlyMessage);
      if (image.bytes.length > maxAttachmentBytes) throw Exception('Tệp quá lớn (tối đa 5 MB)');
      ext = imageExt(image.type);
      att = ChatAttachment(name: anonymousName(image.type, () => DateTime.now().microsecondsSinceEpoch & 0xff), type: image.type, size: image.bytes.length, path: await store.writeFile(id, image.bytes, ext));
    }
    final msg = ChatMessage(id: id, peerId: friendId, mine: true, text: text, att: att, createdAt: DateTime.now().millisecondsSinceEpoch, status: MsgStatus.sending);
    await store.putMessage(msg);
    _bump();
    await _transmit(msg, image?.bytes, att);
    return msg;
  }

  Future<void> _transmit(ChatMessage msg, Uint8List? fileBytes, ChatAttachment? att) async {
    Future<void> fail(String reason) => _setStatus(msg.id, MsgStatus.failed, reason);
    try {
      final key = await _session(msg.peerId);
      if (key == null) return await fail('no-key');
      if (!socket.ready) return await fail('no-socket');
      var bytes = fileBytes;
      final a = att ?? msg.att;
      if (a != null && bytes == null && a.path != null) bytes = await store.readFile(a.path!);
      final plain = packMessage(
        text: msg.text,
        ts: msg.createdAt,
        att: a == null ? null : {'name': a.name, 'type': a.type, 'size': a.size},
        kind: msg.sys == SysKind.screenshotSent ? 'screenshot' : null,
        file: bytes,
      );
      final env = await encryptBytes(key, plain, from: userId, to: msg.peerId, id: msg.id);
      final slices = splitCiphertext(env.ct);
      if (slices.length > maxParts) return await fail('invalid');
      for (var i = 0; i < slices.length; i++) {
        socket.send({'type': 'e2ee-msg', 'to': msg.peerId, 'id': msg.id, 'iv': env.iv, 'ct': slices[i], 'part': i, 'parts': slices.length, 'ts': msg.createdAt});
      }
      await _setStatus(msg.id, MsgStatus.sent);
      _ackTimers[msg.id]?.cancel();
      _ackTimers[msg.id] = Timer(ackWait, () => _setStatus(msg.id, MsgStatus.failed, 'timeout'));
    } catch (_) {
      await fail('invalid');
    }
  }

  /// "Gửi lại" for a failed message.
  Future<void> retry(String messageId) async {
    final m = await store.message(messageId);
    if (m == null || !m.mine) return;
    await _setStatus(m.id, MsgStatus.sending);
    await _transmit(m.copyWith(status: MsgStatus.sending), null, null);
  }

  Future<void> _setStatus(String id, String status, [String? reason]) async {
    final m = await store.message(id);
    if (m == null) return;
    if (status != MsgStatus.sent) {
      _ackTimers.remove(id)?.cancel();
    }
    // A late timeout must not overwrite a delivery that already happened.
    if (m.status == MsgStatus.delivered && status == MsgStatus.failed) return;
    await store.putMessage(ChatMessage(
      id: m.id,
      peerId: m.peerId,
      mine: m.mine,
      text: m.text,
      createdAt: m.createdAt,
      status: status,
      att: m.att,
      sys: m.sys,
      reason: status == MsgStatus.failed ? reason : null,
    ));
    _bump();
  }

  // ---- receiving ---------------------------------------------------------------------------------------------

  /// Handles `e2ee-msg`, `e2ee-ack` and `e2ee-undelivered` frames from the socket (others are ignored).
  Future<void> onFrame(Map<String, dynamic> msg) {
    final type = msg['type'];
    if (type != 'e2ee-msg' && type != 'e2ee-ack' && type != 'e2ee-undelivered') return Future.value();
    _inbox = _inbox.then((_) => _handle(msg)).catchError((_) {});
    return _inbox;
  }

  Future<void> _handle(Map<String, dynamic> msg) async {
    final type = msg['type'];
    final id = msg['id'];
    if (type == 'e2ee-ack') {
      if (id is String) await _setStatus(id, MsgStatus.delivered);
      return;
    }
    if (type == 'e2ee-undelivered') {
      if (id is String) await _setStatus(id, MsgStatus.failed, msg['reason'] as String?);
      return;
    }
    final parsed = E2eeFrame.tryParse(msg);
    if (parsed == null) return;
    final frame = _assembler.add(parsed);
    if (frame == null) return;
    try {
      if (await store.message(frame.id) != null) return; // duplicate
      if (!friendKeys.containsKey(frame.from)) await loadFriendKeys(); // new friend / new device
      var key = await _session(frame.from);
      if (key == null) return;
      final env = Envelope(frame.iv, frame.ct);
      Uint8List plain;
      try {
        plain = await decryptBytes(key, env, from: frame.from, to: userId, id: frame.id);
      } catch (_) {
        await loadFriendKeys(); // their key may have changed; retry once with a fresh one
        key = await _session(frame.from);
        if (key == null) return;
        plain = await decryptBytes(key, env, from: frame.from, to: userId, id: frame.id);
      }
      final m = unpackMessage(plain);
      final createdAt = m.ts < DateTime.now().millisecondsSinceEpoch ? m.ts : DateTime.now().millisecondsSinceEpoch;
      if (m.kind == 'screenshot') {
        await store.putMessage(ChatMessage(id: frame.id, peerId: frame.from, mine: false, text: '', createdAt: createdAt, status: MsgStatus.delivered, sys: SysKind.screenshot));
        socket.send({'type': 'e2ee-ack', 'to': frame.from, 'id': frame.id});
        _bump();
        await _bumpUnread(frame.from);
        onIncoming?.call(frame.from, frame.fromName, 'đã chụp màn hình cuộc trò chuyện với bạn');
        return;
      }
      // Only pictures are accepted from a friend (a modified client could send anything).
      ChatAttachment? att;
      final a = m.att;
      final aType = a?['type'];
      if (a != null && m.file.isNotEmpty && aType is String && allowedImageTypes.contains(aType) && sniffImageType(m.file) != null) {
        final name = (a['name'] ?? 'tep-dinh-kem').toString();
        att = ChatAttachment(
          name: name.length > 200 ? name.substring(0, 200) : name,
          type: aType,
          size: m.file.length,
          path: await store.writeFile(frame.id, Uint8List.fromList(m.file), imageExt(aType)),
        );
      }
      await store.putMessage(ChatMessage(id: frame.id, peerId: frame.from, mine: false, text: m.text, att: att, createdAt: createdAt, status: MsgStatus.delivered));
      socket.send({'type': 'e2ee-ack', 'to': frame.from, 'id': frame.id});
      _bump();
      await _bumpUnread(frame.from);
      onIncoming?.call(frame.from, frame.fromName, m.text.isNotEmpty ? m.text : 'Đã gửi một tệp đính kèm');
    } catch (_) {
      // Could not read an incoming message (wrong key, tampered, malformed): drop it silently like the web.
    }
  }

  // ---- unread counters, kept on this device -----------------------------------------------------------------------

  Future<void> _bumpUnread(String friendId) async {
    if (foreground && openPeer == friendId) return;
    final n = (unread[friendId] ?? 0) + 1;
    unread[friendId] = n;
    await store.setMeta('unread:$friendId', '$n');
    if (!_disposed) notifyListeners();
  }

  Future<void> _restoreUnread() async {
    for (final e in (await store.metaWithPrefix('unread:')).entries) {
      final n = int.tryParse(e.value) ?? 0;
      if (n > 0) unread[e.key.substring(7)] = n;
    }
  }

  Future<void> markRead(String friendId) async {
    if (unread.remove(friendId) != null) {
      await store.setMeta('unread:$friendId', null);
      if (!_disposed) notifyListeners();
    }
  }

  // ---- per-friend auto-delete, applied on this device -----------------------------------------------------------

  Future<RetentionRule?> retentionOf(String friendId) async => RetentionRule.tryParse(await store.meta('retention:$friendId'));

  Future<void> setRetention(String friendId, RetentionRule? rule) async {
    await store.setMeta('retention:$friendId', rule?.toJson());
    await applyRetention(friendId);
  }

  Future<void> applyRetention(String friendId) async {
    final rule = await retentionOf(friendId);
    if (rule == null) return;
    final old = expiredMessages(await store.messagesOf(friendId), rule, DateTime.now().millisecondsSinceEpoch);
    for (final m in old) {
      await store.deleteMessage(m.id);
    }
    if (old.isNotEmpty) _bump();
  }

  Future<void> applyRetentionAll() async {
    for (final k in (await store.metaWithPrefix('retention:')).keys) {
      await applyRetention(k.substring(10));
    }
  }

  // ---- per-device notes: pins, own display names, archive (never uploaded; web keeps the same things locally) ------------

  /// friendId -> own display name for that conversation (shown on this device only).
  final Map<String, String> aliases = {};

  /// Conversations hidden from the Tin nhắn list ("Lưu trữ").
  final Set<String> archived = {};

  /// Loads aliases and the archive from the local store. Called by [init].
  Future<void> restorePrefs() async {
    aliases
      ..clear()
      ..addEntries([for (final e in (await store.metaWithPrefix('alias:')).entries) if (e.value.isNotEmpty) MapEntry(e.key.substring(6), e.value)]);
    archived
      ..clear()
      ..addAll(_decodeList(await store.meta('archive')));
  }

  static List<String> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [for (final x in (jsonDecode(raw) as List)) if (x is String) x];
    } catch (_) {
      return const [];
    }
  }

  String displayName(String friendId, String realName) => aliases[friendId] ?? realName;

  /// Saves (or clears, when empty or equal to the real name) the own display name; only this device sees it.
  Future<void> setAlias(String friendId, String alias, String realName) async {
    final a = alias.trim();
    if (a.isEmpty || a == realName) {
      aliases.remove(friendId);
      await store.setMeta('alias:$friendId', null);
    } else {
      aliases[friendId] = a;
      await store.setMeta('alias:$friendId', a);
    }
    if (!_disposed) notifyListeners();
  }

  /// Archives ([on]) or restores the conversations; they stay on the device, only hidden from the list.
  Future<void> setArchived(Iterable<String> ids, bool on) async {
    if (on) {
      archived.addAll(ids);
    } else {
      archived.removeAll(ids.toSet());
    }
    await store.setMeta('archive', archived.isEmpty ? null : jsonEncode(archived.toList()));
    if (!_disposed) notifyListeners();
  }

  /// Ids of the messages pinned in this conversation (oldest pin first).
  Future<List<String>> pinsOf(String friendId) async => _decodeList(await store.meta('pin:$friendId'));

  /// Pins the message, or unpins it when it was pinned. Returns the new list.
  Future<List<String>> togglePin(String friendId, String messageId) async {
    final pins = [...await pinsOf(friendId)];
    pins.contains(messageId) ? pins.remove(messageId) : pins.add(messageId);
    await store.setMeta('pin:$friendId', pins.isEmpty ? null : jsonEncode(pins));
    return pins;
  }

  /// Deletes one message from THIS device only (the friend keeps theirs), with its pin and decoding notes.
  Future<void> deleteMessage(String friendId, String id) async {
    await store.deleteMessage(id);
    await store.setMeta('decode:$id', null);
    final pins = await pinsOf(friendId);
    if (pins.contains(id)) await store.setMeta('pin:$friendId', pins.length == 1 ? null : jsonEncode(pins.where((x) => x != id).toList()));
    _bump();
  }

  /// Deletes the whole conversation from THIS device only. The friend stays in the contact list.
  Future<void> deleteConversation(String friendId) async {
    for (final m in await store.messagesOf(friendId)) {
      await store.deleteMessage(m.id);
      await store.setMeta('decode:${m.id}', null);
    }
    await store.setMeta('pin:$friendId', null);
    _bump();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _ackTimers.values) {
      t.cancel();
    }
    _ackTimers.clear();
    // Wipe what is only needed while signed in: derived session keys and the private key held in memory.
    _sessions.clear();
    _identity = null;
    friendKeys.clear();
    peerInfo.clear();
    unread.clear();
    ready = false;
    store.close();
    super.dispose();
  }
}
