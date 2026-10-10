import 'package:bcrypt/bcrypt.dart';
import 'package:server/src/recovery_codes.dart';
import 'package:sqlite3/sqlite3.dart';

/// Controlled account recovery (A06). See the `recovery_requests` table in
/// database.dart for the flow. The ticket reuses the recovery-code format
/// (`K7QF-9XMA-2PTD-HW4C`, ~80 bits) and is stored only as a bcrypt hash.

/// How long an approved ticket can be used.
const recoveryTicketTtl = Duration(hours: 24);

/// Requests one IP may file per hour (any username).
const maxRecoveryRequestsPerIpPerHour = 5;

/// Marks approved tickets past their expiry as 'expired'.
void expireRecoveryTickets(Database db) {
  db.execute(
    "UPDATE recovery_requests SET status = 'expired' WHERE status = 'approved' AND ticket_expires_at < ?",
    [DateTime.now().toUtc().toIso8601String()],
  );
}

/// Issues a fresh ticket for [requestId] (replacing any previous one) and
/// returns `(plainTicket, expiresAt)`; the plain value is for one-time display.
(String, DateTime) issueRecoveryTicket(Database db, String requestId, String adminId) {
  final ticket = generateRecoveryCode();
  final now = DateTime.now().toUtc();
  final expires = now.add(recoveryTicketTtl);
  db.execute(
    '''
    UPDATE recovery_requests SET status = 'approved', handled_by = ?, handled_at = ?,
      ticket_hash = ?, ticket_expires_at = ? WHERE id = ?
    ''',
    [adminId, now.toIso8601String(), BCrypt.hashpw(normalizeRecoveryCode(ticket), BCrypt.gensalt()), expires.toIso8601String(), requestId],
  );
  return (ticket, expires);
}
