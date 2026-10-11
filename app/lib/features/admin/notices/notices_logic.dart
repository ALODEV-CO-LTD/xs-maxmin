// Pure logic of "Thông báo & bảo trì" (frontend/src/views/admin/NoticesView.vue).

const noticeKinds = <(String, String)>[('maintenance', 'Bảo trì'), ('policy', 'Đổi chính sách'), ('info', 'Thông báo chung')];

String noticeKindLabel(String k) {
  for (final x in noticeKinds) {
    if (x.$1 == k) return x.$2;
  }
  return k;
}

const kNoticeTitleMax = 200;
const kNoticeBodyMax = 2000;
const kMaintenanceMessageMax = 500;

class Announcement {
  const Announcement({required this.id, required this.kind, required this.title, required this.body, required this.active, this.createdAt});
  final String id, kind, title, body;
  final bool active;
  final String? createdAt;

  Announcement copyWith({bool? active}) => Announcement(id: id, kind: kind, title: title, body: body, active: active ?? this.active, createdAt: createdAt);

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
    id: '${j['id'] ?? ''}',
    kind: '${j['kind'] ?? 'info'}',
    title: '${j['title'] ?? ''}',
    body: '${j['body'] ?? ''}',
    active: j['active'] != false,
    createdAt: j['createdAt'] as String?,
  );
}

/// Returns an error message for a new notice, or null when it can be sent (same limits as the backend).
String? validateNotice(String kind, String title, String body) {
  final t = title.trim();
  if (t.isEmpty) return 'Vui lòng nhập tiêu đề thông báo';
  if (t.length > kNoticeTitleMax || body.trim().length > kNoticeBodyMax) return 'Thông báo quá dài';
  if (!noticeKinds.any((k) => k.$1 == kind)) return 'Loại thông báo không hợp lệ';
  return null;
}

String? validateMaintenanceMessage(String message) => message.trim().length > kMaintenanceMessageMax ? 'Nội dung tối đa $kMaintenanceMessageMax ký tự' : null;

/// Pill sections the account may use: announcements.manage -> sent + compose, maintenance.manage -> maintenance.
List<(String, String)> noticeSections({required bool announce, required bool maintenance, required int sentCount}) => [
  if (announce) ('sent', 'Đã gửi ($sentCount)'),
  if (announce) ('compose', 'Gửi thông báo'),
  if (maintenance) ('maintenance', 'Chế độ bảo trì'),
];
