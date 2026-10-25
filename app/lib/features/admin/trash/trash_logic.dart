import '../../../core/widgets/svg_icon.dart';

/// Thùng rác 7 ngày của Admin (GET /admin/trash): what the Admin deleted, kept for 7 days. Only counts, never the content.
class TrashItem {
  const TrashItem({required this.id, required this.kind, required this.label, required this.counts, required this.deletedAt, required this.daysLeft, this.deletedByName});
  final String id, kind, label;
  final Map<String, int> counts;
  final String? deletedAt, deletedByName;
  final int daysLeft;

  factory TrashItem.fromJson(Map<String, dynamic> j) => TrashItem(
        id: '${j['id']}',
        kind: '${j['kind']}',
        label: '${j['label'] ?? ''}',
        counts: {for (final e in ((j['counts'] as Map?) ?? const {}).entries) '${e.key}': e.value is num ? (e.value as num).toInt() : 0},
        deletedAt: j['deletedAt'] as String?,
        daysLeft: j['daysLeft'] is num ? (j['daysLeft'] as num).toInt() : 0,
        deletedByName: j['deletedByName'] as String?,
      );

  AppSvg get icon => switch (kind) {
        'user' => AppSvg.usersGroup,
        'staff' => AppSvg.userAdmin,
        'announcement' => AppSvg.megaphone,
        'package' => AppSvg.pay,
        _ => AppSvg.gear,
      };

  String get kindLabel => trashKindLabel(kind);

  /// "Còn 3 ngày" / "Còn dưới 1 ngày".
  String get timeLeft => daysLeft <= 1 ? 'Còn dưới 1 ngày' : 'Còn $daysLeft ngày';
}

String trashKindLabel(String kind) => const {
      'user': 'Tài khoản khách hàng',
      'staff': 'Tài khoản nhân viên',
      'announcement': 'Thông báo',
      'package': 'Gói dịch vụ',
      'setting': 'Cài đặt',
    }[kind] ??
    kind;

const _countNames = {
  'customers': 'khách hàng',
  'data_entries': 'số liệu',
  'lottery_results': 'kết quả xổ số',
  'customer_syntax_templates': 'mẫu cú pháp',
  'deletion_schedules': 'lịch xoá',
  'transactions': 'giao dịch',
  'payment_requests': 'yêu cầu thanh toán',
  'messages': 'tin nhắn hỗ trợ',
  'direct_messages': 'tin phản hồi',
  'friendships': 'bạn bè',
  'friend_requests': 'lời mời kết bạn',
  'customer_codes': 'mã ID',
  'retired_codes': 'mã ID cũ',
  'message_reads': 'dấu đã đọc',
  'e2ee_devices': 'thiết bị nhắn tin',
  'recovery_requests': 'yêu cầu khôi phục',
  'call_logs': 'cuộc gọi',
  'announcements': 'thông báo',
  'packages': 'gói',
  'settings': 'mục cài đặt',
};

/// "2 khách hàng · 19 số liệu · 85 kết quả xổ số" in a fixed order; tables the app does not know show their own name.
String countsSummary(Map<String, int> counts) {
  if (counts.isEmpty) return '';
  final known = [for (final k in _countNames.keys) if ((counts[k] ?? 0) > 0) '${counts[k]} ${_countNames[k]}'];
  final others = [for (final e in counts.entries) if (!_countNames.containsKey(e.key) && e.value > 0) '${e.value} ${e.key}'];
  return [...known, ...others].join(' · ');
}
