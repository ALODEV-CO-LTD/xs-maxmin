class StaffAccount {
  const StaffAccount({required this.id, required this.name, required this.username, required this.permissions, required this.locked, required this.createdAt});
  final String id, name, username;
  final List<String> permissions;
  final bool locked;
  final String? createdAt;

  factory StaffAccount.fromJson(Map<String, dynamic> j) => StaffAccount(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        username: '${j['username'] ?? ''}',
        permissions: [for (final p in (j['permissions'] as List? ?? const [])) '$p'],
        locked: j['locked'] == true,
        createdAt: j['createdAt'] as String?,
      );
}

class StaffData {
  const StaffData(this.catalog, this.staff);
  final Map<String, String> catalog; // permission key -> Vietnamese description
  final List<StaffAccount> staff;

  factory StaffData.fromJson(Map<String, dynamic> j) => StaffData(
        {for (final e in ((j['permissions'] as Map?) ?? const {}).entries) '${e.key}': '${e.value}'},
        [for (final s in (j['staff'] as List? ?? const [])) StaffAccount.fromJson((s as Map).cast<String, dynamic>())],
      );
}

class StaffPreset {
  const StaffPreset(this.label, this.keys);
  final String label;
  final List<String> keys;
}

/// Starting points that only tick boxes (same as StaffView.vue).
const staffPresets = [
  StaffPreset('Chăm sóc khách hàng', ['users.view', 'users.recovery', 'support.messages']),
  StaffPreset('Quản lý hệ thống', ['users.view', 'stats.view', 'announcements.manage', 'maintenance.manage', 'settings.manage', 'backups.manage', 'security.view']),
];

bool samePermissions(List<String> a, List<String> b) => a.length == b.length && a.every(b.contains);

/// Client-side check mirroring POST /admin/staff; returns a Vietnamese message or null when it may be sent.
String? validateNewStaff({required String name, required String username, required String password, required List<String> permissions}) {
  if (name.trim().isEmpty) return 'Vui lòng nhập tên hiển thị';
  if (username.trim().length < 3) return 'Tên đăng nhập phải có ít nhất 3 ký tự';
  if (password.length < 8) return 'Mật khẩu phải có ít nhất 8 ký tự';
  if (permissions.isEmpty) return 'Hãy chọn ít nhất một quyền cho tài khoản này';
  return null;
}
