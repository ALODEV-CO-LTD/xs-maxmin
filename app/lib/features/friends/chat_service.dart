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
  const SecureKeyVault([this._s = const FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device))]);
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
  ChatService({required this.api, required this.userId, required this.store, required this.vault, required this.socket, this.ackWait = const Duration(seconds: 15), this.onIncoming});

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

  /// The newest key of each friend (is there a key at all? and what the older single-key code reads).
  final Map<String, Map<String, dynamic>> friendKeys = {};

  /// Every device of each friend that can read our messages: a message is encrypted once for each of them.
  final Map<String, List<DeviceKey>> friendDevices = {};

  /// This install's device id (random, kept in the secure vault next to the private key); null until [prepareDevice] ran.
  String? myDeviceId;
  final Map<String, int> unread = {};

  /// Group chats this device knows (the server stores none): group id -> group.
  final Map<String, ChatGroup> groups = {};

  /// Group message id -> recipients that may still receive it (decreased by each `e2ee-undelivered`; 0 and no ack = failed).
  final Map<String, int> _fanOut = {};

  /// The friend whose conversation is on screen: its incoming messages are not counted as unread.
  String? openPeer;

  /// False while the app is in the background: then no conversation counts as "being read".
  bool foreground = true;

  E2eeIdentity? _identity;
  bool _disposed = false;
  final Map<String, ({Map<String, dynamic> jwk, Uint8List key})> _sessions = {}; // 'friend|device' -> session key
  final Map<String, Timer> _ackTimers = {};
  final PartAssembler _assembler = PartAssembler();
  final Map<String, DateTime> _lastShot = {};
  Future<void> _inbox = Future.value(); // incoming frames are handled one at a time, in order

  String get _vaultKey => 'mamba_e2ee_identity_$userId';
  String get _deviceVaultKey => 'mamba_e2ee_device_$userId';

  /// Reads (or creates) this install's device id. The socket needs it BEFORE it connects, so the relay knows which device a
  /// connection is; `init` calls it too. When the vault cannot be read (phone locked) the id stays null and `init` reports it.
  Future<void> prepareDevice() async {
    if (myDeviceId != null) return;
    try {
      var d = await vault.read(_deviceVaultKey);
      if (d == null || !RegExp(r'^[A-Za-z0-9_-]{8,64}$').hasMatch(d)) {
        d = newMessageId();
        await vault.write(_deviceVaultKey, d);
      }
      myDeviceId = d;
    } catch (_) {
      /* try again in init */
    }
  }

  void _bump() {
    tick++;
    if (!_disposed) notifyListeners();
  }

  /// Creates the key pair on first use, publishes the public key if the server has a different one, loads the
  /// friends' keys. Safe to call again.
  Future<void> init() async {
    try {
      // A key that cannot be READ (phone locked, secure storage busy) is not a missing key: making a new one then would
      // replace the real key, so every friend would see "key changed" and old sessions would stop working. Try again later.
      String? stored;
      try {
        stored = await vault.read(_vaultKey);
      } catch (_) {
        ready = false;
        error = 'Chưa đọc được khoá mã hoá trên máy (điện thoại đang khoá hoặc kho khoá bận). Mở khoá điện thoại rồi thử lại.';
        if (!_disposed) notifyListeners();
        return;
      }
      var id = E2eeIdentity.fromStorage(stored);
      if (id == null) {
        id = E2eeIdentity.generate();
        await vault.write(_vaultKey, id.toStorage());
      }
      _identity = id;
      myFingerprint = await fingerprint(id.publicJwk);
      // One key per DEVICE: this install registers its own, so another device of the same account never replaces it.
      await prepareDevice();
      var registered = false;
      final dev = myDeviceId;
      if (dev != null) {
        try {
          await api.put('/me/e2ee-devices/$dev', {'publicKey': id.publicJwk});
          registered = true;
        } on ApiError catch (e) {
          if (e.status != 404 && e.status != 405) rethrow; // an older server only knows one key per account
        }
      }
      if (!registered) {
        final remote = (await api.get('/me/e2ee-key') as Map)['publicKey'];
        if (!samePublicKey(id.publicJwk, remote is Map<String, dynamic> ? remote : null)) {
          await api.put('/me/e2ee-key', {'publicKey': id.publicJwk});
        }
      }
      await _restoreUnread();
      await restorePrefs();
      await restoreGroups();
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

  Future<List<Map<String, dynamic>>> loadFriendKeys() async {
    final res = await api.get('/me/friends') as Map;
    final friends = [for (final f in (res['friends'] as List)) Map<String, dynamic>.from(f as Map)];
    await rememberFriends(friends);
    return friends;
  }

  /// Remembers each friend's public key and flags one that changed since we last saw it.
  Future<void> rememberFriends(List<Map<String, dynamic>> friends) => _keyStep(() => _rememberFriends(friends));

  // Remembering keys and accepting a changed key run one at a time: a refresh of the friend list that started before "Đã hiểu"
  // must not finish after it and flag the key again from what it read earlier.
  Future<void> _keyLock = Future.value();
  Future<void> _keyStep(Future<void> Function() fn) {
    final next = _keyLock.then((_) => fn());
    _keyLock = next.catchError((_) {});
    return next;
  }

  /// The devices a friend row lists; an older server (or one without devices yet) only has the single `publicKey`.
  List<DeviceKey> _devicesOfRow(Map<String, dynamic> f) {
    final out = <DeviceKey>[];
    final list = f['devices'];
    if (list is List) {
      for (final d in list) {
        if (d is! Map) continue;
        final id = d['id'];
        final raw = d['publicKey'];
        if (id is! String || raw is! Map || !isValidPublicJwk(raw)) continue;
        out.add(DeviceKey(id, pickPublic(Map<String, dynamic>.from(raw))));
      }
    }
    if (out.isEmpty) {
      final raw = f['publicKey'];
      if (raw is Map && isValidPublicJwk(raw)) out.add(DeviceKey(legacyDeviceId, pickPublic(Map<String, dynamic>.from(raw))));
    }
    return out;
  }

  Future<void> _rememberFriends(List<Map<String, dynamic>> friends) async {
    for (final f in friends) {
      final id = f['id'] as String;
      final devices = _devicesOfRow(f);
      if (devices.isEmpty) {
        friendKeys.remove(id);
        friendDevices.remove(id);
        continue;
      }
      friendDevices[id] = devices;
      friendKeys[id] = devices.first.jwk;
      // The warning is about a key that CHANGED for a device we already knew; a friend adding another device is not a change.
      var changed = false;
      var firstFp = '';
      for (final (i, d) in devices.indexed) {
        final fp = await fingerprint(d.jwk);
        if (i == 0) firstFp = fp;
        final pk = peerKeyOf(id, d.id);
        final known = await store.peer(pk);
        if (known == null) {
          await store.putPeer(PeerRecord(id: pk, jwk: d.jwk, fingerprint: fp, changed: false));
        } else if (!samePublicKey(known.jwk, d.jwk)) {
          await store.putPeer(PeerRecord(id: pk, jwk: d.jwk, fingerprint: fp, changed: true));
          _sessions.remove('$id|${d.id}');
          changed = true;
        } else if (known.changed) {
          changed = true;
        }
      }
      peerInfo[id] = PeerInfo(fingerprint: firstFp, changed: changed, devices: devices.length);
    }
    if (!_disposed) notifyListeners();
  }

  /// The user saw the "key changed" warning for this friend: trust the key the server shows NOW. The stored key is replaced too,
  /// otherwise the next refresh of the friend list still sees "different from the stored one" and shows the warning again.
  Future<void> acceptKeyChange(String friendId) => _keyStep(() => _acceptKeyChange(friendId));

  Future<void> _acceptKeyChange(String friendId) async {
    final devices = friendDevices[friendId];
    if (devices != null && devices.isNotEmpty) {
      for (final d in devices) {
        await store.putPeer(PeerRecord(id: peerKeyOf(friendId, d.id), jwk: d.jwk, fingerprint: await fingerprint(d.jwk), changed: false));
        _sessions.remove('$friendId|${d.id}');
      }
      peerInfo[friendId] = PeerInfo(fingerprint: await fingerprint(devices.first.jwk), changed: false, devices: devices.length);
    } else {
      final known = await store.peer(friendId);
      if (known != null) await store.putPeer(PeerRecord(id: known.id, jwk: known.jwk, fingerprint: known.fingerprint, changed: false));
      final info = peerInfo[friendId];
      if (info != null) peerInfo[friendId] = PeerInfo(fingerprint: info.fingerprint, changed: false, devices: info.devices);
    }
    if (!_disposed) notifyListeners();
  }

  Future<Uint8List?> _sessionFor(String friendId, DeviceKey device) async {
    final id = _identity;
    if (id == null) return null;
    final slot = '$friendId|${device.id}';
    final cached = _sessions[slot];
    if (cached != null && samePublicKey(cached.jwk, device.jwk)) return cached.key;
    final key = await deriveSessionKey(id, device.jwk, userId, friendId);
    _sessions[slot] = (jwk: device.jwk, key: key);
    return key;
  }

  /// The session key with the friend's newest device (null = no key at all: not a friend, or no 2-end encryption yet).
  Future<Uint8List?> _session(String friendId) async {
    final d = friendDevices[friendId]?.firstOrNull;
    return d == null ? null : _sessionFor(friendId, d);
  }

  /// Encrypts [plain] once for EVERY device of [to] and relays each copy to that device only. Returns for how many devices a copy
  /// was handed to the socket. [strict]: a message too big for the relay throws instead of skipping that device.
  Future<int> _relayTo(String to, String id, Uint8List plain, int ts, {bool strict = false}) async {
    var n = 0;
    for (final d in friendDevices[to] ?? const <DeviceKey>[]) {
      final key = await _sessionFor(to, d);
      if (key == null) continue;
      final env = await encryptBytes(key, plain, from: userId, to: to, id: id);
      final slices = splitCiphertext(env.ct);
      if (slices.length > maxParts) {
        if (strict) throw StateError('too big');
        continue;
      }
      for (var i = 0; i < slices.length; i++) {
        socket.send({'type': 'e2ee-msg', 'to': to, 'toDevice': d.id, 'id': id, 'iv': env.iv, 'ct': slices[i], 'part': i, 'parts': slices.length, 'ts': ts});
      }
      n++;
    }
    return n;
  }

  /// Devices that were counted for message [id] but never got a copy (no key, too big) will not answer: stop waiting for them.
  void _settleFanOut(String id, int skipped) {
    final left = _fanOut[id];
    if (left == null || skipped <= 0) return;
    if (left - skipped <= 0) {
      _fanOut.remove(id);
    } else {
      _fanOut[id] = left - skipped;
    }
  }

  /// Confirms receipt to the sender's device that sent [frame].
  void _ack(E2eeFrame frame) => socket.send({'type': 'e2ee-ack', 'to': frame.from, 'toDevice': ?frame.fromDevice, 'id': frame.id});

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
    final msg = ChatMessage(id: id, peerId: friendId, mine: true, text: text, att: att, createdAt: DateTime.now().millisecondsSinceEpoch, status: MsgStatus.sending, fromId: isGroupId(friendId) ? userId : null);
    await store.putMessage(msg);
    _bump();
    await _transmit(msg, image?.bytes, att);
    return msg;
  }

  Future<void> _transmit(ChatMessage msg, Uint8List? fileBytes, ChatAttachment? att) async {
    Future<void> fail(String reason) => _setStatus(msg.id, MsgStatus.failed, reason);
    if (isGroupId(msg.peerId)) return _transmitGroup(msg, fileBytes, att);
    try {
      final key = await _session(msg.peerId);
      if (key == null) return await fail('no-key');
      if (!socket.ready) return await fail('no-socket');
      var bytes = fileBytes;
      final a = att ?? msg.att;
      if (a != null && bytes == null && a.path != null) bytes = await store.readFile(a.path!);
      final plain = packMessage(text: msg.text, ts: msg.createdAt, att: a == null ? null : {'name': a.name, 'type': a.type, 'size': a.size}, kind: msg.sys == SysKind.screenshotSent ? 'screenshot' : null, file: bytes);
      // Several devices: it only failed when NONE of them can get it (see the `e2ee-undelivered` handling). The count is set BEFORE
      // the frames go out, so an early answer is never taken for the last one.
      final total = friendDevices[msg.peerId]?.length ?? 0;
      if (total > 1) _fanOut[msg.id] = total;
      final devices = await _relayTo(msg.peerId, msg.id, plain, msg.createdAt, strict: true);
      if (devices == 0) {
        _fanOut.remove(msg.id);
        return await fail('no-key');
      }
      if (total > 1) _settleFanOut(msg.id, total - devices);
      await _setStatus(msg.id, MsgStatus.sent);
      _ackTimers[msg.id]?.cancel();
      _ackTimers[msg.id] = Timer(ackWait, () {
        _fanOut.remove(msg.id);
        _setStatus(msg.id, MsgStatus.failed, 'timeout');
      });
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
    if (_disposed) return; // a send that fails after dispose (closed store) must not write
    final m = await store.message(id);
    if (m == null || _disposed) return;
    if (status != MsgStatus.sent) {
      _ackTimers.remove(id)?.cancel();
    }
    // A late timeout must not overwrite a delivery that already happened.
    if (m.status == MsgStatus.delivered && status == MsgStatus.failed) return;
    await store.putMessage(ChatMessage(id: m.id, peerId: m.peerId, mine: m.mine, text: m.text, createdAt: m.createdAt, status: status, att: m.att, sys: m.sys, reason: status == MsgStatus.failed ? reason : null, fromId: m.fromId));
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
      if (id is String) {
        _fanOut.remove(id);
        await _setStatus(id, MsgStatus.delivered);
      }
      return;
    }
    if (type == 'e2ee-undelivered') {
      if (id is String) {
        // A group message goes to several members: it only failed when NONE of them can get it.
        final left = _fanOut[id];
        if (left != null && left > 1) {
          _fanOut[id] = left - 1;
          return;
        }
        _fanOut.remove(id);
        await _setStatus(id, MsgStatus.failed, msg['reason'] as String?);
      }
      return;
    }
    final parsed = E2eeFrame.tryParse(msg);
    if (parsed == null) return;
    final frame = _assembler.add(parsed);
    if (frame == null) return;
    try {
      final seen = await store.message(frame.id);
      if (seen != null) {
        // duplicate: shown once, but the sender may have missed our ack (lost on the way), so confirm again
        if (!seen.mine) _ack(frame);
        return;
      }
      if (!friendKeys.containsKey(frame.from)) await loadFriendKeys(); // new friend
      // The key of the device that sent it (the relay names it); a sender on an older app has only the single `legacy` key.
      Future<Uint8List?> keyOfSender() async {
        final list = friendDevices[frame.from];
        if (list == null || list.isEmpty) return null;
        final want = frame.fromDevice ?? legacyDeviceId;
        final d = list.where((x) => x.id == want).firstOrNull ?? (frame.fromDevice == null ? list.first : null);
        return d == null ? null : _sessionFor(frame.from, d);
      }

      var key = await keyOfSender();
      if (key == null && frame.fromDevice != null) {
        await loadFriendKeys(); // a device that registered a moment ago
        key = await keyOfSender();
      }
      if (key == null) return;
      final env = Envelope(frame.iv, frame.ct);
      Uint8List plain;
      try {
        plain = await decryptBytes(key, env, from: frame.from, to: userId, id: frame.id);
      } catch (_) {
        await loadFriendKeys(); // their key may have changed; retry once with a fresh one
        key = await keyOfSender();
        if (key == null) return;
        plain = await decryptBytes(key, env, from: frame.from, to: userId, id: frame.id);
      }
      final m = unpackMessage(plain);
      // The sender's clock is not trusted: never in the future, never older than 5 minutes before it was received.
      final now = DateTime.now().millisecondsSinceEpoch;
      final createdAt = m.ts > now ? now : (m.ts < now - 300000 ? now - 300000 : m.ts);
      if (m.group != null) {
        await _handleGroupMessage(frame, m, createdAt);
        return;
      }
      if (m.kind == 'screenshot') {
        await store.putMessage(ChatMessage(id: frame.id, peerId: frame.from, mine: false, text: '', createdAt: createdAt, status: MsgStatus.delivered, sys: SysKind.screenshot));
        _ack(frame);
        _bump();
        await _bumpUnread(frame.from);
        onIncoming?.call(frame.from, frame.fromName, 'đã chụp màn hình cuộc trò chuyện với bạn');
        return;
      }
      final att = await _incomingAttachment(m, frame.id);
      await store.putMessage(ChatMessage(id: frame.id, peerId: frame.from, mine: false, text: m.text, att: att, createdAt: createdAt, status: MsgStatus.delivered));
      _ack(frame);
      _bump();
      await _bumpUnread(frame.from);
      onIncoming?.call(frame.from, frame.fromName, m.text.isNotEmpty ? m.text : 'Đã gửi một tệp đính kèm');
    } catch (_) {
      // Could not read an incoming message (wrong key, tampered, malformed): drop it silently like the web.
    }
  }

  /// Only pictures are accepted from a friend (a modified client could send anything).
  Future<ChatAttachment?> _incomingAttachment(PackedMessage m, String messageId) async {
    final a = m.att;
    final aType = a?['type'];
    if (a != null && m.file.isNotEmpty && aType is String && allowedImageTypes.contains(aType) && sniffImageType(m.file) != null) {
      final name = (a['name'] ?? 'tep-dinh-kem').toString();
      return ChatAttachment(name: name.length > 200 ? name.substring(0, 200) : name, type: aType, size: m.file.length, path: await store.writeFile(messageId, Uint8List.fromList(m.file), imageExt(aType)));
    }
    return null;
  }

  // ---- group chats (no server involved: every message is encrypted once per member and relayed like a 1:1 message) ----------

  Future<void> restoreGroups() async {
    groups.clear();
    for (final e in (await store.metaWithPrefix('group:')).entries) {
      final g = ChatGroup.tryParse(e.value);
      if (g != null) groups[g.id] = g;
    }
  }

  Future<void> _saveGroup(ChatGroup g) async {
    groups[g.id] = g;
    await store.setMeta('group:${g.id}', g.toJson());
  }

  /// Creates the group on this device and tells every member (an empty, end-to-end encrypted "new group" message that carries the
  /// name and the member list). Members must be friends of the creator, since the relay only carries messages between friends.
  Future<ChatGroup> createGroup(String name, String myName, List<GroupMember> others) async {
    if (!ready) throw Exception('Mã hoá 2 đầu chưa sẵn sàng trên thiết bị này.');
    final n = name.trim();
    if (n.isEmpty) throw Exception('Nhập tên nhóm.');
    final ids = {for (final o in others) o.id}..remove(userId);
    if (ids.length < 2) throw Exception('Chọn ít nhất 2 bạn bè để tạo nhóm.');
    if (ids.length > 49) throw Exception('Nhóm tối đa 50 người.');
    final members = [
      GroupMember(userId, myName.isEmpty ? 'Thành viên' : myName),
      for (final o in others)
        if (ids.remove(o.id)) o,
    ];
    final g = ChatGroup(id: '$groupIdPrefix${newMessageId()}', name: n.length > 60 ? n.substring(0, 60) : n, members: members, creatorId: userId, updatedAt: DateTime.now().millisecondsSinceEpoch);
    await _saveGroup(g);
    _bump();
    await _fanOutKind(g, 'group-new');
    return g;
  }

  /// Renames the group for everybody (the new name travels with the next messages too).
  Future<void> renameGroup(String groupId, String name) async {
    final g = groups[groupId];
    final n = name.trim();
    if (g == null || n.isEmpty || g.creatorId != userId) return; // only the creator renames
    final next = g.copyWith(name: n.length > 60 ? n.substring(0, 60) : n, updatedAt: DateTime.now().millisecondsSinceEpoch);
    await _saveGroup(next);
    _bump();
    await _fanOutKind(next, 'group-new');
  }

  /// Creator only: adds friends to the group. Everybody (the new members included) gets the updated group; the new members see
  /// the messages sent from now on, not the earlier ones.
  Future<void> addGroupMembers(String groupId, List<GroupMember> added) async {
    final g = groups[groupId];
    if (g == null || g.creatorId != userId) return;
    final have = {for (final m in g.members) m.id};
    final fresh = [
      for (final a in added)
        if (have.add(a.id)) a,
    ];
    if (fresh.isEmpty) return;
    if (g.members.length + fresh.length > 50) throw Exception('Nhóm tối đa 50 người.');
    final next = g.copyWith(members: [...g.members, ...fresh], updatedAt: DateTime.now().millisecondsSinceEpoch);
    await _saveGroup(next);
    _bump();
    await _fanOutKind(next, 'group-new');
  }

  /// Creator only: removes a member. The others get the updated group; the removed person is told, and drops the group.
  Future<void> removeGroupMember(String groupId, String memberId) async {
    final g = groups[groupId];
    if (g == null || g.creatorId != userId || memberId == userId) return;
    final gone = g.members.where((m) => m.id == memberId).firstOrNull;
    if (gone == null) return;
    final next = g.copyWith(
      members: [
        for (final m in g.members)
          if (m.id != memberId) m,
      ],
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (next.members.length < 2) throw Exception('Nhóm cần ít nhất 2 người.');
    await _saveGroup(next);
    _bump();
    // the removed member is told with the group as it was (so it still lists them) and kind "group-removed"
    final id = newMessageId();
    final ts = DateTime.now().millisecondsSinceEpoch;
    if (socket.ready) await _relayTo(memberId, id, packMessage(text: '', ts: ts, kind: 'group-removed', group: next.toHeader()), ts);
    await _fanOutKind(next, 'group-new');
  }

  /// Leaves the group: the others are told, then it is removed from this device together with its messages.
  Future<void> leaveGroup(String groupId, {bool notify = true}) async {
    final g = groups[groupId];
    if (g != null && notify) {
      final rest = g.copyWith(
        members: [
          for (final m in g.members)
            if (m.id != userId) m,
        ],
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (rest.members.length >= 2) await _fanOutKind(rest, 'group-left');
    }
    await deleteConversation(groupId);
    groups.remove(groupId);
    await store.setMeta('group:$groupId', null);
    if (archived.contains(groupId)) await setArchived([groupId], false);
    unread.remove(groupId);
    await store.setMeta('unread:$groupId', null);
    _bump();
  }

  /// A message without text for the members, only carrying the group (creation, rename, somebody left). Returns how many members
  /// it was sent to.
  Future<int> _fanOutKind(ChatGroup g, String kind) async {
    final id = newMessageId();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return _fanOutFrames(g, id, packMessage(text: '', ts: ts, kind: kind, group: g.toHeader()), ts, ack: false);
  }

  /// Encrypts [plain] for every device of every member except me and relays it. Returns the number of devices it was handed to the socket for.
  Future<int> _fanOutFrames(ChatGroup g, String id, Uint8List plain, int ts, {bool ack = true}) async {
    if (!socket.ready) return 0;
    var sent = 0;
    var total = 0;
    for (final member in g.members) {
      if (member.id != userId) total += friendDevices[member.id]?.length ?? 0;
    }
    if (ack && total > 0) _fanOut[id] = total; // set before anything is sent: an early answer is not the last one
    for (final member in g.members) {
      if (member.id == userId) continue;
      // not my friend (no key): nothing is sent, the relay would refuse it anyway; else one copy per device of the member
      sent += await _relayTo(member.id, id, plain, ts);
    }
    if (ack) {
      if (sent == 0) {
        _fanOut.remove(id);
      } else {
        _settleFanOut(id, total - sent);
      }
    }
    return sent;
  }

  Future<void> _transmitGroup(ChatMessage msg, Uint8List? fileBytes, ChatAttachment? att) async {
    Future<void> fail(String reason) => _setStatus(msg.id, MsgStatus.failed, reason);
    try {
      final g = groups[msg.peerId];
      if (g == null) return await fail('invalid');
      if (!socket.ready) return await fail('no-socket');
      var bytes = fileBytes;
      final a = att ?? msg.att;
      if (a != null && bytes == null && a.path != null) bytes = await store.readFile(a.path!);
      final plain = packMessage(text: msg.text, ts: msg.createdAt, att: a == null ? null : {'name': a.name, 'type': a.type, 'size': a.size}, group: g.toHeader(), file: bytes);
      final sent = await _fanOutFrames(g, msg.id, plain, msg.createdAt);
      if (sent == 0) return await fail('no-key');
      await _setStatus(msg.id, MsgStatus.sent);
      _ackTimers[msg.id]?.cancel();
      _ackTimers[msg.id] = Timer(ackWait, () {
        _fanOut.remove(msg.id);
        _setStatus(msg.id, MsgStatus.failed, 'timeout');
      });
    } catch (_) {
      await fail('invalid');
    }
  }

  /// A message (or creation / rename / "left" notice) of a group chat from [frame].from.
  Future<void> _handleGroupMessage(E2eeFrame frame, PackedMessage m, int createdAt) async {
    final parsedHeader = ChatGroup.fromHeader(m.group);
    if (parsedHeader == null) return;
    // The sender-supplied clock must not freeze later legitimate updates: never more than a little in the future.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final incoming = parsedHeader.updatedAt > nowMs + 60000 ? parsedHeader.copyWith(updatedAt: nowMs + 60000) : parsedHeader;
    final known = groups[incoming.id];
    // A group we already know: only OUR list of members decides who may speak (a removed member, or a friend who merely
    // knows the group id, cannot inject messages by declaring themselves in the header).
    if (known != null && m.kind != 'group-removed' && !known.members.any((x) => x.id == frame.from)) return;
    if (m.kind == 'group-removed') {
      // The creator removed me: forget the group (its messages go with it).
      if (known == null || known.creatorId != frame.from || incoming.members.any((x) => x.id == userId)) return;
      _ack(frame);
      final name = known.name;
      await leaveGroup(known.id, notify: false);
      onIncoming?.call(known.id, name, 'Bạn đã bị xoá khỏi nhóm');
      return;
    }
    if (m.kind == 'group-left') {
      // The sender is leaving: it is no longer in the list the message carries, so it must have been a member before.
      if (known == null || !known.members.any((x) => x.id == frame.from) || incoming.members.any((x) => x.id == frame.from)) return;
    } else if (!incoming.members.any((x) => x.id == frame.from) || !incoming.members.any((x) => x.id == userId)) {
      // Only a member may speak in the group, and the group must include me.
      return;
    }
    if (known != null && known.creatorId != incoming.creatorId) return; // the creator of an existing group cannot be changed
    // Who may change the group (name, members): the creator; a member leaving removes only themselves. A newer header carried by an
    // ordinary message of another member is not trusted.
    final fromCreator = frame.from == incoming.creatorId;
    if (known == null) {
      await _saveGroup(incoming);
    } else if (incoming.updatedAt > known.updatedAt) {
      final expected = {
        for (final x in known.members)
          if (x.id != frame.from) x.id,
      };
      final got = incoming.members.map((x) => x.id).toList();
      final leftOk = m.kind == 'group-left' && got.length == expected.length && got.toSet().length == got.length && got.toSet().containsAll(expected);
      if (fromCreator || leftOk) await _saveGroup(incoming);
    }
    final g = groups[incoming.id]!;
    _ack(frame);
    final who = _nameInGroup(g, frame.from, frame.fromName);
    if (m.kind == 'group-new' || m.kind == 'group-left') {
      _bump();
      if (m.kind == 'group-new' && known == null) onIncoming?.call(g.id, g.name, '$who đã thêm bạn vào nhóm');
      return;
    }
    final att = await _incomingAttachment(m, frame.id);
    await store.putMessage(ChatMessage(id: frame.id, peerId: g.id, mine: false, text: m.text, att: att, createdAt: createdAt, status: MsgStatus.delivered, fromId: frame.from));
    _bump();
    await _bumpUnread(g.id);
    onIncoming?.call(g.id, g.name, '$who: ${m.text.isNotEmpty ? m.text : 'Đã gửi một tệp đính kèm'}');
  }

  /// Test hook: sends a group message of [g] to [to] as this device, without checking that it belongs to the group.
  @visibleForTesting
  Future<void> debugSendGroupFrame(ChatGroup g, String to, String text, {String? kind, String? id, int? ts}) async {
    id ??= newMessageId();
    ts ??= DateTime.now().millisecondsSinceEpoch;
    await _relayTo(to, id, packMessage(text: text, ts: ts, kind: kind, group: g.toHeader()), ts);
  }

  String _nameInGroup(ChatGroup g, String id, [String? fallback]) {
    final alias = aliases[id];
    if (alias != null) return alias;
    for (final x in g.members) {
      if (x.id == id) return x.name;
    }
    return fallback ?? 'Thành viên';
  }

  /// The name to show for member [id] of [g] on this device.
  String memberName(ChatGroup g, String id) => id == userId ? 'Bạn' : _nameInGroup(g, id);

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
      ..addEntries([
        for (final e in (await store.metaWithPrefix('alias:')).entries)
          if (e.value.isNotEmpty) MapEntry(e.key.substring(6), e.value),
      ]);
    archived
      ..clear()
      ..addAll(_decodeList(await store.meta('archive')));
  }

  static List<String> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return [
        for (final x in (jsonDecode(raw) as List))
          if (x is String) x,
      ];
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
    friendDevices.clear();
    peerInfo.clear();
    unread.clear();
    ready = false;
    store.close();
    super.dispose();
  }
}
