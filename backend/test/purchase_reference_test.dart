import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/database.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import '../routes/api/me/packages/purchase.dart' as purchase;
import 'support.dart';

late Database db;

Future<Map<String, dynamic>> buy(String user, Object? body) async {
  final r = await callRoute(purchase.onRequest, db, userId: user, method: HttpMethod.post, body: body);
  return {...await jsonBody(r), 'code': r.statusCode};
}

void main() {
  setUp(() {
    db = testDb();
    db.execute('''
      CREATE TABLE packages (code TEXT PRIMARY KEY, label TEXT NOT NULL, duration_days INTEGER NOT NULL, price_vnd INTEGER NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, active INTEGER NOT NULL DEFAULT 1)
    ''');
    db.execute("INSERT INTO packages (code, label, duration_days, price_vnd) VALUES ('1m', '1 tháng', 30, 99000)");
    db.execute('ALTER TABLE payment_requests ADD COLUMN reference_code TEXT'); // added by a migration in prod
  });

  test('the reference the app printed in the QR becomes the request\'s reference', () async {
    final r = await buy('u1', {'packageType': '1m', 'referenceCode': 'XS7K2MQA'});
    expect(r['code'], 201);
    expect(r['referenceCode'], 'XS7K2MQA');
    expect(db.select('SELECT reference_code FROM payment_requests').single['reference_code'], 'XS7K2MQA');
  });

  test('no reference, a malformed one or one already used: the server makes its own', () async {
    final none = await buy('u1', {'packageType': '1m'});
    expect(none['referenceCode'], matches(paymentReferencePattern));
    db.execute("UPDATE payment_requests SET status = 'approved'"); // u1 may buy again
    final bad = await buy('u1', {'packageType': '1m', 'referenceCode': 'hello'});
    expect(bad['referenceCode'], matches(paymentReferencePattern));
    expect(bad['referenceCode'], isNot('hello'));
    db.execute("UPDATE payment_requests SET status = 'approved'");
    final used = await buy('u2', {'packageType': '1m', 'referenceCode': none['referenceCode']});
    expect(used['code'], 201);
    expect(used['referenceCode'], isNot(none['referenceCode']));
    // letters the alphabet leaves out (0, O, 1, I) are not accepted either
    db.execute("UPDATE payment_requests SET status = 'approved'");
    final odd = await buy('u1', {'packageType': '1m', 'referenceCode': 'XS0O1I22'});
    expect(odd['referenceCode'], isNot('XS0O1I22'));
  });

  test('still one waiting request per customer', () async {
    await buy('u1', {'packageType': '1m', 'referenceCode': 'XS7K2MQA'});
    final again = await buy('u1', {'packageType': '1m', 'referenceCode': 'XS7K2MQB'});
    expect(again['code'], 409);
  });
}
