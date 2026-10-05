import 'dart:typed_data';

import 'package:server/src/attachments.dart';
import 'package:server/src/customer_codes.dart';
import 'package:server/src/deletion_scheduler.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
  test('JPEG: EXIF (APP1) removed, JFIF (APP0) and scan data kept', () {
    final jpeg = Uint8List.fromList([
      0xFF, 0xD8,
      0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46, // APP0
      0xFF, 0xE1, 0x00, 0x06, 0x45, 0x78, 0x69, 0x66, // APP1 "Exif"
      0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0xFF, 0xD9, // SOS + data + EOI
    ]);
    final out = stripImageMetadata(jpeg);
    expect(out.length, jpeg.length - 8);
    expect(out.contains(0xE1), isFalse);
    expect(out.sublist(out.length - 8), [0xFF, 0xDA, 0x00, 0x02, 0x11, 0x22, 0xFF, 0xD9]);
  });

  test('PNG: tEXt/eXIf dropped, IDAT kept', () {
    Uint8List chunk(String type, List<int> data) => Uint8List.fromList([
          0, 0, 0, data.length, ...type.codeUnits, ...data, 0, 0, 0, 0,
        ]);
    final sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    final png = Uint8List.fromList([
      ...sig,
      ...chunk('IHDR', List.filled(13, 0)),
      ...chunk('tEXt', [1, 2, 3]),
      ...chunk('eXIf', [4, 5]),
      ...chunk('IDAT', [9, 9]),
      ...chunk('IEND', []),
    ]);
    final out = String.fromCharCodes(stripImageMetadata(png));
    expect(out.contains('tEXt'), isFalse);
    expect(out.contains('eXIf'), isFalse);
    expect(out.contains('IDAT'), isTrue);
    expect(out.contains('IEND'), isTrue);
  });

  test('non-images pass through', () {
    final b = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]);
    expect(stripImageMetadata(b), b);
  });

  test('custom Mã ID validation', () {
    expect(validateCustomCode('482915'), isNull);
    expect(validateCustomCode('12345'), isNotNull); // too short
    expect(validateCustomCode('12a456'), isNotNull);
    expect(validateCustomCode('111111'), isNotNull);
    expect(validateCustomCode('123456'), isNotNull);
    expect(validateCustomCode('987654'), isNotNull);
    expect(validateCustomCode('121212'), isNotNull);
    expect(validateCustomCode('123123'), isNotNull);
  });

  test('scheduler: data schedule runs once, chat rule keeps running', () {
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = OFF');
    db.execute('CREATE TABLE data_entries (id TEXT, user_id TEXT, customer_name TEXT, entry_date TEXT)');
    db.execute(
      'CREATE TABLE direct_messages (id TEXT, from_user_id TEXT, to_user_id TEXT, content TEXT, '
      'created_at TEXT, attachment_name TEXT, attachment_type TEXT, attachment_size INTEGER, attachment_data BLOB)',
    );
    db.execute(
      'CREATE TABLE deletion_schedules (id TEXT, user_id TEXT, kind TEXT, customer_name TEXT, date_from TEXT, '
      'date_to TEXT, friend_id TEXT, chat_scope TEXT, ttl_seconds INTEGER, run_at TEXT, status TEXT, '
      'deleted_count INTEGER DEFAULT 0, created_at TEXT, executed_at TEXT)',
    );
    db.execute("INSERT INTO data_entries VALUES ('1','u','An','2026-01-01'), ('2','u','Binh','2026-01-02')");
    db.execute(
      "INSERT INTO direct_messages (id, from_user_id, to_user_id, content, created_at) VALUES "
      "('m1','u','f','old','2020-01-01T00:00:00Z'), ('m2','f','u','new','2999-01-01T00:00:00Z')",
    );
    db.execute(
      "INSERT INTO deletion_schedules (id, user_id, kind, customer_name, run_at, status, created_at) "
      "VALUES ('s1','u','data','An','2020-01-01T00:00:00Z','pending','x')",
    );
    db.execute(
      "INSERT INTO deletion_schedules (id, user_id, kind, friend_id, chat_scope, ttl_seconds, run_at, status, created_at) "
      "VALUES ('s2','u','chat','f','all',3600,'2020-01-01T00:00:00Z','pending','x')",
    );
    runDueDeletions(db);
    expect(db.select('SELECT id FROM data_entries').map((r) => r['id']).toList(), ['2']);
    expect(db.select('SELECT id FROM direct_messages').map((r) => r['id']).toList(), ['m2']);
    expect(db.select("SELECT status FROM deletion_schedules WHERE id='s1'").first['status'], 'done');
    expect(db.select("SELECT status FROM deletion_schedules WHERE id='s2'").first['status'], 'pending');
  });
}
