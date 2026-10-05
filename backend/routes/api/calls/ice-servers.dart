import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/auth_middleware.dart';

/// `GET /api/calls/ice-servers` -> `{ iceServers: [...], ttl, turn }`
///
/// What the browser's RTCPeerConnection uses to find a path between two
/// phones. STUN alone fails behind strict NATs (many 4G/5G carriers, office
/// networks); a TURN relay fixes that. It is configured by the server's
/// environment so no credentials live in the repository or the frontend:
///   XOSO_STUN_URLS       comma-separated, default Google's public STUN
///   XOSO_TURN_URLS       comma-separated turn:/turns: URLs (empty = no TURN)
///   XOSO_TURN_SECRET     shared secret of coturn's `use-auth-secret`: the
///                        server hands out per-user credentials valid for
///                        [_ttlSeconds] (recommended)
///   XOSO_TURN_USERNAME / XOSO_TURN_CREDENTIAL
///                        static credentials instead of the secret
Response onRequest(RequestContext context) {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final env = Platform.environment;
  List<String> split(String? v) =>
      (v ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  final stun = split(env['XOSO_STUN_URLS']);
  final servers = <Map<String, Object>>[
    {'urls': stun.isEmpty ? ['stun:stun.l.google.com:19302'] : stun},
  ];

  final turnUrls = split(env['XOSO_TURN_URLS']);
  var hasTurn = false;
  if (turnUrls.isNotEmpty) {
    final secret = env['XOSO_TURN_SECRET'];
    if (secret != null && secret.isNotEmpty) {
      final expiry = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + _ttlSeconds;
      final username = '$expiry:${auth.userId}';
      final credential = base64Encode(Hmac(sha1, utf8.encode(secret)).convert(utf8.encode(username)).bytes);
      servers.add({'urls': turnUrls, 'username': username, 'credential': credential});
      hasTurn = true;
    } else if ((env['XOSO_TURN_USERNAME'] ?? '').isNotEmpty && (env['XOSO_TURN_CREDENTIAL'] ?? '').isNotEmpty) {
      servers.add({
        'urls': turnUrls,
        'username': env['XOSO_TURN_USERNAME']!,
        'credential': env['XOSO_TURN_CREDENTIAL']!,
      });
      hasTurn = true;
    }
  }

  return Response.json(body: {'iceServers': servers, 'ttl': _ttlSeconds, 'turn': hasTurn});
}

const _ttlSeconds = 3600;
