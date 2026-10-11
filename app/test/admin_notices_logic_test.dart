import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/admin/notices/notices_logic.dart';

void main() {
  test('notice validation mirrors the backend', () {
    expect(validateNotice('info', '   ', ''), isNotNull);
    expect(validateNotice('info', 'Xin chào', ''), isNull);
    expect(validateNotice('bogus', 'x', ''), 'Loại thông báo không hợp lệ');
    expect(validateNotice('info', 'a' * 201, ''), 'Thông báo quá dài');
    expect(validateNotice('info', 'a' * 200, 'b' * 2000), isNull);
    expect(validateNotice('info', 'a', 'b' * 2001), 'Thông báo quá dài');
  });

  test('maintenance message max 500', () {
    expect(validateMaintenanceMessage('a' * 500), isNull);
    expect(validateMaintenanceMessage('a' * 501), isNotNull);
  });

  test('sections follow the rights', () {
    expect(noticeSections(announce: true, maintenance: true, sentCount: 3).map((e) => e.$1), ['sent', 'compose', 'maintenance']);
    expect(noticeSections(announce: false, maintenance: true, sentCount: 0).map((e) => e.$1), ['maintenance']);
    expect(noticeSections(announce: true, maintenance: false, sentCount: 2).first.$2, 'Đã gửi (2)');
    expect(noticeSections(announce: false, maintenance: false, sentCount: 0), isEmpty);
  });

  test('announcement parsing/toggle', () {
    final a = Announcement.fromJson({'id': '1', 'kind': 'policy', 'title': 'T', 'body': null, 'active': true});
    expect(a.body, ''); // null body must not crash
    expect(a.copyWith(active: false).active, isFalse);
    expect(noticeKindLabel('maintenance'), 'Bảo trì');
    expect(noticeKindLabel('zzz'), 'zzz');
  });
}
