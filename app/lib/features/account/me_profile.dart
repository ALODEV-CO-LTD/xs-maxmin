/// `GET /me` (backend meJson).
class MeProfile {
  const MeProfile({
    required this.name,
    required this.username,
    this.role = 'user',
    this.hasSecondPassword = false,
    this.hasWipePassword = false,
    this.hasRecoveryCode = false,
    this.packageType,
    this.packageLabel,
    this.packageExpiresAt,
    this.packageActive = false,
    this.quotaTotal = 0,
    this.quotaUsed = 0,
  });

  final String name, username, role;
  final bool hasSecondPassword, hasWipePassword, hasRecoveryCode;
  final String? packageType, packageLabel, packageExpiresAt;
  final bool packageActive;
  final int quotaTotal, quotaUsed;

  bool get isAdmin => role == 'admin';
  bool get unlimited => quotaTotal >= 999999999;

  factory MeProfile.fromJson(Map<String, dynamic> j) {
    final pkg = j['package'] is Map ? j['package'] as Map : const {};
    final st = j['stats'] is Map ? j['stats'] as Map : const {};
    int n(Object? v) => v is num ? v.toInt() : 0;
    return MeProfile(
      name: (j['name'] ?? '') as String,
      username: (j['username'] ?? '') as String,
      role: (j['role'] ?? 'user') as String,
      hasSecondPassword: j['hasSecondPassword'] == true,
      hasWipePassword: j['hasWipePassword'] == true,
      hasRecoveryCode: j['hasRecoveryCode'] == true,
      packageType: pkg['type'] as String?,
      packageLabel: pkg['label'] as String?,
      packageExpiresAt: pkg['expiresAt'] as String?,
      packageActive: pkg['isActive'] == true,
      quotaTotal: n(st['total']),
      quotaUsed: n(st['used']),
    );
  }
}

/// "2026-10-11T03:04:05.000Z" -> "11/10/2026" (local time), "-" when empty.
String viDateTimeLocal(String? iso, {bool withTime = false}) {
  if (iso == null || iso.isEmpty) return '-';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  String p(int v) => v.toString().padLeft(2, '0');
  final date = '${p(d.day)}/${p(d.month)}/${d.year}';
  return withTime ? '${p(d.hour)}:${p(d.minute)} $date' : date;
}
