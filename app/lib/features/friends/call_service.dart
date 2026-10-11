import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../core/api_client.dart';
import 'call_state.dart';
import 'realtime_socket.dart';

export 'call_state.dart';

class CallPeer {
  const CallPeer(this.id, this.name);
  final String id;
  final String name;
}

const _ringTimeout = Duration(seconds: 30);
const _mediaPromptTimeout = Duration(seconds: 60);
const _mediaSetupTimeout = Duration(seconds: 25);
const _reconnectGrace = Duration(seconds: 20);
const _maxIceRestarts = 2;
const _iceCacheTtl = Duration(minutes: 10);

/// Plain-language text for a failed `getUserMedia`.
String micErrorMessage(Object err) {
  final t = err.toString().toLowerCase();
  if (t.contains('permission') || t.contains('notallowed') || t.contains('denied')) {
    return 'Chưa được cấp quyền dùng micro. Vào Cài đặt > Ứng dụng > MAMBA > Quyền, cho phép micro rồi gọi lại.';
  }
  if (t.contains('notfound') || t.contains('no audio')) return 'Không tìm thấy micro trên thiết bị này.';
  if (t.contains('notreadable') || t.contains('abort')) return 'Không mở được micro, có thể ứng dụng khác đang dùng.';
  return 'Không bật được micro.';
}

/// Voice-only WebRTC calls between friends. Same signalling as frontend/src/stores/call.js (messages travel over the
/// shared WebSocket, see backend/routes/api/ws/calls.dart): call-invite / call-ringing / call-accept / call-reject /
/// call-end / offer / answer / ice. One call at a time. The status changes follow [reduceCall]; the call UI is
/// `CallPanel`, ringing / vibration / notifications are driven by the app-level controller from [status].
class CallService extends ChangeNotifier {
  CallService({required this.api, required this.socket, required this.canCall});
  final ApiClient api;
  final FrameSink socket;

  /// Admin accounts neither place nor receive calls (the server enforces this too).
  final bool canCall;

  /// An invitation arrived while this device was already busy (it was rejected with `busy`): (friendId, name).
  void Function(String friendId, String name)? onBusyMissed;

  CallStatus status = CallStatus.idle;
  CallPeer? peer;
  bool muted = false;
  bool speaker = false;
  bool ringing = false;
  bool reconnecting = false;
  bool acquiring = false;
  String error = '';
  String health = '';
  DateTime? startedAt;
  int endedTick = 0; // bumps when a call ends, so history views reload

  /// How the last call ended (set together with [endedTick]).
  CallEnd? lastEnd;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  bool _isCaller = false;
  int _restarts = 0;
  Timer? _ringTimer, _failTimer, _monitor;
  bool _incomingCall = false;
  final List<RTCIceCandidate> _pending = [];
  List<Map<String, dynamic>> _iceServers = const [
    {'urls': 'stun:stun.l.google.com:19302'},
  ];
  DateTime _iceAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  bool get busy => status != CallStatus.idle || acquiring;

  /// Forces a status (tests of what the app does around a call: foreground service, privacy lock).
  @visibleForTesting
  void debugSetStatus(CallStatus st, {CallPeer? withPeer}) {
    status = st;
    if (withPeer != null) peer = withPeer;
    _changed();
  }

  /// Puts an outgoing call in the ringing state without touching the microphone (tests).
  @visibleForTesting
  void debugStartOutgoing(String friendId, String name) {
    peer = CallPeer(friendId, name);
    _isCaller = true;
    _incomingCall = false;
    status = reduceCall(status, CallEvent.localInvite).status;
    _armRing();
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<List<Map<String, dynamic>>> _loadIce() async {
    if (DateTime.now().difference(_iceAt) < _iceCacheTtl) return _iceServers;
    try {
      final res = await api.get('/calls/ice-servers') as Map;
      final list = res['iceServers'];
      if (list is List && list.isNotEmpty) {
        _iceServers = [for (final s in list) Map<String, dynamic>.from(s as Map)];
        _iceAt = DateTime.now();
      }
    } catch (_) {/* STUN-only still works on most networks */}
    return _iceServers;
  }

  /// Handles call-related socket frames; returns true if consumed.
  bool onFrame(Map<String, dynamic> m) {
    final from = m['from'];
    switch (m['type']) {
      case 'call-invite':
        if (from is! String) return true;
        final name = (m['fromName'] as String?) ?? 'Người dùng';
        if (!canCall || busy || reduceCall(status, CallEvent.remoteInvite).outcome == CallOutcome.busy) {
          socket.send({'type': 'call-reject', 'to': from, 'reason': 'busy'});
          if (canCall) onBusyMissed?.call(from, name);
          return true;
        }
        peer = CallPeer(from, name);
        error = '';
        _incomingCall = true;
        status = reduceCall(status, CallEvent.remoteInvite).status;
        _armRing();
        _changed();
      case 'call-ringing':
        if (status == CallStatus.outgoing && from == peer?.id) {
          ringing = true;
          _changed();
        }
      case 'call-accept':
        if (status == CallStatus.outgoing && from == peer?.id) {
          _clearRing();
          status = reduceCall(status, CallEvent.remoteAccept).status;
          _changed();
          _startAsCaller();
        }
      case 'call-reject':
        if (peer?.id == from) {
          error = m['reason'] == 'busy' ? 'Người này đang bận' : 'Cuộc gọi bị từ chối';
          _cleanup(m['reason'] == 'busy' ? CallEvent.remoteBusy : CallEvent.remoteReject);
        }
      case 'call-unavailable':
        if (peer?.id == from) {
          error = 'Người này hiện không trực tuyến';
          _cleanup(CallEvent.unavailable);
        }
      case 'call-end':
        if (peer?.id == from) {
          if (status == CallStatus.incoming) error = 'Bạn nhỡ cuộc gọi từ ${peer!.name}';
          switch (m['reason']) {
            case 'disconnected':
              error = 'Đối phương bị mất kết nối, cuộc gọi đã kết thúc';
            case 'media-error':
              error = 'Đối phương không bật được micro nên không nghe máy được';
            case 'failed':
              error = 'Không thể kết nối trực tiếp giữa hai thiết bị (mạng đang chặn). Thử lại bằng mạng khác.';
          }
          _cleanup(CallEvent.remoteEnd);
        }
      case 'offer':
        if (peer?.id == from) _onOffer(m['sdp']);
      case 'answer':
        if (peer?.id == from) _onAnswer(m['sdp']);
      case 'ice':
        if (peer?.id == from && m['candidate'] is Map) _onRemoteIce(Map<String, dynamic>.from(m['candidate'] as Map));
      case 'call-error':
        error = (m['error'] as String?) ?? 'Lỗi cuộc gọi';
        if (status != CallStatus.idle) _cleanup(CallEvent.failure);
        _changed();
      default:
        return false;
    }
    return true;
  }

  void _send(String to, Map<String, dynamic> extra) => socket.send({'to': to, ...extra});

  void _armRing() {
    _clearRing();
    _ringTimer = Timer(_ringTimeout, () {
      if (status == CallStatus.incoming || status == CallStatus.outgoing) {
        error = status == CallStatus.incoming ? 'Bạn nhỡ cuộc gọi từ ${peer?.name ?? 'người dùng'}' : 'Không có phản hồi';
        if (peer != null) _send(peer!.id, {'type': 'call-end'});
        _cleanup(CallEvent.ringTimeout);
      }
    });
  }

  void _clearRing() {
    _ringTimer?.cancel();
    _ringTimer = null;
  }

  Future<MediaStream> _acquireMic() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': false,
    }).timeout(_mediaPromptTimeout);
    return stream;
  }

  // ---- outgoing ------------------------------------------------------------------------------------------------

  Future<void> startCall(String friendId, String friendName) async {
    if (busy) return;
    error = '';
    if (!canCall) {
      error = 'Chỉ khách hàng gọi được cho nhau, không gọi cho Admin. Hãy nhắn tin để được hỗ trợ.';
      _changed();
      return;
    }
    if (!socket.ready) {
      error = 'Chưa kết nối tới máy chủ cuộc gọi, vui lòng thử lại sau vài giây.';
      _changed();
      return;
    }
    acquiring = true;
    _changed();
    unawaited(_loadIce());
    MediaStream stream;
    try {
      stream = await _acquireMic();
    } catch (e) {
      acquiring = false;
      error = micErrorMessage(e);
      _changed();
      return;
    }
    acquiring = false;
    if (status != CallStatus.idle || !socket.ready || _disposed) {
      await _stopStream(stream);
      if (!socket.ready) error = 'Mất kết nối tới máy chủ cuộc gọi, vui lòng thử lại.';
      _changed();
      return;
    }
    _local = stream;
    peer = CallPeer(friendId, friendName);
    _isCaller = true;
    _incomingCall = false;
    ringing = false;
    status = reduceCall(status, CallEvent.localInvite).status;
    _send(friendId, {'type': 'call-invite'});
    _armRing();
    _changed();
  }

  Future<void> _startAsCaller() async {
    try {
      await _setupPc();
      final offer = await _pc!.createOffer({'offerToReceiveAudio': 1});
      await _pc!.setLocalDescription(offer);
      _send(peer!.id, {'type': 'offer', 'sdp': {'type': offer.type, 'sdp': offer.sdp}});
    } catch (_) {
      _failCall('Không thể bắt đầu cuộc gọi');
    }
  }

  // ---- incoming ------------------------------------------------------------------------------------------------

  Future<void> accept() async {
    final p = peer;
    if (status != CallStatus.incoming || p == null) return;
    _clearRing();
    _isCaller = false;
    unawaited(_loadIce());
    status = reduceCall(status, CallEvent.localAccept).status;
    _changed();
    MediaStream stream;
    try {
      stream = await _acquireMic();
    } catch (e) {
      if (peer?.id == p.id) _failCall(micErrorMessage(e), 'media-error');
      return;
    }
    if (status != CallStatus.connecting || peer?.id != p.id) {
      await _stopStream(stream);
      return;
    }
    _local = stream;
    _send(p.id, {'type': 'call-accept'});
  }

  void reject() {
    if (status != CallStatus.incoming || peer == null) return;
    _send(peer!.id, {'type': 'call-reject'});
    _cleanup(CallEvent.localReject);
  }

  Future<void> _onOffer(Object? sdp) async {
    try {
      if (_local == null || sdp is! Map) return;
      final desc = RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?);
      if (_pc != null && status == CallStatus.connected) {
        // The caller restarted ICE after the network path dropped: answer on the same connection.
        await _pc!.setRemoteDescription(desc);
        await _flushPending();
        final a = await _pc!.createAnswer();
        await _pc!.setLocalDescription(a);
        _send(peer!.id, {'type': 'answer', 'sdp': {'type': a.type, 'sdp': a.sdp}});
        return;
      }
      await _setupPc();
      await _pc!.setRemoteDescription(desc);
      await _flushPending();
      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      _send(peer!.id, {'type': 'answer', 'sdp': {'type': answer.type, 'sdp': answer.sdp}});
      _markConnected();
    } catch (_) {
      _failCall('Không thể kết nối cuộc gọi');
    }
  }

  Future<void> _onAnswer(Object? sdp) async {
    final pc = _pc;
    if (pc == null || sdp is! Map) return;
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp['sdp'] as String?, sdp['type'] as String?));
      await _flushPending();
      if (status == CallStatus.connected) return; // answer to an ICE restart
      _markConnected();
    } catch (_) {
      _failCall('Không thể kết nối cuộc gọi');
    }
  }

  void _markConnected() {
    status = reduceCall(status, CallEvent.mediaUp).status;
    startedAt = DateTime.now();
    ringing = false;
    _startMonitor();
    unawaited(Helper.setSpeakerphoneOn(speaker).catchError((_) {}));
    _changed();
  }

  Future<void> _onRemoteIce(Map<String, dynamic> c) async {
    final cand = c['candidate'];
    if (cand is! String || cand.isEmpty) return;
    final ice = RTCIceCandidate(cand, c['sdpMid'] as String?, c['sdpMLineIndex'] as int?);
    final pc = _pc;
    if (pc == null || await pc.getRemoteDescription() == null) {
      _pending.add(ice);
      return;
    }
    try {
      await pc.addCandidate(ice);
    } catch (_) {/* late or malformed */}
  }

  Future<void> _flushPending() async {
    final queued = List<RTCIceCandidate>.of(_pending);
    _pending.clear();
    for (final c in queued) {
      try {
        await _pc?.addCandidate(c);
      } catch (_) {/* ignore */}
    }
  }

  // ---- peer connection -----------------------------------------------------------------------------------------

  Future<void> _setupPc() async {
    final local = _local;
    if (local == null) throw StateError('no microphone');
    final servers = await _loadIce();
    final pc = await createPeerConnection({'iceServers': servers, 'sdpSemantics': 'unified-plan'});
    for (final t in local.getAudioTracks()) {
      await pc.addTrack(t, local);
    }
    pc.onIceCandidate = (c) {
      final p = peer;
      if (p != null && c.candidate != null && c.candidate!.isNotEmpty) {
        _send(p.id, {'type': 'ice', 'candidate': {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}});
      }
    };
    pc.onConnectionState = (state) {
      if (_pc != pc || status != CallStatus.connected) return;
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          reconnecting = false;
          _failTimer?.cancel();
          _failTimer = null;
          _changed();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          reconnecting = true;
          _changed();
          _tryIceRestart(pc);
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          _cleanup(CallEvent.remoteEnd);
        default:
      }
    };
    _pc = pc;
  }

  /// Only the original caller offers a restart; both sides give up after [_reconnectGrace].
  Future<void> _tryIceRestart(RTCPeerConnection pc) async {
    if (_pc != pc || status != CallStatus.connected) return;
    _failTimer ??= Timer(_reconnectGrace, () {
      _failTimer = null;
      if (_pc == pc && status == CallStatus.connected && reconnecting) {
        _failCall('Mất kết nối mạng giữa hai thiết bị, cuộc gọi đã kết thúc.', 'failed');
      }
    });
    if (!_isCaller || _restarts >= _maxIceRestarts) return;
    _restarts++;
    try {
      final offer = await pc.createOffer({'iceRestart': true, 'offerToReceiveAudio': 1});
      await pc.setLocalDescription(offer);
      _send(peer!.id, {'type': 'offer', 'sdp': {'type': offer.type, 'sdp': offer.sdp}});
    } catch (_) {/* the grace timer ends the call */}
  }

  /// Every 2 s: is audio arriving? Ends the call if the path never comes up.
  void _startMonitor() {
    _monitor?.cancel();
    final pc = _pc;
    if (pc == null) return;
    final began = DateTime.now();
    var lastRecv = 0;
    var stalled = 0;
    var flowed = false;
    health = 'Đang thiết lập đường truyền âm thanh…';
    _monitor = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_pc != pc || status != CallStatus.connected) return;
      final ice = pc.iceConnectionState;
      final up = ice == RTCIceConnectionState.RTCIceConnectionStateConnected || ice == RTCIceConnectionState.RTCIceConnectionStateCompleted;
      final elapsed = DateTime.now().difference(began);
      if (!up) {
        if (elapsed > _mediaSetupTimeout) {
          _failCall('Không thiết lập được đường truyền âm thanh giữa hai thiết bị (mạng đang chặn kết nối trực tiếp). Thử lại bằng mạng khác, ví dụ Wi-Fi thay cho 4G.', 'failed');
          return;
        }
        health = elapsed.inSeconds > 8 ? 'Đường truyền âm thanh chưa thông, có thể mạng đang chặn. Đang thử thêm…' : 'Đang thiết lập đường truyền âm thanh…';
        _changed();
        return;
      }
      var recv = 0;
      try {
        for (final r in await pc.getStats()) {
          if (r.type == 'inbound-rtp' && r.values['kind'] == 'audio') {
            final b = r.values['bytesReceived'];
            if (b is num) recv = b.toInt();
          }
        }
      } catch (_) {/* stats unavailable: fall back to ICE state alone */}
      if (recv > lastRecv) {
        flowed = true;
        stalled = 0;
      } else {
        stalled++;
      }
      lastRecv = recv;
      if (stalled >= 3) {
        health = flowed ? 'Mất tín hiệu âm thanh từ đối phương.' : 'Chưa nhận được âm thanh từ đối phương. Nhờ họ kiểm tra micro.';
      } else {
        health = 'Âm thanh đã thông';
      }
      _changed();
    });
  }

  // ---- controls ---------------------------------------------------------------------------------------------------

  void toggleMute() {
    final l = _local;
    if (l == null) return;
    muted = !muted;
    for (final t in l.getAudioTracks()) {
      t.enabled = !muted;
    }
    _changed();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    _changed();
    try {
      await Helper.setSpeakerphoneOn(speaker);
    } catch (_) {/* device without the route */}
  }

  void hangUp() {
    final p = peer;
    if (p != null && status != CallStatus.idle) _send(p.id, {'type': 'call-end'});
    _cleanup(CallEvent.localHangup);
  }

  /// Ends the call because of a local problem and tells the peer (otherwise it would hang on "calling").
  void _failCall(String message, [String? reason]) {
    error = message;
    final p = peer;
    if (p != null && status != CallStatus.idle) _send(p.id, {'type': 'call-end', 'reason': ?reason});
    _cleanup(CallEvent.failure);
  }

  void clearError() {
    error = '';
    _changed();
  }

  Future<void> _stopStream(MediaStream s) async {
    for (final t in s.getTracks()) {
      try {
        await t.stop();
      } catch (_) {/* stopped */}
    }
    try {
      await s.dispose();
    } catch (_) {/* disposed */}
  }

  void _cleanup([CallEvent event = CallEvent.failure]) {
    final was = status != CallStatus.idle;
    if (was && peer != null) {
      final step = reduceCall(status, event);
      lastEnd = CallEnd(
        peerId: peer!.id,
        peerName: peer!.name,
        outcome: step.outcome ?? CallOutcome.ended,
        incoming: _incomingCall,
        duration: startedAt == null ? Duration.zero : DateTime.now().difference(startedAt!),
      );
    }
    _clearRing();
    _failTimer?.cancel();
    _failTimer = null;
    _monitor?.cancel();
    _monitor = null;
    ringing = false;
    reconnecting = false;
    _restarts = 0;
    health = '';
    final pc = _pc;
    final local = _local;
    _pc = null;
    _local = null;
    unawaited(() async {
      try {
        await pc?.close();
        await pc?.dispose();
      } catch (_) {/* closing */}
      if (local != null) await _stopStream(local);
      if (speaker) {
        try {
          await Helper.setSpeakerphoneOn(false);
        } catch (_) {/* ignore */}
      }
    }());
    status = CallStatus.idle;
    peer = null;
    muted = false;
    speaker = false;
    startedAt = null;
    _pending.clear();
    if (was) endedTick++;
    _changed();
  }

  /// Call when the socket drops: a dead signalling channel cannot carry a call.
  void onSocketLost() {
    if (status != CallStatus.idle) {
      error = error.isEmpty ? 'Mất kết nối, cuộc gọi đã kết thúc' : error;
      _cleanup(CallEvent.socketLost);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    hangUp();
    super.dispose();
  }
}

/// Text for one entry of `GET /me/calls` (FriendsView.vue `callLine`).
String callLine(Map<String, dynamic> c) {
  final secs = (c['durationSeconds'] as num?)?.toInt() ?? 0;
  final dur = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
  final out = c['direction'] == 'outgoing';
  return switch (c['status']) {
    'completed' => '${out ? 'Cuộc gọi thoại đi' : 'Cuộc gọi thoại đến'} · $dur',
    'missed' => out ? 'Cuộc gọi đi · Không ai nghe máy' : 'Cuộc gọi nhỡ',
    'busy' => out ? 'Cuộc gọi đi · Máy bận' : 'Cuộc gọi nhỡ (bạn đang bận)',
    'rejected' => out ? 'Cuộc gọi đi · Bị từ chối' : 'Bạn đã từ chối cuộc gọi',
    'failed' => 'Cuộc gọi · Không kết nối được âm thanh',
    _ => 'Cuộc gọi thoại',
  };
}

bool isMissedCall(Map<String, dynamic> c) => c['direction'] == 'incoming' && (c['status'] == 'missed' || c['status'] == 'busy');
