import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http2/http2.dart';
import 'package:server/src/database.dart' show appDatabase;
import 'package:server/src/push_tokens.dart';
import 'package:sqlite3/sqlite3.dart';

/// Apple Push Notification service (APNs) for the iOS app.
///
/// PRIVACY RULE: a push (and every log line here) carries ONLY the sender's
/// display name and the kind (message / call). Never message text, key
/// material or file names - chat is end-to-end encrypted and the server does
/// not know any of that. Everything is configured from the environment; with
/// no configuration the sender is a silent no-op.

enum PushKind { message, call }

class PushMessage {
  const PushMessage({required this.kind, required this.title, required this.body, required this.friendId});
  final PushKind kind;
  final String title;
  final String body;

  /// The id of the SENDER (the app opens /friends/chat/<friendId> on tap).
  final String friendId;

  /// The APNs JSON payload.
  Map<String, dynamic> toPayload() => {
        'aps': {
          'alert': {'title': title, 'body': body},
          'sound': 'default',
          'thread-id': friendId,
        },
        'friendId': friendId,
        'kind': kind.name,
      };
}

/// Sends a push to every iOS device registered for [userId].
abstract class PushSender {
  Future<void> send(String userId, PushMessage message);
}

class NoopPushSender implements PushSender {
  @override
  Future<void> send(String userId, PushMessage message) async {}
}

/// One HTTP/2 request to APNs, already fully built.
class ApnsRequest {
  ApnsRequest({required this.sandbox, required this.token, required this.headers, required this.body});
  final bool sandbox;
  final String token;
  final Map<String, String> headers;
  final List<int> body;
}

class ApnsResponse {
  const ApnsResponse(this.status, [this.reason]);
  final int status;

  /// APNs `reason` from the JSON body of a failure, e.g. `BadDeviceToken`.
  final String? reason;
}

/// The HTTP/2 layer, injectable so tests never open a socket.
typedef ApnsTransport = Future<ApnsResponse> Function(ApnsRequest request);

class ApnsConfig {
  const ApnsConfig({
    required this.keyPem,
    required this.keyId,
    required this.teamId,
    required this.topic,
    required this.sandbox,
  });
  final String keyPem;
  final String keyId;
  final String teamId;
  final String topic;
  final bool sandbox;

  /// Reads XOSO_APNS_KEY_PATH / _KEY_ID / _TEAM_ID / _TOPIC / _SANDBOX.
  /// Returns null (APNs disabled) if anything required is missing/unreadable.
  static ApnsConfig? fromEnv(Map<String, String> env) {
    final path = env['XOSO_APNS_KEY_PATH']?.trim() ?? '';
    final keyId = env['XOSO_APNS_KEY_ID']?.trim() ?? '';
    final teamId = env['XOSO_APNS_TEAM_ID']?.trim() ?? '';
    if (path.isEmpty || keyId.isEmpty || teamId.isEmpty) return null;
    final String pem;
    try {
      pem = File(path).readAsStringSync();
    } catch (_) {
      return null;
    }
    final topic = (env['XOSO_APNS_TOPIC']?.trim().isNotEmpty ?? false) ? env['XOSO_APNS_TOPIC']!.trim() : 'vn.mamba.mambaApp';
    final sandbox = (env['XOSO_APNS_SANDBOX'] ?? '').trim().toLowerCase() == 'true';
    return ApnsConfig(keyPem: pem, keyId: keyId, teamId: teamId, topic: topic, sandbox: sandbox);
  }
}

class ApnsSender implements PushSender {
  ApnsSender({
    required this.config,
    required this.db,
    ApnsTransport? transport,
    DateTime Function()? clock,
  })  : _transport = transport ?? Http2ApnsTransport().call,
        _clock = clock ?? DateTime.now;

  final ApnsConfig config;
  final Database Function() db;
  final ApnsTransport _transport;
  final DateTime Function() _clock;

  String? _jwt;
  DateTime? _jwtAt;
  static const _jwtLifetime = Duration(minutes: 50);

  /// Provider authentication token (ES256), cached ~50 minutes (Apple wants a
  /// refresh at most every 60 min and at least every 20 min... of use).
  String providerToken() {
    final now = _clock();
    if (_jwt != null && _jwtAt != null && now.difference(_jwtAt!) < _jwtLifetime) return _jwt!;
    final jwt = JWT({'iss': config.teamId, 'iat': now.millisecondsSinceEpoch ~/ 1000}, header: {'kid': config.keyId});
    _jwt = jwt.sign(ECPrivateKey(config.keyPem), algorithm: JWTAlgorithm.ES256, noIssueAt: true);
    _jwtAt = now;
    return _jwt!;
  }

  /// The headers APNs expects for [message].
  Map<String, String> headersFor(PushMessage message) {
    final isCall = message.kind == PushKind.call;
    final expiry = _clock().millisecondsSinceEpoch ~/ 1000 + (isCall ? 30 : 3600);
    return {
      'authorization': 'bearer ${providerToken()}',
      'apns-topic': config.topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': '$expiry',
      'content-type': 'application/json',
    };
  }

  @override
  Future<void> send(String userId, PushMessage message) async {
    final database = db();
    final tokens = pushTokensOf(database, userId);
    if (tokens.isEmpty) return;
    final body = utf8.encode(jsonEncode(message.toPayload()));
    for (final token in tokens) {
      try {
        final res = await _transport(
          ApnsRequest(sandbox: config.sandbox, token: token, headers: headersFor(message), body: body),
        );
        if (res.status == 410 || res.reason == 'BadDeviceToken' || res.reason == 'Unregistered') {
          deletePushToken(database, token);
        } else if (res.status != 200) {
          stderr.writeln('[apns] push failed: status=${res.status} reason=${res.reason}');
        }
      } catch (e) {
        // Never log payloads; the error type is enough.
        stderr.writeln('[apns] push error: ${e.runtimeType}');
      }
    }
  }
}

/// Real HTTP/2 connection to api.push.apple.com (kept open, reopened on error).
class Http2ApnsTransport {
  final Map<String, ClientTransportConnection> _conns = {};

  Future<ClientTransportConnection> _connection(String host) async {
    final existing = _conns[host];
    if (existing != null && existing.isOpen) return existing;
    final socket = await SecureSocket.connect(host, 443, supportedProtocols: ['h2']).timeout(const Duration(seconds: 10));
    final conn = ClientTransportConnection.viaSocket(socket);
    _conns[host] = conn;
    return conn;
  }

  Future<ApnsResponse> call(ApnsRequest r) async {
    final host = r.sandbox ? 'api.sandbox.push.apple.com' : 'api.push.apple.com';
    try {
      return await _once(host, r).timeout(const Duration(seconds: 15));
    } catch (_) {
      _conns.remove(host)?.finish();
      return await _once(host, r).timeout(const Duration(seconds: 15));
    }
  }

  Future<ApnsResponse> _once(String host, ApnsRequest r) async {
    final conn = await _connection(host);
    final stream = conn.makeRequest([
      Header.ascii(':method', 'POST'),
      Header.ascii(':scheme', 'https'),
      Header.ascii(':path', '/3/device/${r.token}'),
      Header.ascii(':authority', host),
      for (final e in r.headers.entries) Header.ascii(e.key, e.value),
      Header.ascii('content-length', '${r.body.length}'),
    ]);
    stream.outgoingMessages.add(DataStreamMessage(r.body, endStream: true));
    var status = 0;
    final data = <int>[];
    await for (final m in stream.incomingMessages) {
      if (m is HeadersStreamMessage) {
        for (final h in m.headers) {
          if (utf8.decode(h.name) == ':status') status = int.tryParse(utf8.decode(h.value)) ?? 0;
        }
      } else if (m is DataStreamMessage) {
        data.addAll(m.bytes);
      }
    }
    String? reason;
    if (data.isNotEmpty) {
      try {
        reason = (jsonDecode(utf8.decode(data)) as Map)['reason'] as String?;
      } catch (_) {}
    }
    return ApnsResponse(status, reason);
  }
}

PushSender? _sender;
bool _loggedDisabled = false;

/// The sender used by the websocket hooks. Tests replace it with a fake via
/// the setter; by default it is built once from the environment (no-op when
/// APNs is not configured).
PushSender get pushSender => _sender ??= _fromEnvironment(Platform.environment, () => appDatabase);

set pushSender(PushSender? s) => _sender = s;

/// Builds the real/no-op sender from [env]; logs once when disabled.
PushSender buildPushSender(Map<String, String> env, Database Function() db, {ApnsTransport? transport}) =>
    _fromEnvironment(env, db, transport: transport);

PushSender _fromEnvironment(Map<String, String> env, Database Function() db, {ApnsTransport? transport}) {
  final cfg = ApnsConfig.fromEnv(env);
  if (cfg == null) {
    if (!_loggedDisabled) {
      _loggedDisabled = true;
      stderr.writeln('[apns] not configured (XOSO_APNS_*): push notifications disabled');
    }
    return NoopPushSender();
  }
  return ApnsSender(config: cfg, db: db, transport: transport);
}
