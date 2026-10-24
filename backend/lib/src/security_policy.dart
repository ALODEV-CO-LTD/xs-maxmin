import 'package:sqlite3/sqlite3.dart';

/// Admin-configurable security policy (A09). Stored in the `settings` table
/// under `policy.*` keys; anything not set falls back to the defaults below,
/// which equal the values that used to be hard-coded.
///
///  - loginFreeAttempts / loginBaseLockSeconds / loginMaxLockSeconds: the
///    wrong-password throttle (login, second password, re-auth prompts): free
///    tries, first lock, and the lock ceiling (the lock doubles each time).
///  - tokenDays: how long a login lasts before the person must sign in again.
///  - autoLockMinutes: default idle auto-lock for accounts that never chose
///    their own (0 = off); each person can still pick a value in Tài khoản.
///  - hideLockSeconds: default "lock when the app was in the background / tab hidden for this long" for accounts that
///    never chose their own (0 = off); each person can still pick a value in Tài khoản.
///  - screenshotGuardEnabled: cover the screen when a desktop screenshot shortcut
///    (Cmd+Shift+3/4/5, Win+Shift+S) is held (frontend/src/screenshotGuard.js).
///  - watermarkEnabled: faint viewer name/time overlay on every screen so a
///    leaked screenshot can be traced (the web cannot block screenshots). OFF by default;
///    the Admin turns it on in Chính sách bảo mật.
///  - blurOnHideEnabled: blur the whole screen while the page is hidden / unfocused
///    (frontend/src/stores/privacy.js). OFF by default; the Admin turns it on.
class SecurityPolicy {
  const SecurityPolicy({
    this.loginFreeAttempts = 5,
    this.loginBaseLockSeconds = 30,
    this.loginMaxLockSeconds = 15 * 60,
    this.tokenDays = 30,
    this.autoLockMinutes = 0,
    this.hideLockSeconds = 0,
    this.watermarkEnabled = false,
    this.screenshotGuardEnabled = true,
    this.blurOnHideEnabled = false,
  });

  final int loginFreeAttempts;
  final int loginBaseLockSeconds;
  final int loginMaxLockSeconds;
  final int tokenDays;
  final int autoLockMinutes;
  final int hideLockSeconds;
  final bool watermarkEnabled;
  final bool screenshotGuardEnabled;
  final bool blurOnHideEnabled;

  Map<String, Object> toJson() => {
        'loginFreeAttempts': loginFreeAttempts,
        'loginBaseLockSeconds': loginBaseLockSeconds,
        'loginMaxLockSeconds': loginMaxLockSeconds,
        'tokenDays': tokenDays,
        'autoLockMinutes': autoLockMinutes,
        'hideLockSeconds': hideLockSeconds,
        'watermarkEnabled': watermarkEnabled,
        'screenshotGuardEnabled': screenshotGuardEnabled,
        'blurOnHideEnabled': blurOnHideEnabled,
      };
}

const _prefix = 'policy.';

/// Allowed range per numeric field (inclusive), with the Vietnamese label used in errors.
const _ranges = <String, (int, int, String)>{
  'loginFreeAttempts': (3, 20, 'Số lần nhập sai được phép'),
  'loginBaseLockSeconds': (5, 3600, 'Thời gian khoá lần đầu (giây)'),
  'loginMaxLockSeconds': (30, 86400, 'Thời gian khoá tối đa (giây)'),
  'tokenDays': (1, 365, 'Thời hạn đăng nhập (ngày)'),
  'autoLockMinutes': (0, 240, 'Tự khoá màn hình mặc định (phút)'),
  'hideLockSeconds': (0, 3600, 'Khoá khi thoát ra / chuyển ứng dụng mặc định (giây)'),
};

SecurityPolicy loadPolicy(Database db) {
  final stored = <String, String>{
    for (final r in db.select("SELECT key, value FROM settings WHERE key LIKE 'policy.%'")) (r['key'] as String).substring(_prefix.length): r['value'] as String,
  };
  int num(String k, int d) {
    final n = int.tryParse(stored[k] ?? '');
    final r = _ranges[k]!;
    return n == null || n < r.$1 || n > r.$2 ? d : n;
  }

  const d = SecurityPolicy();
  final base = num('loginBaseLockSeconds', d.loginBaseLockSeconds);
  final max = num('loginMaxLockSeconds', d.loginMaxLockSeconds);
  return SecurityPolicy(
    loginFreeAttempts: num('loginFreeAttempts', d.loginFreeAttempts),
    loginBaseLockSeconds: base,
    loginMaxLockSeconds: max < base ? base : max,
    tokenDays: num('tokenDays', d.tokenDays),
    autoLockMinutes: num('autoLockMinutes', d.autoLockMinutes),
    hideLockSeconds: num('hideLockSeconds', d.hideLockSeconds),
    watermarkEnabled: stored['watermarkEnabled'] == null ? d.watermarkEnabled : stored['watermarkEnabled'] == 'true',
    screenshotGuardEnabled: stored['screenshotGuardEnabled'] == null ? d.screenshotGuardEnabled : stored['screenshotGuardEnabled'] == 'true',
    blurOnHideEnabled: stored['blurOnHideEnabled'] == null ? d.blurOnHideEnabled : stored['blurOnHideEnabled'] == 'true',
  );
}

/// Validates a submitted policy (any subset of fields); returns an error message or null.
String? validatePolicyInput(Map<String, dynamic> body) {
  for (final e in _ranges.entries) {
    if (!body.containsKey(e.key)) continue;
    final v = body[e.key];
    if (v is! int || v < e.value.$1 || v > e.value.$2) {
      return '${e.value.$3} phải là số nguyên từ ${e.value.$1} đến ${e.value.$2}';
    }
  }
  if (body.containsKey('watermarkEnabled') && body['watermarkEnabled'] is! bool) {
    return 'Đóng dấu tên người xem phải là bật hoặc tắt';
  }
  if (body.containsKey('screenshotGuardEnabled') && body['screenshotGuardEnabled'] is! bool) {
    return 'Che màn hình khi chụp phải là bật hoặc tắt';
  }
  if (body.containsKey('blurOnHideEnabled') && body['blurOnHideEnabled'] is! bool) {
    return 'Làm mờ màn hình khi ẩn trang phải là bật hoặc tắt';
  }
  final base = body['loginBaseLockSeconds'];
  final max = body['loginMaxLockSeconds'];
  if (base is int && max is int && max < base) {
    return 'Thời gian khoá tối đa không được nhỏ hơn thời gian khoá lần đầu';
  }
  return null;
}

/// Writes the given fields; the rest keep their current/default value.
void savePolicy(Database db, Map<String, dynamic> body) {
  for (final k in [..._ranges.keys, 'watermarkEnabled', 'screenshotGuardEnabled', 'blurOnHideEnabled']) {
    if (!body.containsKey(k)) continue;
    db.execute(
      'INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      ['$_prefix$k', '${body[k]}'],
    );
  }
}

/// Back to the built-in defaults.
void resetPolicy(Database db) => db.execute("DELETE FROM settings WHERE key LIKE 'policy.%'");
