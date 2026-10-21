import 'package:server/src/call_signaling.dart';
import 'package:server/src/push_notify.dart';
import 'package:sqlite3/sqlite3.dart';

/// Status as the API reports it: a withdrawn request is 'cancelled' (stored as
/// 'rejected' + cancelled = 1, see database.dart).
String paymentStatus(Row r) {
  final status = r['status'] as String;
  if (status == 'rejected' && (r['cancelled'] as int? ?? 0) == 1) return 'cancelled';
  return status;
}

/// One request as JSON (shared by the user's and the admin's lists).
Map<String, Object?> paymentJson(Row r, {bool withUser = false}) => {
      'id': r['id'],
      if (withUser) 'userName': r['user_name'],
      if (withUser) 'username': r['username'],
      'packageType': r['package_type'],
      'amount': r['amount'],
      'status': paymentStatus(r),
      'referenceCode': r['reference_code'],
      'rejectReason': r['reject_reason'],
      'createdAt': r['created_at'],
      'decidedAt': r['decided_at'],
    };

/// Tells the user's open app that Admin decided their payment request
/// (best effort - an offline user sees the new status next time they open
/// "Gói dịch vụ & Thanh toán").
void pushPaymentDecision(String userId, {required String status, String? reason, required String reference}) {
  // every open connection (a phone and a tablet), not only the newest; nobody connected -> a push wakes the phone
  final delivered = CallSignalingRegistry.instance.sendToAll(userId, {
    'type': 'payment-decided',
    'status': status,
    'referenceCode': reference,
    'reason': reason,
  });
  if (!delivered) notifyPaymentDecision(userId, approved: status == 'approved');
}
