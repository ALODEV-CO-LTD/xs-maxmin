/// Version helpers shared by the Admin settings form and the app's update check (A17).
/// A version is `x.y.z` (three numbers); empty = "not set".
final _pattern = RegExp(r'^\d{1,4}\.\d{1,4}\.\d{1,4}$');

bool isVersion(String v) => _pattern.hasMatch(v.trim());

/// -1 / 0 / 1, or null when either side is not a version.
int? compareVersions(String a, String b) {
  if (!isVersion(a) || !isVersion(b)) return null;
  final x = a.trim().split('.').map(int.parse).toList();
  final y = b.trim().split('.').map(int.parse).toList();
  for (var i = 0; i < 3; i++) {
    if (x[i] != y[i]) return x[i] < y[i] ? -1 : 1;
  }
  return 0;
}

/// What `GET /app-version` says (empty strings = not set by the Admin).
class AppVersionInfo {
  const AppVersionInfo({this.latest = '', this.min = '', this.downloadUrl = '', this.notes = ''});
  final String latest, min, downloadUrl, notes;

  factory AppVersionInfo.fromJson(Map<String, dynamic> j) => AppVersionInfo(
        latest: '${j['latestVersion'] ?? ''}',
        min: '${j['minVersion'] ?? ''}',
        downloadUrl: '${j['downloadUrl'] ?? ''}',
        notes: '${j['notes'] ?? ''}',
      );

  Map<String, String> toBody() => {'latestVersion': latest, 'minVersion': min, 'downloadUrl': downloadUrl, 'notes': notes};

  @override
  bool operator ==(Object other) => other is AppVersionInfo && other.latest == latest && other.min == min && other.downloadUrl == downloadUrl && other.notes == notes;
  @override
  int get hashCode => Object.hash(latest, min, downloadUrl, notes);
}

/// First problem with an Admin's input (same rules as the server), or null.
String? validateAppVersionForm(AppVersionInfo v) {
  final l = v.latest.trim(), m = v.min.trim();
  if (l.isNotEmpty && !isVersion(l)) return 'Phiên bản mới nhất phải có dạng 1.2.3';
  if (m.isNotEmpty && !isVersion(m)) return 'Phiên bản tối thiểu phải có dạng 1.2.3';
  if (m.isNotEmpty && l.isEmpty) return 'Hãy nhập phiên bản mới nhất trước khi đặt phiên bản tối thiểu';
  if (l.isNotEmpty && m.isNotEmpty && compareVersions(m, l)! > 0) return 'Phiên bản tối thiểu không được lớn hơn phiên bản mới nhất';
  final u = v.downloadUrl.trim();
  if (u.isNotEmpty && !RegExp(r'^https://\S+$').hasMatch(u)) return 'Đường dẫn tải phải bắt đầu bằng https://';
  if (v.notes.length > 500) return 'Ghi chú tối đa 500 ký tự';
  return null;
}

enum UpdateNeed { none, optional, required }

/// What the app must do for the installed [current] version: nothing, offer an update (below the newest) or block
/// (below the minimum). A server answer that is not a valid version never blocks the app.
UpdateNeed updateNeed(String current, AppVersionInfo info) {
  final belowMin = info.min.isNotEmpty && (compareVersions(current, info.min) ?? 0) < 0;
  if (belowMin) return UpdateNeed.required;
  final belowLatest = info.latest.isNotEmpty && (compareVersions(current, info.latest) ?? 0) < 0;
  return belowLatest ? UpdateNeed.optional : UpdateNeed.none;
}
