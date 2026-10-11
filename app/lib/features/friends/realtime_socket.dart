import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';

/// Where chat / call code sends JSON frames.
abstract class FrameSink {
  bool get ready;
  void send(Map<String, dynamic> frame);
}

/// What the chat header shows: Đang kết nối / Đã kết nối / Mất kết nối.
enum ConnState { connecting, connected, disconnected }

typedef ChannelFactory = WebSocketChannel Function(Uri uri);

WebSocketChannel _defaultFactory(Uri uri) => IOWebSocketChannel.connect(uri, pingInterval: const Duration(seconds: 20), connectTimeout: const Duration(seconds: 15));

/// Reconnect delay: 1 s, 2 s, 4 s ... capped at 30 s, plus up to 25 % jitter.
Duration reconnectDelay(int attempt, [Random? rnd]) {
  final base = min(30000, 1000 * (1 << min(attempt, 5)));
  return Duration(milliseconds: base + (rnd ?? Random()).nextInt(base ~/ 4 + 1));
}

/// `wss://host/api/ws/calls?token=...` - signalling for calls, the E2EE chat relay and push events - with automatic
/// reconnection and backoff. The app opens it once for the signed-in customer and keeps it (with backoff) while the
/// process is alive; [stop] closes it for good.
class RealtimeSocket extends ChangeNotifier implements FrameSink {
  RealtimeSocket({required this.tokenProvider, ChannelFactory? factory, Duration Function(int)? delay})
      : _factory = factory ?? _defaultFactory,
        _delay = delay ?? reconnectDelay;

  final String? Function() tokenProvider;
  final ChannelFactory _factory;
  final Duration Function(int attempt) _delay;
  final _frames = StreamController<Map<String, dynamic>>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;
  bool _wanted = false;
  bool _disposed = false;
  bool _ready = false;
  bool _dialing = false;
  int _generation = 0;

  @override
  bool get ready => _ready;
  Stream<Map<String, dynamic>> get frames => _frames.stream;
  bool get wanted => _wanted;

  ConnState get state => _ready ? ConnState.connected : (_wanted && _dialing ? ConnState.connecting : ConnState.disconnected);

  void start() {
    if (_wanted || _disposed) return;
    _wanted = true;
    _attempt = 0;
    _connect();
  }

  /// Closes the socket and stops reconnecting (screen left).
  void stop() {
    _wanted = false;
    _dialing = false;
    _retry?.cancel();
    _retry = null;
    _teardown();
  }

  /// App came back to the foreground: reconnect right away instead of waiting for the backoff.
  void reconnectNow() {
    if (!_wanted || _ready) return;
    _retry?.cancel();
    _attempt = 0;
    _connect();
  }

  void _teardown() {
    _generation++;
    _sub?.cancel();
    _sub = null;
    final c = _channel;
    _channel = null;
    if (c != null) {
      try {
        c.sink.close();
      } catch (_) {/* closing */}
    }
    if (_ready) {
      _ready = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _connect() async {
    final token = tokenProvider();
    if (!_wanted || token == null || token.isEmpty) return;
    _teardown();
    final gen = _generation;
    _dialing = true;
    notifyListeners();
    try {
      final uri = Uri.parse(AppConfig.wsCalls).replace(queryParameters: {'token': token});
      final ch = _factory(uri);
      _channel = ch;
      await ch.ready;
      if (gen != _generation) return;
      _ready = true;
      _dialing = false;
      _attempt = 0;
      notifyListeners();
      _sub = ch.stream.listen(
        (raw) {
          if (gen != _generation || raw is! String) return;
          try {
            final m = jsonDecode(raw);
            if (m is Map<String, dynamic>) _frames.add(m);
          } catch (_) {/* not JSON */}
        },
        onDone: () => _lost(gen),
        onError: (_) => _lost(gen),
        cancelOnError: true,
      );
    } catch (_) {
      _lost(gen);
    }
  }

  void _lost(int gen) {
    if (gen != _generation) return;
    _teardown();
    _dialing = false;
    if (!_disposed) notifyListeners();
    if (!_wanted || _disposed) return;
    _retry?.cancel();
    _retry = Timer(_delay(_attempt++), _connect);
  }

  @override
  void send(Map<String, dynamic> frame) {
    final c = _channel;
    if (!_ready || c == null) return;
    c.sink.add(jsonEncode(frame));
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    _frames.close();
    super.dispose();
  }
}
