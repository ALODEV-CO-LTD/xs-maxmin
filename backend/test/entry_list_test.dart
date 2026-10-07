import 'package:server/src/entry_list.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Database _db(int n, {String user = 'u1'}) {
  final db = sqlite3.openInMemory();
  db.execute('''
    CREATE TABLE data_entries (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL, customer_name TEXT,
      entry_date TEXT NOT NULL, value TEXT NOT NULL, score TEXT, result TEXT,
      note TEXT, created_at TEXT NOT NULL, bet_type TEXT, updated_at TEXT
    );
  ''');
  for (var i = 0; i < n; i++) {
    final day = (i % 28 + 1).toString().padLeft(2, '0');
    db.execute(
      'INSERT INTO data_entries (id, user_id, entry_date, value, created_at) VALUES (?,?,?,?,?)',
      ['e$i', user, '2026-01-$day', '$i', '2026-01-01T00:00:00.${i.toString().padLeft(6, '0')}Z'],
    );
  }
  db.execute(
    "INSERT INTO data_entries (id, user_id, entry_date, value, created_at) VALUES ('x','other','2026-01-01','1','2026-01-01T00:00:00Z')",
  );
  return db;
}

void main() {
  test('pages cover every row exactly once (more than the old 200 cap)', () {
    final db = _db(700);
    final seen = <String>[];
    var offset = 0;
    while (true) {
      final p = listEntriesPage(db, 'u1', limitParam: '300', offsetParam: '$offset');
      expect(p.total, 700);
      seen.addAll(p.rows.map((r) => r['id'] as String));
      offset += p.rows.length;
      if (offset >= p.total) break;
    }
    expect(seen.length, 700);
    expect(seen.toSet().length, 700);
    expect(seen.contains('x'), isFalse); // other users' rows never leak
  });

  test('order is newest date first and stable', () {
    final db = _db(60);
    final p = listEntriesPage(db, 'u1', limitParam: '60');
    final dates = p.rows.map((r) => r['entry_date'] as String).toList();
    expect(dates, [...dates]..sort((a, b) => b.compareTo(a)));
  });

  test('limit/offset are clamped and defaulted', () {
    final db = _db(1200);
    expect(listEntriesPage(db, 'u1').rows.length, defaultEntriesPageSize);
    expect(listEntriesPage(db, 'u1', limitParam: '99999').rows.length, maxEntriesPageSize);
    expect(listEntriesPage(db, 'u1', limitParam: 'abc', offsetParam: '-5').offset, 0);
    expect(listEntriesPage(db, 'u1', offsetParam: '1190').rows.length, 10);
    expect(listEntriesPage(db, 'u1', offsetParam: '5000').rows, isEmpty);
  });

  test('vietnamToday rolls over at 17:00 UTC', () {
    expect(vietnamToday(DateTime.utc(2026, 3, 9, 16, 59)), '2026-03-09');
    expect(vietnamToday(DateTime.utc(2026, 3, 9, 17, 0)), '2026-03-10');
    expect(vietnamToday(DateTime.utc(2026, 12, 31, 20)), '2027-01-01');
  });
}
