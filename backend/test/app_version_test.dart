import 'package:server/src/app_version.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Database _db() {
  final db = sqlite3.openInMemory();
  db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
  return db;
}

void main() {
  test('compareVersions orders x.y.z numerically', () {
    expect(compareVersions('1.2.0', '1.10.0'), -1);
    expect(compareVersions('2.0.0', '1.99.99'), 1);
    expect(compareVersions('1.2.3', '1.2.3'), 0);
    expect(compareVersions('1.2', '1.2.3'), isNull);
    expect(compareVersions('a.b.c', '1.2.3'), isNull);
  });

  test('defaults are empty and save/clear round trips', () {
    final db = _db();
    expect(loadAppVersion(db).toJson(), {'latestVersion': '', 'minVersion': '', 'downloadUrl': '', 'notes': ''});
    saveAppVersion(db, {'latestVersion': '1.3.0', 'minVersion': '1.1.0', 'downloadUrl': 'https://example.com/MAMBA.apk', 'notes': 'Mới'});
    final v = loadAppVersion(db);
    expect([v.latest, v.min, v.downloadUrl, v.notes], ['1.3.0', '1.1.0', 'https://example.com/MAMBA.apk', 'Mới']);
    saveAppVersion(db, {'minVersion': ''});
    expect(loadAppVersion(db).min, '');
    expect(loadAppVersion(db).latest, '1.3.0');
  });

  test('validation: format, min <= latest, https link, lengths', () {
    const none = AppVersionInfo();
    expect(validateAppVersionInput({'latestVersion': '1.2.3'}, none), isNull);
    expect(validateAppVersionInput({'latestVersion': '1.2'}, none), isNotNull);
    expect(validateAppVersionInput({'latestVersion': 'v1.2.3'}, none), isNotNull);
    expect(validateAppVersionInput({'minVersion': '1.0.0'}, none), isNotNull); // latest not set yet
    expect(validateAppVersionInput({'latestVersion': '1.0.0', 'minVersion': '1.1.0'}, none), isNotNull);
    expect(validateAppVersionInput({'minVersion': '1.5.0'}, const AppVersionInfo(latest: '1.2.0')), isNotNull);
    expect(validateAppVersionInput({'latestVersion': '1.0.0'}, const AppVersionInfo(latest: '2.0.0', min: '1.5.0')), isNotNull);
    expect(validateAppVersionInput({'downloadUrl': 'http://example.com/a.apk'}, none), isNotNull);
    expect(validateAppVersionInput({'downloadUrl': 'javascript:alert(1)'}, none), isNotNull);
    expect(validateAppVersionInput({'downloadUrl': 'https://example.com/a.apk'}, none), isNull);
    expect(validateAppVersionInput({'downloadUrl': ''}, none), isNull);
    expect(validateAppVersionInput({'notes': 'x' * 501}, none), isNotNull);
    expect(validateAppVersionInput({'latestVersion': 5}, none), isNotNull);
  });
}
