import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

Database _empty() {
  final db = sqlite3.openInMemory();
  db.execute('PRAGMA foreign_keys = ON');
  db.execute(File('schema.sql').readAsStringSync());
  return db;
}

void main() {
  test('no env: only the admin, with a random password logged once (never 1234)', () {
    final db = _empty();
    final lines = <String>[];
    seedDatabase(db, {}, log: lines.add);
    final users = db.select('SELECT username, password_hash, role FROM users');
    expect(users.length, 1);
    expect(users.first['username'], '1');
    expect(users.first['role'], 'admin');
    expect(BCrypt.checkpw('1234', users.first['password_hash'] as String), isFalse);
    expect(lines.length, 1);
    expect(lines.single, startsWith('[seed] admin password: '));
    final pw = lines.single.substring('[seed] admin password: '.length);
    expect(pw.length, 16);
    expect(BCrypt.checkpw(pw, users.first['password_hash'] as String), isTrue);
  });

  test('two seeds give different random passwords', () {
    expect(generateAdminPassword(), isNot(generateAdminPassword()));
  });

  test('XOSO_ADMIN_PASSWORD is used and nothing is printed', () {
    final db = _empty();
    final lines = <String>[];
    seedDatabase(db, {'XOSO_ADMIN_PASSWORD': 'my-own-secret'}, log: lines.add);
    expect(lines, isEmpty);
    final hash = db.select("SELECT password_hash FROM users WHERE username = '1'").first['password_hash'] as String;
    expect(BCrypt.checkpw('my-own-secret', hash), isTrue);
  });

  test('demo customers only with XOSO_SEED_DEMO=1', () {
    final db = _empty();
    seedDatabase(db, {'XOSO_SEED_DEMO': '1', 'XOSO_ADMIN_PASSWORD': 'x-secret'}, log: (_) {});
    expect(db.select("SELECT 1 FROM users WHERE role = 'user'").length, 5);
    final off = _empty();
    seedDatabase(off, {'XOSO_SEED_DEMO': '0', 'XOSO_ADMIN_PASSWORD': 'x-secret'}, log: (_) {});
    expect(off.select("SELECT 1 FROM users WHERE role = 'user'"), isEmpty);
  });
}
