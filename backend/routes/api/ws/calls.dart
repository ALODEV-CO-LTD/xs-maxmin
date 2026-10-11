import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';
import 'package:server/src/call_log.dart';
import 'package:server/src/apns.dart';
import 'package:server/src/call_signaling.dart';
import 'package:server/src/database.dart';
import 'package:server/src/push_notify.dart';
import 'package:server/src/security.dart';
import 'package:server/src/sessions.dart';
import 'package:sqlite3/sqlite3.dart';

/// `GET /api/ws/calls?token=<jwt>` - signaling relay for WebRTC voice
/// calls between friends, used by FriendsView's call button. A browser's
/// WebSocket handshake can't carry a custom `Authorization` header, so
/// unlike every other route the JWT travels as a query param here and is
/// verified directly with [verifyToken] instead of going through
/// `auth_middleware.dart`'s header-based provider.
///
/// This relay never stores or looks at call content (audio/video is pure
/// peer-to-peer WebRTC once connected) - it only passes along small JSON
/// control messages, each addressed with a `to` user id:
///   - `call-invite` - "ring" the other side; sent back as `call-unavailable`
///     if they're not connected right now.
///   - `offer` / `answer` / `ice` - standard WebRTC SDP/ICE exchange.
///   - `call-reject` / `call-end` - hang up before or during a call.
/// Voice only: the product has no video calling, so any message flagged
/// `video: true` (or an offer/answer SDP that carries a video m-line) is
/// refused with a `call-error` instead of being relayed.
/// Every inbound message is re-broadcast to `to` unchanged except `to` is
/// replaced with `from: <sender's own id>` so the receiver knows who it's
/// from without being able to spoof it.
///
/// Also synthesizes a `call-end` (with `reason: 'disconnected'`) to whoever
/// a user was ringing/talking to if their socket drops without them
/// sending one themselves - see [CallSignalingRegistry]'s active-peer
/// tracking - so a closed tab or lost connection doesn't leave the other
/// side stuck on "ringing"/"connecting" indefinitely.
/// The only message types the relay forwards. Anything else is ignored.
const _relayedTypes = {'call-invite', 'call-accept', 'call-reject', 'call-end', 'offer', 'answer', 'ice'};
const _maxMessageChars = 64 * 1024;

/// End-to-end encrypted chat (docs/MA_HOA_2_DAU.md). The relay forwards the
/// ciphertext envelope `{id, iv, ct}` to a friend who is online right now and
/// stores NOTHING: if they are offline the sender is told (`e2ee-undelivered`)
/// and nothing is kept. The recipient confirms with `e2ee-ack`, which is relayed
/// back. The plaintext (text and any attachment) is inside `ct`; the server
/// never sees it. A 5 MB file does not fit one WebSocket frame, so the
/// ciphertext is split into parts (`part`/`parts`, at most 8) that are relayed
/// one by one and put back together by the receiver; the relay keeps no state.
const _e2eeTypes = {'e2ee-msg', 'e2ee-ack'};
const _maxE2eeChars = 2 * 1024 * 1024; // one frame (part) of ciphertext
const _maxE2eeParts = 8;

Future<Response> onRequest(RequestContext context) async {
  final token = context.request.uri.queryParameters['token'];
  var auth = token == null ? null : verifyToken(token);
  if (auth != null && !sessionIsActive(appDatabase, auth.userId, auth.sessionId, issuedAtSeconds: auth.issuedAt)) auth = null;
  if (auth == null) {
    return Response.json(statusCode: 401, body: {'error': 'Chưa đăng nhập'});
  }
  final userId = auth.userId;
  final db = context.read<Database>();
  final registry = CallSignalingRegistry.instance;

  final handler = webSocketHandler(
    (channel, protocol) {
      registry.register(userId, channel);

      channel.stream.listen(
        (raw) {
          // Signaling messages are tiny (an SDP is a few KB); anything big is
          // abuse, not a call.
          if (raw is! String || raw.length > _maxE2eeChars) return;
          final Map<String, dynamic> msg;
          try {
            msg = jsonDecode(raw) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          final to = msg['to'] as String?;
          final type = msg['type'] as String?;
          if (type != null && _e2eeTypes.contains(type)) {
            _relayE2ee(db, registry, channel, userId, to, type, msg);
            return;
          }
          if (raw.length > _maxMessageChars) return;
          if (to == null || type == null || !_relayedTypes.contains(type)) return;

          // Same trust boundary as text messages: only confirmed friends
          // can signal each other (see /me/friends/:friendId/messages.dart).
          final isFriend = db.select(
            'SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?',
            [userId, to],
          ).isNotEmpty;
          if (!isFriend) {
            channel.sink.add(jsonEncode({'type': 'call-error', 'error': 'Không phải bạn bè'}));
            return;
          }

          // Business rule: calls exist only between customers. Admin can
          // chat with everyone but neither places nor receives calls, so a
          // customer can never ring Admin. Enforced here - not just by
          // hiding the buttons - because the client is untrusted; every
          // signaling type is blocked (not only call-invite) so offer/ice
          // can't be pushed at an admin either.
          final involvesAdmin = db.select(
            "SELECT 1 FROM users WHERE id IN (?, ?) AND role = 'admin'",
            [userId, to],
          ).isNotEmpty;
          if (involvesAdmin) {
            channel.sink.add(jsonEncode({
              'type': 'call-error',
              'error': 'Chỉ khách hàng gọi được cho nhau, không gọi cho Admin. Hãy nhắn tin để được hỗ trợ.',
            }));
            return;
          }

          // Voice-only rule (K31): enforced here because the client is
          // untrusted - hiding the video button is not enough.
          if (_wantsVideo(msg)) {
            channel.sink.add(jsonEncode({'type': 'call-error', 'error': 'Chỉ hỗ trợ gọi thoại, không hỗ trợ gọi video.'}));
            return;
          }

          final payload = Map<String, dynamic>.from(msg)
            ..remove('to')
            ..['from'] = userId;

          if (type == 'call-invite') {
            // The caller's display name is read from the account, never
            // taken from the client - otherwise anyone could ring a friend
            // while showing up under someone else's name.
            final nameRow = db.select('SELECT name FROM users WHERE id = ?', [userId]);
            payload['fromName'] = nameRow.isEmpty ? 'Người dùng' : nameRow.first['name'];

            if (!registry.allowInvite(userId)) {
              channel.sink.add(jsonEncode({
                'type': 'call-error',
                'error': 'Bạn gọi quá nhiều lần liên tiếp, vui lòng thử lại sau ít phút.',
              }));
              return;
            }
            // Busy line: either side already ringing/talking. Answered here
            // (not by the callee's client) so a callee in a call is never
            // disturbed, and the missed call is still recorded for them.
            if (registry.activePeerOf(to) != null || registry.activePeerOf(userId) != null) {
              startCallLog(db, userId, to, status: 'busy');
              channel.sink.add(jsonEncode({'type': 'call-reject', 'from': to, 'reason': 'busy'}));
              return;
            }
            final delivered = registry.sendTo(to, payload);
            if (!delivered) {
              // Offline callee: no ring, but they will see a missed call.
              startCallLog(db, userId, to, status: 'missed');
              notifyOfflineRecipient(kind: PushKind.call, fromUserId: userId, fromName: payload['fromName'] as String, toUserId: to);
              channel.sink.add(jsonEncode({'type': 'call-unavailable', 'from': to}));
              return;
            }
            // A delivered invite already makes both sides part of the same
            // call attempt, so pair them from that point - not just once they
            // reach `connected` - otherwise a caller who vanishes while the
            // other side is still ringing would leave them hanging until the
            // client's own ring timeout, instead of right away.
            registry.setActivePeer(userId, to, logId: startCallLog(db, userId, to));
            // Tells the caller the other phone is ringing (UI: "Đang đổ chuông").
            channel.sink.add(jsonEncode({'type': 'call-ringing', 'from': to}));
            return;
          }

          // Everything else only means something inside a call between these
          // two people; a stray accept/offer/ice from a stranger is dropped.
          final inCallWithTo = registry.activePeerOf(userId) == to;
          if (!inCallWithTo && type != 'call-end') return;

          final logId = registry.activeLogOf(userId);
          switch (type) {
            case 'call-accept':
              applyCallEvent(db, logId, 'accept');
            case 'call-reject':
              applyCallEvent(db, logId, 'reject', reason: msg['reason'] as String?);
            case 'call-end':
              if (inCallWithTo) applyCallEvent(db, logId, 'end', reason: msg['reason'] as String?);
          }

          registry.sendTo(to, payload);
          if (inCallWithTo && (type == 'call-end' || type == 'call-reject')) registry.clearActivePeer(userId);
        },
        onDone: () {
          // The client didn't get a chance to send call-end (closed tab,
          // crashed, lost network, dev server restart...) - if they were
          // mid-call with someone, that person would otherwise be stuck on
          // "Đang gọi…"/"Đang kết nối…" forever with no way to know.
          final peer = registry.activePeerOf(userId);
          if (peer != null) {
            applyCallEvent(db, registry.activeLogOf(userId), 'end', reason: 'disconnected');
            registry.sendTo(peer, {'type': 'call-end', 'from': userId, 'reason': 'disconnected'});
            registry.clearActivePeer(userId);
          }
          registry.unregister(userId, channel);
        },
      );
    },
    // Detects a connection that's gone dead without a clean close (e.g. the
    // dev server restarting, a network drop) within ~20s instead of leaving
    // both sides thinking they're still connected indefinitely - the
    // client's `onclose` then fires and its own reconnect logic kicks in.
    pingInterval: const Duration(seconds: 10),
  );

  return handler(context);
}

/// True when a signaling message asks for video: an explicit `video: true`
/// flag (call-invite) or an SDP offer/answer containing a video media line.
bool _wantsVideo(Map<String, dynamic> msg) {
  final video = msg['video'];
  if (video == true || video == 'true' || video == 1) return true;
  final sdp = msg['sdp'];
  if (sdp is Map && sdp['sdp'] is String && RegExp(r'^m=video ', multiLine: true).hasMatch(sdp['sdp'] as String)) {
    return true;
  }
  return false;
}

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
/// Base64 / base64url characters only. A loop, not a RegExp: a regex over a
/// megabyte of ciphertext overflows the Dart regex engine's stack.
bool _isBase64(String s) {
  for (final c in s.codeUnits) {
    final ok = (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == 0x2b || c == 0x2f || c == 0x2d || c == 0x5f || c == 0x3d;
    if (!ok) return false;
  }
  return true;
}

void _relayE2ee(
  Database db,
  CallSignalingRegistry registry,
  dynamic channel,
  String userId,
  String? to,
  String type,
  Map<String, dynamic> msg,
) {
  final id = msg['id'];
  if (to == null || id is! String || !_idPattern.hasMatch(id)) return;

  // Only confirmed friends, and never Admin (support has its own thread).
  final ok = db.select(
    '''
    SELECT 1 FROM friendships f JOIN users u ON u.id = f.friend_id
    WHERE f.user_id = ? AND f.friend_id = ? AND u.role != 'admin'
    ''',
    [userId, to],
  ).isNotEmpty;
  if (!ok) {
    channel.sink.add(jsonEncode({'type': 'e2ee-undelivered', 'id': id, 'to': to, 'reason': 'not-friend'}));
    return;
  }

  if (type == 'e2ee-ack') {
    registry.sendTo(to, {'type': 'e2ee-ack', 'id': id, 'from': userId});
    return;
  }

  final part = msg['part'] ?? 0;
  final parts = msg['parts'] ?? 1;
  if (part is! int || parts is! int || parts < 1 || parts > _maxE2eeParts || part < 0 || part >= parts) {
    channel.sink.add(jsonEncode({'type': 'e2ee-undelivered', 'id': id, 'to': to, 'reason': 'invalid'}));
    return;
  }
  final iv = msg['iv'];
  final ct = msg['ct'];
  if (iv is! String || ct is! String || iv.length > 64 || ct.isEmpty || !_isBase64(iv) || !_isBase64(ct)) {
    channel.sink.add(jsonEncode({'type': 'e2ee-undelivered', 'id': id, 'to': to, 'reason': 'invalid'}));
    return;
  }
  // `ts` is the sender's clock, shown by the receiver; `fromName` comes from the
  // account, never from the client.
  final nameRow = db.select('SELECT name FROM users WHERE id = ?', [userId]);
  final delivered = registry.sendTo(to, {
    'type': 'e2ee-msg',
    'id': id,
    'from': userId,
    'fromName': nameRow.isEmpty ? 'Người dùng' : nameRow.first['name'],
    'iv': iv,
    'ct': ct,
    'part': part,
    'parts': parts,
    if (msg['ts'] is int) 'ts': msg['ts'],
  });
  if (!delivered) {
    // Wake the recipient's iPhone (name + kind only, never content). Only for
    // the first part so a multi-part file sends one push.
    if (part == 0) {
      notifyOfflineRecipient(
        kind: PushKind.message,
        fromUserId: userId,
        fromName: nameRow.isEmpty ? 'Người dùng' : nameRow.first['name'] as String,
        toUserId: to,
      );
    }
    channel.sink.add(jsonEncode({'type': 'e2ee-undelivered', 'id': id, 'to': to, 'reason': 'offline'}));
  }
}
