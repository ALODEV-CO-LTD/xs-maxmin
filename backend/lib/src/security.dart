import 'dart:convert';
import 'dart:io';
import 'dart:math';

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

String issueToken({required String userId, required String role}) {
  final jwt = JWT({'sub': userId, 'role': role});
  return jwt.sign(SecretKey(_jwtSecret), expiresIn: const Duration(days: 30));
}

class AuthTokenPayload {
  AuthTokenPayload({required this.userId, required this.role});
  final String userId;
  final String role;
}

AuthTokenPayload? verifyToken(String token) {
  try {
    final jwt = JWT.verify(token, SecretKey(_jwtSecret));
    final payload = jwt.payload as Map<String, dynamic>;
    return AuthTokenPayload(
      userId: payload['sub'] as String,
      role: payload['role'] as String,
    );
  } on JWTException {
    return null;
  }
}

/// Short-lived token proving the caller already passed the first login
/// step (username + primary password) for [userId], so `/api/auth/step2`
/// can trust it without asking for the primary password again.
String issuePendingSecondFactorToken(String userId) {
  final jwt = JWT({'sub': userId, 'type': 'pending_2fa'});
  return jwt.sign(SecretKey(_jwtSecret), expiresIn: const Duration(minutes: 5));
}

/// Returns the user id if [token] is a valid, unexpired pending-2FA token
/// from [issuePendingSecondFactorToken]; null otherwise.
String? verifyPendingSecondFactorToken(String token) {
  try {
    final jwt = JWT.verify(token, SecretKey(_jwtSecret));
    final payload = jwt.payload as Map<String, dynamic>;
    if (payload['type'] != 'pending_2fa') return null;
    return payload['sub'] as String;
  } on JWTException {
    return null;
  }
}

/// Short-lived token proving the login form's password field matched this
/// account's configured wipe-password. It authorizes ONLY
/// `/api/auth/confirm-wipe` - it is never a session/access token, so simply
/// holding it never logs anyone in or reveals any account data. The app is
/// required to show an explicit on-screen confirmation naming what will
/// happen before it ever sends this token back to confirm-wipe.
String issuePendingWipeToken(String userId) {
  final jwt = JWT({'sub': userId, 'type': 'pending_wipe'});
  return jwt.sign(SecretKey(_jwtSecret), expiresIn: const Duration(minutes: 5));
}

/// Returns the user id if [token] is a valid, unexpired pending-wipe token
/// from [issuePendingWipeToken]; null otherwise.
String? verifyPendingWipeToken(String token) {
  try {
    final jwt = JWT.verify(token, SecretKey(_jwtSecret));
    final payload = jwt.payload as Map<String, dynamic>;
    if (payload['type'] != 'pending_wipe') return null;
    return payload['sub'] as String;
  } on JWTException {
    return null;
  }
}
