import 'dart:typed_data';

import 'package:server/src/attachments.dart';
import 'package:server/src/customer_codes.dart';
import 'package:server/src/deletion_scheduler.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

void main() {
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
      'deleted_count INTEGER DEFAULT 0, created_at TEXT, executed_at TEXT, repeat_every INTEGER, '
      'repeat_unit TEXT, keep_days INTEGER NOT NULL DEFAULT 0, run_count INTEGER NOT NULL DEFAULT 0, first_run_at TEXT)',
    );
    db.execute('CREATE TABLE users (id TEXT, data_used INTEGER DEFAULT 0)');
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
