import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:sqlite3/sqlite3.dart';

/// Mã khôi phục (K07/K08/A06): a random one-time-shown code that lets a user
/// who forgot their password set a new one without an admin. Only a bcrypt
/// hash is stored (users.recovery_code_hash) so nobody - including admins and
/// anyone with a copy of the database - can read it back. Rotating = writing a
/// new hash, which invalidates the previous code.

/// Alphabet without look-alike characters (no 0/O, 1/I/L).
const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const _groups = 4;
const _groupLen = 4;

/// After this many wrong codes in a row the account is locked for [_lockFor].
const maxRecoveryAttempts = 5;
const _lockFor = Duration(minutes: 15);

/// New random code like `K7QF-9XMA-2PTD-HW4C` (~80 bits of entropy).
String generateRecoveryCode() {
  final rng = Random.secure();
  final parts = List.generate(
    _groups,
    (_) => String.fromCharCodes(
      List.generate(_groupLen, (_) => _alphabet.codeUnitAt(rng.nextInt(_alphabet.length))),
    ),
  );
  return parts.join('-');
}

/// Same code however the user typed it (case, dashes, spaces).
String normalizeRecoveryCode(String input) => input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

/// Generates a fresh code for [userId], stores only its hash (replacing -
/// and thereby invalidating - any previous code, and clearing the throttle),
/// and returns the plain code for one-time display to the caller.
String rotateRecoveryCode(Database db, String userId) {
  final code = generateRecoveryCode();
  db.execute(
    '''
    UPDATE users SET recovery_code_hash = ?, recovery_code_created_at = ?,
      recovery_failed_attempts = 0, recovery_locked_until = NULL
    WHERE id = ?
    ''',
    [
      BCrypt.hashpw(normalizeRecoveryCode(code), BCrypt.gensalt()),
      DateTime.now().toUtc().toIso8601String(),
      userId,
    ],
  );
  return code;
}

/// Minutes left on the throttle lock for [row], or 0 if not locked.
int recoveryLockMinutesLeft(Row row) {
  final until = row['recovery_locked_until'] as String?;
  if (until == null) return 0;
  final left = DateTime.parse(until).difference(DateTime.now().toUtc());
  return left.isNegative ? 0 : (left.inSeconds / 60).ceil();
}

/// Checks [code] against the stored hash, counting failures. Returns true on
/// success (counter reset). The caller must have checked the lock first.
bool checkRecoveryCode(Database db, Row row, String code) {
  final hash = row['recovery_code_hash'] as String?;
  final id = row['id'] as String;
  if (hash != null && BCrypt.checkpw(normalizeRecoveryCode(code), hash)) {
    db.execute('UPDATE users SET recovery_failed_attempts = 0, recovery_locked_until = NULL WHERE id = ?', [id]);
    return true;
  }
  final attempts = ((row['recovery_failed_attempts'] as int?) ?? 0) + 1;
  if (attempts >= maxRecoveryAttempts) {
    db.execute(
      'UPDATE users SET recovery_failed_attempts = 0, recovery_locked_until = ? WHERE id = ?',
      [DateTime.now().toUtc().add(_lockFor).toIso8601String(), id],
    );
  } else {
    db.execute('UPDATE users SET recovery_failed_attempts = ? WHERE id = ?', [attempts, id]);
  }
  return false;
}
