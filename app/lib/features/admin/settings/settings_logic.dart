import '../../../core/format.dart';

/// Pure logic of "Cài đặt" (SettingsView.vue, SecurityPolicyView.vue, BackupsView.vue and the matching backend validation).

class Bank {
  const Bank(this.bin, this.name);
  final String bin, name;
}

/// BIN codes per Napas / VietQR.
const vietQrBanks = <Bank>[
  Bank('970436', 'Vietcombank'),
  Bank('970415', 'VietinBank'),
  Bank('970418', 'BIDV'),
  Bank('970405', 'Agribank'),
  Bank('970422', 'MB Bank'),
  Bank('970407', 'Techcombank'),
  Bank('970416', 'ACB'),
  Bank('970432', 'VPBank'),
  Bank('970423', 'TPBank'),
  Bank('970403', 'Sacombank'),
  Bank('970437', 'HDBank'),
  Bank('970443', 'SHB'),
  Bank('970431', 'Eximbank'),
  Bank('970426', 'MSB'),
  Bank('970448', 'OCB'),
  Bank('970440', 'SeABank'),
  Bank('970441', 'VIB'),
  Bank('970449', 'LienVietPostBank (LPBank)'),
  Bank('970429', 'SCB'),
  Bank('970406', 'DongA Bank'),
];

String bankNameOf(String bin) {
  for (final b in vietQrBanks) {
    if (b.bin == bin) return b.name;
  }
  return '';
}

/// The "Thanh toán" form (value object so edit-mode can compare against the saved snapshot).
class BankForm {
  const BankForm({this.bin = '', this.account = '', this.holder = ''});
  final String bin, account, holder;

  factory BankForm.fromSettings(Map<String, dynamic> s) => BankForm(bin: '${s['bank_bin'] ?? ''}', account: '${s['bank_account_number'] ?? ''}', holder: '${s['bank_account_holder'] ?? ''}');

  BankForm copyWith({String? bin, String? account, String? holder}) => BankForm(bin: bin ?? this.bin, account: account ?? this.account, holder: holder ?? this.holder);

  /// null when it can be saved (same rule as the web: everything is required).
  String? validate() => bin.isEmpty || account.trim().isEmpty || holder.trim().isEmpty ? 'Vui lòng chọn ngân hàng và nhập đầy đủ số tài khoản, chủ tài khoản' : null;

  /// Body of `PUT /admin/settings`.
  Map<String, String> toBody() => {'bank_bin': bin, 'bank_name': bankNameOf(bin), 'bank_account_number': account.trim(), 'bank_account_holder': holder.trim()};

  @override
  bool operator ==(Object other) => other is BankForm && other.bin == bin && other.account == account && other.holder == holder;
  @override
  int get hashCode => Object.hash(bin, account, holder);
}

const kMaxVirtualIdsMin = 1;
const kMaxVirtualIdsMax = 100;

/// Giới hạn ID: empty means the default 5. Returns the error message or null.
String? validateMaxIds(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final n = int.tryParse(t);
  if (n == null || n < kMaxVirtualIdsMin || n > kMaxVirtualIdsMax) return 'Giới hạn ID ảo phải là số nguyên từ 1 đến 100';
  return null;
}

String maxIdsBody(String raw) => raw.trim().isEmpty ? '5' : raw.trim();

// ---- package catalog ----

class PackageItem {
  const PackageItem({required this.type, required this.label, required this.durationDays, required this.priceVnd, required this.active, this.users = 0, this.requests = 0, this.transactions = 0});
  final String type, label;
  final int durationDays, priceVnd, users, requests, transactions;
  final bool active;

  bool get inUse => users + requests + transactions > 0;

  factory PackageItem.fromJson(Map<String, dynamic> j) {
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final u = j['usage'] is Map ? j['usage'] as Map : const {};
    return PackageItem(
      type: '${j['type'] ?? j['code'] ?? ''}',
      label: '${j['label'] ?? ''}',
      durationDays: i(j['durationDays']),
      priceVnd: i(j['priceVnd']),
      active: j['active'] != false,
      users: i(u['users']),
      requests: i(u['requests']),
      transactions: i(u['transactions']),
    );
  }
}

/// Validates the package form like the backend `parsePackageFields`; returns the JSON body or sets [error].
({Map<String, dynamic>? body, String? error}) parsePackageForm(String label, String days, String price) {
  final l = label.trim();
  if (l.isEmpty || l.length > 60) return (body: null, error: 'Tên gói phải từ 1 đến 60 ký tự');
  final d = int.tryParse(days.trim());
  if (d == null || d < 1 || d > 3650) return (body: null, error: 'Thời hạn phải từ 1 đến 3650 ngày');
  final p = int.tryParse(price.trim());
  if (p == null || p < 0 || p > 1000000000) return (body: null, error: 'Giá không hợp lệ');
  return (body: {'label': l, 'durationDays': d, 'priceVnd': p}, error: null);
}

String formatDuration(int d) {
  if (d > 0 && d % 365 == 0) return '$d ngày (${d ~/ 365} năm)';
  if (d > 0 && d % 30 == 0) return '$d ngày (${d ~/ 30} tháng)';
  return '$d ngày';
}

String formatVndPlain(num v) => '${formatNumber(v)} đ';

// ---- security policy ----

class PolicyRange {
  const PolicyRange(this.min, this.max, this.label);
  final int min, max;
  final String label;
}

const policyRanges = <String, PolicyRange>{
  'loginFreeAttempts': PolicyRange(3, 20, 'Số lần nhập sai được phép'),
  'loginBaseLockSeconds': PolicyRange(5, 3600, 'Thời gian khoá lần đầu (giây)'),
  'loginMaxLockSeconds': PolicyRange(30, 86400, 'Thời gian khoá tối đa (giây)'),
  'tokenDays': PolicyRange(1, 365, 'Thời hạn đăng nhập (ngày)'),
  'autoLockMinutes': PolicyRange(0, 240, 'Tự khoá màn hình mặc định (phút)'),
};

class SecurityPolicyForm {
  const SecurityPolicyForm({
    this.loginFreeAttempts = 5,
    this.loginBaseLockSeconds = 30,
    this.loginMaxLockSeconds = 900,
    this.tokenDays = 30,
    this.autoLockMinutes = 0,
    this.watermarkEnabled = false,
    this.screenshotGuardEnabled = true,
    this.blurOnHideEnabled = false,
  });

  final int loginFreeAttempts, loginBaseLockSeconds, loginMaxLockSeconds, tokenDays, autoLockMinutes;
  final bool watermarkEnabled, screenshotGuardEnabled, blurOnHideEnabled;

  factory SecurityPolicyForm.fromJson(Map<String, dynamic> j) {
    const d = SecurityPolicyForm();
    int i(String k, int def) => j[k] is num ? (j[k] as num).toInt() : def;
    bool b(String k, bool def) => j[k] is bool ? j[k] as bool : def;
    return SecurityPolicyForm(
      loginFreeAttempts: i('loginFreeAttempts', d.loginFreeAttempts),
      loginBaseLockSeconds: i('loginBaseLockSeconds', d.loginBaseLockSeconds),
      loginMaxLockSeconds: i('loginMaxLockSeconds', d.loginMaxLockSeconds),
      tokenDays: i('tokenDays', d.tokenDays),
      autoLockMinutes: i('autoLockMinutes', d.autoLockMinutes),
      watermarkEnabled: b('watermarkEnabled', d.watermarkEnabled),
      screenshotGuardEnabled: b('screenshotGuardEnabled', d.screenshotGuardEnabled),
      blurOnHideEnabled: b('blurOnHideEnabled', d.blurOnHideEnabled),
    );
  }

  Map<String, Object> toJson() => {
    'loginFreeAttempts': loginFreeAttempts,
    'loginBaseLockSeconds': loginBaseLockSeconds,
    'loginMaxLockSeconds': loginMaxLockSeconds,
    'tokenDays': tokenDays,
    'autoLockMinutes': autoLockMinutes,
    'watermarkEnabled': watermarkEnabled,
    'screenshotGuardEnabled': screenshotGuardEnabled,
    'blurOnHideEnabled': blurOnHideEnabled,
  };

  int numeric(String key) => (toJson()[key]! as int);

  /// [key] numeric field set to [v] (the others unchanged).
  SecurityPolicyForm withNumber(String key, int v) => SecurityPolicyForm(
    loginFreeAttempts: key == 'loginFreeAttempts' ? v : loginFreeAttempts,
    loginBaseLockSeconds: key == 'loginBaseLockSeconds' ? v : loginBaseLockSeconds,
    loginMaxLockSeconds: key == 'loginMaxLockSeconds' ? v : loginMaxLockSeconds,
    tokenDays: key == 'tokenDays' ? v : tokenDays,
    autoLockMinutes: key == 'autoLockMinutes' ? v : autoLockMinutes,
    watermarkEnabled: watermarkEnabled,
    screenshotGuardEnabled: screenshotGuardEnabled,
    blurOnHideEnabled: blurOnHideEnabled,
  );

  SecurityPolicyForm withFlags({bool? watermark, bool? screenshotGuard, bool? blurOnHide}) => SecurityPolicyForm(
    loginFreeAttempts: loginFreeAttempts,
    loginBaseLockSeconds: loginBaseLockSeconds,
    loginMaxLockSeconds: loginMaxLockSeconds,
    tokenDays: tokenDays,
    autoLockMinutes: autoLockMinutes,
    watermarkEnabled: watermark ?? watermarkEnabled,
    screenshotGuardEnabled: screenshotGuard ?? screenshotGuardEnabled,
    blurOnHideEnabled: blurOnHide ?? blurOnHideEnabled,
  );

  /// Error message in the backend's words (validatePolicyInput), or null.
  String? validate() {
    final j = toJson();
    for (final e in policyRanges.entries) {
      final v = j[e.key]! as int;
      if (v < e.value.min || v > e.value.max) return '${e.value.label} phải là số nguyên từ ${e.value.min} đến ${e.value.max}';
    }
    if (loginMaxLockSeconds < loginBaseLockSeconds) return 'Thời gian khoá tối đa không được nhỏ hơn thời gian khoá lần đầu';
    return null;
  }

  /// "30 giây → 1 phút → ..." the first four consecutive locks.
  String get lockExample {
    String mins(int s) => s % 60 == 0 && s >= 60 ? '${s ~/ 60} phút' : '$s giây';
    final out = <String>[];
    var s = loginBaseLockSeconds;
    for (var i = 0; i < 4; i++) {
      out.add(mins(s < loginMaxLockSeconds ? s : loginMaxLockSeconds));
      s *= 2;
    }
    return out.join(' → ');
  }

  @override
  bool operator ==(Object other) => other is SecurityPolicyForm && other.toJson().toString() == toJson().toString();
  @override
  int get hashCode => toJson().toString().hashCode;
}

// ---- security log / backups ----

const securityEventLabels = {
  'login_failed': 'Đăng nhập sai',
  'login_locked': 'Khoá tạm đăng nhập',
  'session_revoked': 'Thu hồi phiên',
  'data_wiped': 'Xoá dữ liệu',
  'security_policy_changed': 'Đổi chính sách bảo mật',
  'security_policy_reset': 'Đặt lại chính sách bảo mật',
};

String formatBackupSize(num bytes) => bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB' : '${(bytes / 1024).round().clamp(1, 1 << 40)} KB';

class SettingsSection {
  const SettingsSection(this.key, this.label);
  final String key, label;
}

/// Pills the account may see (same order and rules as the web TABS).
List<SettingsSection> settingsSections({required bool settings, required bool security, required bool policy, required bool backups, required bool hasOtherKeys}) => [
  if (settings) const SettingsSection('payment', 'Thanh toán'),
  if (settings) const SettingsSection('prices', 'Giá gói'),
  if (settings) const SettingsSection('limits', 'Giới hạn ID'),
  if (settings) const SettingsSection('appversion', 'Phiên bản ứng dụng'),
  if (security) const SettingsSection('security', 'Nhật ký bảo mật'),
  if (policy) const SettingsSection('policy', 'Chính sách bảo mật'),
  if (backups) const SettingsSection('backups', 'Sao lưu'),
  if (settings && hasOtherKeys) const SettingsSection('other', 'Khoá khác'),
];

const _bankKeys = {'bank_name', 'bank_bin', 'bank_account_number', 'bank_account_holder', 'max_virtual_ids'};
const _internalKeys = {'unread_epoch', 'e2ee_friend_chat_purged', 'perm_split_maintenance'};

/// Keys of the generic store not covered by a dedicated form.
List<String> otherSettingKeys(Map<String, dynamic> raw) => [
  for (final k in raw.keys)
    if (!k.startsWith('package_price_') && !k.startsWith('app_') && !_bankKeys.contains(k) && !_internalKeys.contains(k)) k,
];
