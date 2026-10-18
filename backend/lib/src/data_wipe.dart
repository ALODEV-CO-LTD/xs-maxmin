import 'package:sqlite3/sqlite3.dart';

/// The ONE definition of what "Xoá toàn bộ dữ liệu" deletes. Shared by
/// `POST /api/me/delete-data` (logged in) and `POST /api/auth/confirm-wipe`
/// (emergency wipe via the wipe-password) so the two can never drift apart.
///
/// Deleted (only rows belonging to [userId]):
///  - data_entries               số liệu đã nhập
///  - customers                  danh sách khách hàng
///  - customer_syntax_templates  mẫu cú pháp
///  - deletion_schedules         lịch xoá tự động
///  - call_logs                  nhật ký cuộc gọi (người này gọi hoặc nhận)
///  - direct_messages với Admin  tin nhắn phản hồi với Admin (cả hai chiều, kể cả
///                               tệp đính kèm nằm trong dòng đó) + dấu đã đọc
///  - messages (bảng cũ)         tin nhắn cũ phản hồi với Admin
///  - transactions               lịch sử giao dịch
///  - payment_requests 'pending' yêu cầu thanh toán chưa duyệt
///  - friend_requests            lời mời kết bạn (cả hai chiều, mọi trạng thái)
///
/// Kept on purpose: the account itself, package/quota, friendships, friend
/// chat (`direct_messages` between two non-admin users belongs to both people), customer codes (Mã ID),
/// scoring configuration, approved/rejected payment requests (accounting
/// trail for Admin) and the security log.
///
/// Runs in a single transaction: everything is deleted or nothing is.
/// Returns the number of rows removed per table.
Map<String, int> wipeUserData(Database db, String userId) {
  final counts = <String, int>{};
  void del(String key, String sql, [List<Object?>? params]) {
    db.execute(sql, params ?? [userId]);
    counts[key] = db.updatedRows;
  }

  db.execute('BEGIN IMMEDIATE');
  try {
    del('data_entries', 'DELETE FROM data_entries WHERE user_id = ?');
    del('lottery_results', 'DELETE FROM lottery_results WHERE user_id = ?');
    del('customers', 'DELETE FROM customers WHERE user_id = ?');
    del('customer_syntax_templates', 'DELETE FROM customer_syntax_templates WHERE user_id = ?');
    del('deletion_schedules', 'DELETE FROM deletion_schedules WHERE user_id = ?');
    del('call_logs', 'DELETE FROM call_logs WHERE caller_id = ? OR callee_id = ?', [userId, userId]);
    del('messages', 'DELETE FROM messages WHERE user_id = ?');
    // Phản hồi thật nằm ở direct_messages (người dùng <-> tài khoản Admin).
    // Chỉ xoá cặp có một đầu là role='admin'; chat bạn bè giữ nguyên.
    del(
      'support_messages',
      '''
      DELETE FROM direct_messages
      WHERE (from_user_id = ? AND to_user_id IN (SELECT id FROM users WHERE role = 'admin'))
         OR (to_user_id = ? AND from_user_id IN (SELECT id FROM users WHERE role = 'admin'))
      ''',
      [userId, userId],
    );
    db.execute("DELETE FROM message_reads WHERE user_id = ? AND peer_key = 'support'", [userId]);
    del('transactions', 'DELETE FROM transactions WHERE user_id = ?');
    del('payment_requests', "DELETE FROM payment_requests WHERE user_id = ? AND status = 'pending'");
    del('friend_requests', 'DELETE FROM friend_requests WHERE from_user_id = ? OR to_user_id = ?', [userId, userId]);
    db.execute('UPDATE users SET data_used = 0 WHERE id = ?', [userId]);
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
  return counts;
}
