import 'package:sqlite3/sqlite3.dart';

/// App version management (A17): the Admin sets the newest version, the oldest version still allowed and where to
/// download the Android app; the app asks `GET /api/app-version` when it starts and asks the user to update (or, below
/// the minimum, blocks until it is updated). Stored in the `settings` store under `app_*` keys.
class AppVersionInfo {
  const AppVersionInfo({this.latest = '', this.min = '', this.downloadUrl = '', this.notes = ''});
  final String latest; // newest released version, '' = not set
  final String min; // oldest version allowed to run, '' = no minimum
  final String downloadUrl; // https link to the APK or the download page
  final String notes; // what is new (shown in the update dialog)

  Map<String, String> toJson() => {'latestVersion': latest, 'minVersion': min, 'downloadUrl': downloadUrl, 'notes': notes};
}

const _keys = {
  'latestVersion': 'app_latest_version',
  'minVersion': 'app_min_version',
  'downloadUrl': 'app_download_url',
  'notes': 'app_release_notes',
};

/// Every settings key owned by this feature (the generic settings list must not show them as "other keys").
const appVersionSettingKeys = ['app_latest_version', 'app_min_version', 'app_download_url', 'app_release_notes'];

final _versionPattern = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$');

/// -1 / 0 / 1 comparing two `x.y.z` versions, null when either is not a version.
int? compareVersions(String a, String b) {
  if (!_versionPattern.hasMatch(a) || !_versionPattern.hasMatch(b)) return null;
  final pa = a.split('.').map(int.parse).toList();
  final pb = b.split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (pa[i] != pb[i]) return pa[i] < pb[i] ? -1 : 1;
  }
  return 0;
}

AppVersionInfo loadAppVersion(Database db) {
  String get(String k) {
    final r = db.select('SELECT value FROM settings WHERE key = ?', [_keys[k]]);
    return r.isEmpty ? '' : (r.first['value'] as String? ?? '');
  }

  return AppVersionInfo(latest: get('latestVersion'), min: get('minVersion'), downloadUrl: get('downloadUrl'), notes: get('notes'));
}

/// Validates a submitted (partial) configuration against the stored one; returns an error message or null.
String? validateAppVersionInput(Map<String, dynamic> body, AppVersionInfo current) {
  String? text(String k) => body[k] is String ? (body[k] as String).trim() : null;
  final latest = text('latestVersion') ?? current.latest;
  final min = text('minVersion') ?? current.min;
  for (final k in ['latestVersion', 'minVersion']) {
    if (body.containsKey(k) && body[k] is! String) return 'Phiên bản phải là chuỗi dạng 1.2.3';
    final v = text(k);
    if (v != null && v.isNotEmpty && !_versionPattern.hasMatch(v)) {
      return '${k == 'latestVersion' ? 'Phiên bản mới nhất' : 'Phiên bản tối thiểu'} phải có dạng 1.2.3 (ba số, cách nhau bằng dấu chấm)';
    }
  }
  if (latest.isNotEmpty && min.isNotEmpty && compareVersions(min, latest)! > 0) {
    return 'Phiên bản tối thiểu không được lớn hơn phiên bản mới nhất';
  }
  if (min.isNotEmpty && latest.isEmpty) return 'Hãy nhập phiên bản mới nhất trước khi đặt phiên bản tối thiểu';
  if (body.containsKey('downloadUrl')) {
    if (body['downloadUrl'] is! String) return 'Đường dẫn tải phải là chuỗi';
    final u = text('downloadUrl')!;
    if (u.length > 500) return 'Đường dẫn tải tối đa 500 ký tự';
    if (u.isNotEmpty) {
      final uri = Uri.tryParse(u);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return 'Đường dẫn tải phải bắt đầu bằng https://';
    }
  }
  if (body.containsKey('notes')) {
    if (body['notes'] is! String) return 'Ghi chú phải là chuỗi';
    if (text('notes')!.length > 500) return 'Ghi chú tối đa 500 ký tự';
  }
  return null;
}

void saveAppVersion(Database db, Map<String, dynamic> body) {
  for (final e in _keys.entries) {
    if (body[e.key] is! String) continue;
    final v = (body[e.key] as String).trim();
    if (v.isEmpty) {
      db.execute('DELETE FROM settings WHERE key = ?', [e.value]);
    } else {
      db.execute('INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value', [e.value, v]);
    }
  }
}
