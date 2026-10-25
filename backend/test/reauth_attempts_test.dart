import 'package:bcrypt/bcrypt.dart';
import 'package:dart_frog/dart_frog.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/me/verify-password.dart' as route;
import 'support.dart';

late Database db;

Future<Response> tryPassword(String pw) => callRoute(route.onRequest, db, userId: 'u1', method: HttpMethod.post, body: {'password': pw});

void main() {
  setUp(() {
    db = testDb();
    db.execute("UPDATE users SET password_hash = ? WHERE id = 'u1'", [BCrypt.hashpw('dung-roi', BCrypt.gensalt())]);
  });

  test('a wrong password says how many tries were used, the maximum and how many are left; then the lock gives its seconds', () async {
    final left = <int>[];
    for (var i = 1; i <= 4; i++) {
      final r = await tryPassword('sai');
      expect(r.statusCode, 403);
      final b = await jsonBody(r);
      expect(b['failedAttempts'], i);
      expect(b['maxAttempts'], 5);
      left.add(b['attemptsLeft'] as int);
    }
    expect(left, [4, 3, 2, 1]);
    final locked = await tryPassword('sai'); // the 5th wrong one starts the lock
    expect(locked.statusCode, 429);
    final b = await jsonBody(locked);
    expect(b['retryAfterSeconds'], greaterThan(0));
    expect(b['retryAfterSeconds'], lessThanOrEqualTo(31));
    // while locked even the right password waits, and the seconds keep counting down on the server
    expect((await tryPassword('dung-roi')).statusCode, 429);
  });

  test('a right password resets the count', () async {
    await tryPassword('sai');
    await tryPassword('sai');
    expect((await tryPassword('dung-roi')).statusCode, 200);
    final b = await jsonBody(await tryPassword('sai'));
    expect(b['failedAttempts'], 1);
    expect(b['attemptsLeft'], 4);
  });
}
