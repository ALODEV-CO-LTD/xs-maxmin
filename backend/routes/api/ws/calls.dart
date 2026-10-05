import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:dart_frog_web_socket/dart_frog_web_socket.dart';
import 'package:server/src/call_signaling.dart';
import 'package:server/src/database.dart';
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
Future<Response> onRequest(RequestContext context) async {
  final token = context.request.uri.queryParameters['token'];
  var auth = token == null ? null : verifyToken(token);
  if (auth != null && !sessionIsActive(appDatabase, auth.userId, auth.sessionId)) auth = null;
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
          final Map<String, dynamic> msg;
          try {
            msg = jsonDecode(raw as String) as Map<String, dynamic>;
          } catch (_) {
            return;
          }
          final to = msg['to'] as String?;
          final type = msg['type'] as String?;
          if (to == null || type == null) return;

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
          final delivered = registry.sendTo(to, payload);
          if (!delivered && type == 'call-invite') {
            channel.sink.add(jsonEncode({'type': 'call-unavailable', 'from': to}));
          }

          // Track "who is userId currently ringing/talking to" purely so a
          // disconnect below can still tell that person the call is over
          // (see CallSignalingRegistry's doc comment). A delivered invite
          // already means both sides are now part of the same call
          // attempt, so pair them from that point - not just once they
          // reach `connected` - otherwise a caller who vanishes while the
          // other side is still ringing would leave them hanging until the
          // client's own 30s ring-timeout, instead of right away.
          if (delivered && type == 'call-invite') registry.setActivePeer(userId, to);
          if (type == 'call-end' || type == 'call-reject') registry.clearActivePeer(userId);
        },
        onDone: () {
          // The client didn't get a chance to send call-end (closed tab,
          // crashed, lost network, dev server restart...) - if they were
          // mid-call with someone, that person would otherwise be stuck on
          // "Đang gọi…"/"Đang kết nối…" forever with no way to know.
          final peer = registry.activePeerOf(userId);
          if (peer != null) {
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
