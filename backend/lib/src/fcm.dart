import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:server/src/push_message.dart';
import 'package:server/src/push_tokens.dart';
import 'package:sqlite3/sqlite3.dart';

/// Firebase Cloud Messaging (HTTP v1) for the Android app.
///
/// PRIVACY RULE (same as APNs): a push (and every log line here) carries ONLY
/// the sender's display name and the kind (message / call). Never message
/// text, key material or file names. Configured only from the environment;
/// without configuration it is a silent no-op.

const fcmScope = 'https://www.googleapis.com/auth/firebase.messaging';
const _defaultTokenUri = 'https://oauth2.googleapis.com/token';

/// One outgoing HTTPS request (already fully built).
class FcmHttpRequest {
  FcmHttpRequest({required this.url, required this.headers, required this.body});
  final Uri url;
  final Map<String, String> headers;
  final String body;
}

class FcmHttpResponse {
  const FcmHttpResponse(this.status, [this.body = '']);
  final int status;
  final String body;
}

/// The HTTP layer, injectable so tests never open a socket.
typedef FcmTransport = Future<FcmHttpResponse> Function(FcmHttpRequest request);

class FcmConfig {
  const FcmConfig({required this.clientEmail, required this.privateKeyPem, required this.tokenUri, required this.projectId});
  final String clientEmail;
  final String privateKeyPem;
  final String tokenUri;
  final String projectId;

  /// Reads XOSO_FCM_CREDENTIALS_PATH (service-account JSON) and optionally
  /// XOSO_FCM_PROJECT_ID. Returns null (FCM disabled) when missing/invalid.
  static FcmConfig? fromEnv(Map<String, String> env) {
    final path = env['XOSO_FCM_CREDENTIALS_PATH']?.trim() ?? '';
    if (path.isEmpty) return null;
    try {
      final j = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      final email = (j['client_email'] as String?)?.trim() ?? '';
      final key = (j['private_key'] as String?) ?? '';
      final override = env['XOSO_FCM_PROJECT_ID']?.trim() ?? '';
      final project = override.isNotEmpty ? override : ((j['project_id'] as String?)?.trim() ?? '');
      final uri = (j['token_uri'] as String?)?.trim();
      if (email.isEmpty || !key.contains('PRIVATE KEY') || project.isEmpty) return null;
      return FcmConfig(
        clientEmail: email,
        privateKeyPem: key,
        tokenUri: (uri == null || uri.isEmpty) ? _defaultTokenUri : uri,
        projectId: project,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The JSON body of `messages:send` for [message] to [token].
Map<String, dynamic> fcmPayload(String token, PushMessage message) {
  final isCall = message.kind == PushKind.call;
  return {
    'message': {
      'token': token,
      'notification': {'title': message.title, 'body': message.body},
      'data': {'friendId': message.friendId, 'kind': message.kind.name},
      'android': {
        'priority': 'HIGH',
        'ttl': isCall ? '30s' : '3600s',
        'notification': {'channel_id': isCall ? 'mamba_calls' : 'mamba_messages', 'sound': 'default'},
      },
    },
  };
}

class FcmSender implements PushSender {
  FcmSender({
    required this.config,
    required this.db,
    FcmTransport? transport,
    DateTime Function()? clock,
  })  : _transport = transport ?? _httpTransport,
        _clock = clock ?? DateTime.now;

  final FcmConfig config;
  final Database Function() db;
  final FcmTransport _transport;
  final DateTime Function() _clock;

  String? _accessToken;
  DateTime? _accessExpiry;
  Future<String?>? _refreshing;

  /// The signed service-account assertion (RS256), valid 1 hour.
  String signedAssertion() {
    final iat = _clock().millisecondsSinceEpoch ~/ 1000;
    final jwt = JWT({
      'iss': config.clientEmail,
      'scope': fcmScope,
      'aud': config.tokenUri,
      'iat': iat,
      'exp': iat + 3600,
    });
    return jwt.sign(RSAPrivateKey(config.privateKeyPem), algorithm: JWTAlgorithm.RS256, noIssueAt: true);
  }

  /// OAuth2 access token, cached until ~5 minutes before it expires.
  Future<String?> accessToken() {
    final now = _clock();
    if (_accessToken != null && _accessExpiry != null && now.isBefore(_accessExpiry!.subtract(const Duration(minutes: 5)))) {
      return Future.value(_accessToken);
    }
    return _refreshing ??= _refresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _refresh() async {
    final res = await _transport(FcmHttpRequest(
      url: Uri.parse(config.tokenUri),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=${Uri.encodeQueryComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}'
          '&assertion=${Uri.encodeQueryComponent(signedAssertion())}',
    ));
    if (res.status != 200) {
      stderr.writeln('[fcm] token exchange failed: status=${res.status}');
      return null;
    }
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final t = j['access_token'] as String?;
    if (t == null || t.isEmpty) return null;
    _accessToken = t;
    _accessExpiry = _clock().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3600));
    return t;
  }

  /// True when [res] says the registration token is dead and must be deleted.
  static bool isDeadToken(FcmHttpResponse res) {
    if (res.status == 404) return true;
    try {
      final err = (jsonDecode(res.body) as Map)['error'] as Map?;
      if (err == null) return false;
      final codes = [
        for (final d in (err['details'] as List? ?? const [])) if (d is Map) d['errorCode'],
      ];
      if (codes.contains('UNREGISTERED')) return true;
      if (err['status'] == 'NOT_FOUND') return true;
      if (err['status'] == 'INVALID_ARGUMENT' && '${err['message']}'.toLowerCase().contains('token')) return true;
    } catch (_) {}
    return false;
  }

  @override
  Future<void> send(String userId, PushMessage message) async {
    final database = db();
    final tokens = pushTokensOf(database, userId, platform: 'android');
    if (tokens.isEmpty) return;
    try {
      final access = await accessToken();
      if (access == null) return;
      final url = Uri.parse('https://fcm.googleapis.com/v1/projects/${config.projectId}/messages:send');
      for (final token in tokens) {
        try {
          final res = await _transport(FcmHttpRequest(
            url: url,
            headers: {'authorization': 'Bearer $access', 'content-type': 'application/json'},
            body: jsonEncode(fcmPayload(token, message)),
          ));
          if (res.status == 200) continue;
          if (isDeadToken(res)) {
            deletePushToken(database, token);
          } else {
            if (res.status == 401) _accessToken = null;
            stderr.writeln('[fcm] push failed: status=${res.status}');
          }
        } catch (e) {
          stderr.writeln('[fcm] push error: ${e.runtimeType}');
        }
      }
    } catch (e) {
      // Never log payloads; the error type is enough.
      stderr.writeln('[fcm] error: ${e.runtimeType}');
    }
  }
}

Future<FcmHttpResponse> _httpTransport(FcmHttpRequest r) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.postUrl(r.url).timeout(const Duration(seconds: 10));
    r.headers.forEach(req.headers.set);
    req.add(utf8.encode(r.body));
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 15));
    return FcmHttpResponse(res.statusCode, body);
  } finally {
    client.close(force: true);
  }
}
