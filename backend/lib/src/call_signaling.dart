import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// In-memory registry of currently-connected call sockets, keyed by user
/// id. Lets `routes/ws/calls.dart` relay WebRTC signaling (offer/answer/ICE
/// candidates) and call-invite/reject/end messages directly between two
/// specific users without persisting any of it - calls aren't stored data,
/// just a live relay. A user can only have one call socket open at a time;
/// a second connection replaces the first (e.g. a page reload).
class CallSignalingRegistry {
  CallSignalingRegistry._();
  static final CallSignalingRegistry instance = CallSignalingRegistry._();

  final Map<String, WebSocketChannel> _sockets = {};

  // Who each user is currently ringing/talking to, tracked purely so a
  // disconnect (closed tab, crashed app, dropped network - anything that
  // isn't the user cleanly pressing "end call") can still tell the other
  // side the call is over. Without this, a client that vanishes mid-call
  // leaves its peer stuck on "ringing"/"connecting" forever, since the
  // relay never stores or inspects call content and has nothing else that
  // would make it notice. Set symmetrically when a call-invite is
  // delivered, cleared symmetrically on call-end/call-reject/disconnect.
  final Map<String, String> _activePeer = {};

  void register(String userId, WebSocketChannel channel) {
    _sockets[userId] = channel;
  }

  /// Only removes the mapping if it still points at [channel] - guards
  /// against a stale disconnect handler clearing a newer connection that
  /// already replaced it for the same user.
  void unregister(String userId, WebSocketChannel channel) {
    if (_sockets[userId] == channel) _sockets.remove(userId);
  }

  void setActivePeer(String a, String b) {
    _activePeer[a] = b;
    _activePeer[b] = a;
  }

  String? activePeerOf(String userId) => _activePeer[userId];

  /// Clears the pairing for [userId] and whoever they were paired with
  /// (symmetric - a single id is enough to find and remove both sides).
  void clearActivePeer(String userId) {
    final peer = _activePeer.remove(userId);
    if (peer != null) _activePeer.remove(peer);
  }

  bool isOnline(String userId) => _sockets.containsKey(userId);

  /// Sends a JSON message to [userId]'s socket if connected. Returns false
  /// (caller should tell the sender the other side is offline) if not.
  bool sendTo(String userId, Map<String, dynamic> message) {
    final channel = _sockets[userId];
    if (channel == null) return false;
    channel.sink.add(jsonEncode(message));
    return true;
  }
}
