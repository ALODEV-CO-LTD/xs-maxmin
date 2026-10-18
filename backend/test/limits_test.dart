import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:mocktail/mocktail.dart';
import 'package:server/src/customer_codes.dart';
import 'package:server/src/rate_gate.dart';
import 'package:server/src/request_body.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/auth/register.dart' as register;
import '../routes/api/me/customer-codes/[id].dart' as codeById;
import '../routes/api/me/customer-codes/index.dart' as codes;
import '../routes/api/me/customers/index.dart' as customers;
import '../routes/api/me/entries/index.dart' as entries;
import '../routes/api/me/messages/index.dart' as messages;
import 'support.dart';

Future<JsonBodyResult> _read(Request req, int max) {
  final ctx = FakeCtx();
  when(() => ctx.request).thenReturn(req);
  return readJsonBody(ctx, max);
}

Database _dbWithCodes() {
  return testDb();
}

void main() {
  group('readJsonBody', () {
    test('accepts a JSON object within the limit', () async {
      final r = await _read(Request('POST', Uri.parse('http://x/'), body: '{"a":1}'), 100);
      expect(r.body, {'a': 1});
    });

    test('413 from Content-Length alone, before reading the body', () async {
      final r = await _read(Request('POST', Uri.parse('http://x/'), body: Stream.value(utf8.encode('{"a":1}')), headers: {'content-length': '999999'}), 100);
      expect(r.error!.statusCode, 413);
    });

    test('413 when the streamed body is over the limit even without a Content-Length', () async {
      final big = jsonEncode({'a': 'x' * 500});
      final r = await _read(Request('POST', Uri.parse('http://x/'), body: Stream.value(utf8.encode(big))), 100);
      expect(r.error!.statusCode, 413);
    });

    test('400 for invalid JSON, arrays and scalars', () async {
      for (final b in ['{nope', '[1]', '5', '', '"x"']) {
        final r = await _read(Request('POST', Uri.parse('http://x/'), body: b), 100);
        expect(r.error!.statusCode, 400, reason: b);
      }
    });
  });

  group('auth routes', () {
    test('register: 8 KB body limit (413), long fields (400), non-string fields (400)', () async {
      final db = testDb();
      var r = await callRoute(register.onRequest, db, body: {'name': 'x' * 9000});
      expect(r.statusCode, 413);
      r = await callRoute(register.onRequest, db, body: {'name': 'n' * 61, 'username': 'abcd', 'password': 'p', 'secondPassword': 'q'});
      expect(r.statusCode, 400);
      r = await callRoute(register.onRequest, db, body: {'name': 5, 'username': 'abcd', 'password': 'p', 'secondPassword': 'q'});
      expect(r.statusCode, 400);
    });

    test('register: at most 10 attempts per hour per IP, then 429', () async {
      final db = testDb();
      // unique key per test run: all test requests share the "unknown" IP, so reset by using the gate directly.
      final gate = SlidingWindowGate(limit: 10, window: const Duration(hours: 1));
      for (var i = 0; i < 10; i++) {
        expect(gate.hit('ip:1.2.3.4'), 0);
      }
      expect(gate.hit('ip:1.2.3.4'), greaterThan(0));
      expect(registerPerIp.limit, 10);
      expect(registerPerIp.window, const Duration(hours: 1));

      // Through the route: exhaust the shared per-IP gate, the next call is a 429.
      for (var i = 0; i < 20; i++) {
        final r = await callRoute(register.onRequest, db, body: {'name': ''});
        if (r.statusCode == 429) {
          expect(r.headers['Retry-After'], isNotNull);
          return;
        }
        expect(r.statusCode, 400);
      }
      fail('expected a 429');
    });
  });

  group('messages (support)', () {
    test('413 for a huge body, 400 for content over 4000 chars or not a string', () async {
      final db = testDb();
      var r = await callRoute(messages.onRequest, db, headers: {'content-length': '${messageBodyMaxBytes + 1}'}, body: {'content': 'hi'});
      expect(r.statusCode, 413);
      r = await callRoute(messages.onRequest, db, body: {'content': 'x' * 4001});
      expect(r.statusCode, 400);
      r = await callRoute(messages.onRequest, db, body: {'content': 7});
      expect(r.statusCode, 400);
    });

    test('at most 30 messages per hour per user, then 429; other users unaffected', () async {
      final db = testDb();
      for (var i = 0; i < 30; i++) {
        final r = await callRoute(messages.onRequest, db, userId: 'u1', body: {'content': 'hello $i'});
        expect(r.statusCode, 201, reason: 'message $i');
      }
      var r = await callRoute(messages.onRequest, db, userId: 'u1', body: {'content': 'one more'});
      expect(r.statusCode, 429);
      r = await callRoute(messages.onRequest, db, userId: 'u2', body: {'content': 'hi'});
      expect(r.statusCode, 201);
    });
  });

  group('entries and customers', () {
    test('non-string or over-long text fields are a 400, not a 500', () async {
      final db = testDb();
      for (final body in [
        {'value': 5, 'customerName': 'A'},
        {'value': '12', 'customerName': 7},
        {'value': '12', 'customerName': 'A', 'note': ['x']},
        {'value': '12', 'customerName': 'A', 'note': 'n' * 1001},
        {'value': 'v' * 2001, 'customerName': 'A'},
        {'value': '12', 'customerName': 'c' * 101},
      ]) {
        final r = await callRoute(entries.onRequest, db, body: body);
        expect(r.statusCode, 400, reason: '$body');
      }
      for (final body in [
        {'name': 5},
        {'name': 'n' * 101},
      ]) {
        final r = await callRoute(customers.onRequest, db, body: body);
        expect(r.statusCode, 400, reason: '$body');
      }
      expect((await callRoute(entries.onRequest, db, body: {'value': 'x' * 300000, 'customerName': 'A'})).statusCode, 413);
    });
  });

  group('customer codes', () {
    test('409 answers count as failed guesses and lead to a 429 lock', () async {
      final db = _dbWithCodes();
      db.execute("INSERT INTO customer_codes (id, user_id, code, created_at) VALUES ('c0','u2','482915','2026-01-01')");
      var locked = false;
      for (var i = 0; i < 40; i++) {
        final r = await callRoute(codes.onRequest, db, userId: 'u1', body: {'code': '482915'});
        if (r.statusCode == 429) {
          locked = true;
          break;
        }
        expect(r.statusCode, 409);
      }
      expect(locked, isTrue);
    });

    test('markCodeUsed sets used_at once', () {
      final db = _dbWithCodes();
      db.execute("INSERT INTO customer_codes (id, user_id, code, created_at) VALUES ('c1','u1','324097','2026-01-01')");
      expect(db.select('SELECT used_at FROM customer_codes').single['used_at'], isNull);
      markCodeUsed(db, '324097');
      final first = db.select('SELECT used_at FROM customer_codes').single['used_at'];
      expect(first, isNotNull);
      markCodeUsed(db, '324097');
      expect(db.select('SELECT used_at FROM customer_codes').single['used_at'], first);
    });

    test('a code deleted without ever being used is not quarantined; a used one is', () async {
      final db = _dbWithCodes();
      db.execute("INSERT INTO customer_codes (id, user_id, code, created_at, used_at) VALUES ('c1','u1','324097','2026-01-01',NULL)");
      db.execute("INSERT INTO customer_codes (id, user_id, code, created_at, used_at) VALUES ('c2','u1','907318','2026-01-01','2026-01-02')");
      var r = await callRoute((c) => codeById.onRequest(c, 'c1'), db, method: HttpMethod.delete);
      expect(r.statusCode, 200);
      r = await callRoute((c) => codeById.onRequest(c, 'c2'), db, method: HttpMethod.delete);
      expect(r.statusCode, 200);
      final retired = db.select('SELECT code FROM retired_codes').map((x) => x['code']).toList();
      expect(retired, ['907318']);
    });
  });
}
