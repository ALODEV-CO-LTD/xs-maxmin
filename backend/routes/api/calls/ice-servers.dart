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
///   XOSO_CF_TURN_KEY_ID + XOSO_CF_TURN_API_TOKEN
///                        Cloudflare Realtime TURN (dashboard > Realtime >
///                        TURN). The server asks Cloudflare for short-lived
///                        credentials and caches them; takes precedence over
///                        the settings above. XOSO_CF_TURN_API_BASE overrides
///                        the API host (tests).
Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.get) {
    return Response(statusCode: 405, body: 'Method not allowed');
  }
  final auth = requireAuth(context);
  if (auth == null) return unauthorized();

  final env = Platform.environment;
  List<String> split(String? v) =>
      (v ?? '').split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  // Cloudflare Realtime TURN: needs no open ports on our side.
  final cfKey = env['XOSO_CF_TURN_KEY_ID'];
  final cfToken = env['XOSO_CF_TURN_API_TOKEN'];
  if (cfKey != null && cfKey.isNotEmpty && cfToken != null && cfToken.isNotEmpty) {
    final cf = await _cloudflareIceServers(cfKey, cfToken, env['XOSO_CF_TURN_API_BASE']);
    if (cf != null) {
      return Response.json(body: {'iceServers': cf, 'ttl': _cfRefreshSeconds, 'turn': true});
    }
    // Cloudflare unreachable: fall through to STUN (and any other TURN) so
    // calls on easy networks keep working.
  }

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

// Cloudflare credentials are valid for [_cfTtlSeconds]; one set is shared by
// everyone and refreshed well before it expires.
const _cfTtlSeconds = 86400;
const _cfRefreshSeconds = 6 * 3600;
List<Map<String, Object?>>? _cfCache;
DateTime? _cfCachedAt;

Future<List<Map<String, Object?>>?> _cloudflareIceServers(String keyId, String token, String? apiBase) async {
  final cached = _cfCache;
  final at = _cfCachedAt;
  if (cached != null && at != null && DateTime.now().difference(at).inSeconds < _cfRefreshSeconds) {
    return cached;
  }
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final base = (apiBase == null || apiBase.isEmpty) ? 'https://rtc.live.cloudflare.com' : apiBase;
    final uri = Uri.parse('$base/v1/turn/keys/$keyId/credentials/generate-ice-servers');
    final req = await client.postUrl(uri).timeout(const Duration(seconds: 5));
    req.headers
      ..set('Authorization', 'Bearer $token')
      ..contentType = ContentType.json;
    req.write(jsonEncode({'ttl': _cfTtlSeconds}));
    final res = await req.close().timeout(const Duration(seconds: 8));
    final text = await utf8.decoder.bind(res).join().timeout(const Duration(seconds: 8));
    if (res.statusCode < 200 || res.statusCode >= 300) return _cfCache; // stale beats nothing
    final decoded = jsonDecode(text) as Map<String, dynamic>;
    final raw = decoded['iceServers'];
    // Documented as an array; accept a single object too.
    final list = raw is List ? raw : (raw is Map ? [raw] : const <Object?>[]);
    final servers = <Map<String, Object?>>[
      for (final e in list)
        if (e is Map && e['urls'] != null)
          {
            'urls': e['urls'],
            if (e['username'] != null) 'username': e['username'],
            if (e['credential'] != null) 'credential': e['credential'],
          },
    ];
    if (servers.isEmpty) return _cfCache;
    _cfCache = servers;
    _cfCachedAt = DateTime.now();
    return servers;
  } catch (_) {
    return _cfCache;
  } finally {
    client.close(force: true);
  }
}
