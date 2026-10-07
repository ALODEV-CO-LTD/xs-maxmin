import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

/// Signing key for all tokens. Set XOSO_JWT_SECRET in the environment of the
/// server (a long random string). If it is missing, a random key is generated
/// for this process only: nothing is ever hard-coded in the repository, but all
/// logins are invalidated whenever the server restarts.
final String _jwtSecret = _loadJwtSecret();

String _loadJwtSecret() {
  final fromEnv = Platform.environment['XOSO_JWT_SECRET'];
  if (fromEnv != null && fromEnv.length >= 16) return fromEnv;
  stderr.writeln('WARNING: XOSO_JWT_SECRET not set (or shorter than 16 chars); using a random per-process key.');
  final rng = Random.secure();
  return base64UrlEncode(List<int>.generate(48, (_) => rng.nextInt(256)));
}

/// [sessionId] points at the `device_sessions` row (see sessions.dart) so the
/// session can be revoked server-side; it is the JWT's `sid` claim.
/// Access tokens carry `type: access`; the short-lived pending tokens below
/// carry their own `type` and are refused by [verifyToken].
String issueToken({required String userId, required String role, String? sessionId}) {
  final jwt = JWT({'sub': userId, 'role': role, 'type': 'access', if (sessionId != null) 'sid': sessionId});
  return jwt.sign(SecretKey(_jwtSecret), expiresIn: const Duration(days: 30));
}

class AuthTokenPayload {
  AuthTokenPayload({required this.userId, required this.role, this.sessionId, this.issuedAt});
  final String userId;
  final String role;

  /// Null for tokens issued before device sessions existed.
  final String? sessionId;

  /// JWT `iat` (epoch seconds). Used to revoke tokens that have no [sessionId].
  final int? issuedAt;
}

/// Decodes an ACCESS token. Pending tokens (`pending_2fa`, `pending_wipe`)
/// and anything malformed return null (=> 401), never throw. Tokens issued
/// before the `type` claim existed have none and are still accepted.
AuthTokenPayload? verifyToken(String token) {
  try {
    final jwt = JWT.verify(token, SecretKey(_jwtSecret));
    final payload = jwt.payload as Map<String, dynamic>;
    final type = payload['type'];
    if (type != null && type != 'access') return null;
    final iat = payload['iat'];
    return AuthTokenPayload(
      userId: payload['sub'] as String,
      role: payload['role'] as String,
      sessionId: payload['sid'] as String?,
      issuedAt: iat is num ? iat.toInt() : null,
    );
  } catch (_) {
    // JWTException, or a claim with the wrong type: just "not a valid token".
    return null;
  }
}

/// A real bcrypt hash (same cost as real accounts) of a throwaway value. Login
/// and recovery check against it when the account does not exist, so a missing
/// account costs the same ~70ms as a wrong password and names cannot be probed
/// by timing. Computed once, lazily (top-level finals are lazy in Dart).
final String dummyPasswordHash = BCrypt.hashpw('xoso-dummy-${Random.secure().nextInt(1 << 30)}', BCrypt.gensalt());

/// True if every key in [keys] that is present and non-null in [body] is a
/// String. Routes call this first so `{"username": 5}` gets a 400, not a 500.
bool fieldsAreStrings(Map<String, dynamic> body, List<String> keys) =>
    keys.every((k) => body[k] == null || body[k] is String);

// ---------------------------------------------------------------------------
// One-time temporary tokens
// ---------------------------------------------------------------------------
//
// pending_2fa and pending_wipe tokens carry a random `jti`. The id of a token
// that has been spent is kept in a small in-memory map {jti -> expiry}; the
// map is purged of expired entries on every insert, so it can never hold more
// than the tokens spent in the last 5 minutes (an expired token no longer
// verifies, so forgetting it is safe). No table / migration needed.
// Trade-off: the map is per process, so a server restart inside the 5-minute
// window forgets spent ids (only matters if XOSO_JWT_SECRET is fixed; with a
// random per-process key every token dies on restart anyway).
final Map<String, int> _spentJti = {};

String _newJti() {
  final rng = Random.secure();
  return base64UrlEncode(List<int>.generate(18, (_) => rng.nextInt(256)));
}

/// Marks the token with this [jti] as used (until [expSeconds], epoch seconds).
/// Returns false if it was already used. Synchronous, so check-and-mark is
/// atomic within the single isolate.
bool _spend(String? jti, int expSeconds) {
  if (jti == null) return true; // issued before jti existed (at most 5 min old)
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  _spentJti.removeWhere((_, expMs) => expMs <= nowMs);
  if (_spentJti.containsKey(jti)) return false;
  _spentJti[jti] = expSeconds * 1000 + 1000;
  return true;
}

int _expOf(Map<String, dynamic> payload) {
  final exp = payload['exp'];
  return exp is num ? exp.toInt() : DateTime.now().millisecondsSinceEpoch ~/ 1000 + 300;
}

JWT? _verifyTyped(String token, String type) {
  try {
    final jwt = JWT.verify(token, SecretKey(_jwtSecret));
    final payload = jwt.payload as Map<String, dynamic>;
    if (payload['type'] != type || payload['sub'] is! String) return null;
    return jwt;
  } catch (_) {
    return null;
  }
}

/// Short-lived token proving the caller already passed the first login
/// step (username + primary password) for [userId], so `/api/auth/step2`
/// can trust it without asking for the primary password again.
String issuePendingSecondFactorToken(String userId) {
  final jwt = JWT({'sub': userId, 'type': 'pending_2fa'}, jwtId: _newJti());
  return jwt.sign(SecretKey(_jwtSecret), expiresIn: const Duration(minutes: 5));
}

/// Returns the user id if [token] is a valid, unexpired, not-yet-spent
/// pending-2FA token from [issuePendingSecondFactorToken]; null otherwise.
/// Does NOT spend it (a mistyped second password may be retried, bounded by
/// the login throttle) - call [spendPendingSecondFactorToken] on success.
String? verifyPendingSecondFactorToken(String token) {
  final jwt = _verifyTyped(token, 'pending_2fa');
  if (jwt == null) return null;
  final jti = jwt.jwtId;
  if (jti != null && _spentJti.containsKey(jti)) return null;
  return (jwt.payload as Map<String, dynamic>)['sub'] as String;
}

/// Spends a pending-2FA token so it cannot be used again. Returns false if it
/// was already spent (or is invalid).
bool spendPendingSecondFactorToken(String token) {
  final jwt = _verifyTyped(token, 'pending_2fa');
  if (jwt == null) return false;
  return _spend(jwt.jwtId, _expOf(jwt.payload as Map<String, dynamic>));
}

/// Short-lived token proving the login form's password field matched this
/// account's configured wipe-password. It authorizes ONLY
/// `/api/auth/confirm-wipe` - it is never a session/access token, so simply
/// holding it never logs anyone in or reveals any account data. The app is
/// required to show an explicit on-screen confirmation naming what will
/// happen before it ever sends this token back to confirm-wipe.
String issuePendingWipeToken(String userId) {
  final jwt = JWT({'sub': userId, 'type': 'pending_wipe'}, jwtId: _newJti());
  return jwt.sign(SecretKey(_jwtSecret), expiresIn: const Duration(minutes: 5));
}

/// Returns the user id if [token] is a valid, unexpired pending-wipe token
/// from [issuePendingWipeToken] AND spends it: the wipe token works exactly
/// once (confirm-wipe calls this a single time and then acts), so replaying
/// the same request cannot wipe again. null otherwise.
String? verifyPendingWipeToken(String token) {
  final jwt = _verifyTyped(token, 'pending_wipe');
  if (jwt == null) return null;
  final payload = jwt.payload as Map<String, dynamic>;
  if (!_spend(jwt.jwtId, _expOf(payload))) return null;
  return payload['sub'] as String;
}
