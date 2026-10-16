import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/customers/customer_model.dart';
import 'package:mamba_app/features/customers/customers_controller.dart';
import 'package:mamba_app/features/scoring/entry_model.dart';
import 'package:mamba_app/features/scoring/scoring_logic.dart';

import 'scoring_fixtures.dart';

String _jwt(String sub) {
  String part(Map m) => base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${part({'alg': 'x'})}.${part({'sub': sub})}.sig';
}

void main() {
  test('saveHomeRegion PATCHes { homeRegion } and keeps what the server answers', () async {
    final bodies = <Map<String, dynamic>>[];
    final api = ApiClient(
      AuthStore()..token = _jwt('u1'),
      client: MockClient((req) async {
        expect(req.method, 'PATCH');
        expect(req.url.path, '/api/me/customers/c1');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        bodies.add(body);
        final v = body['homeRegion'];
        return http.Response(jsonEncode({'homeRegion': v == '' ? null : v}), 200, headers: {'content-type': 'application/json'});
      }),
    );
    final ctl = CustomersController(api: api, auth: api.auth);
    final c = Customer(id: 'c1', name: 'An');
    expect(await ctl.saveHomeRegion(c, 'mn'), '');
    expect(c.homeRegion, 'mn');
    expect(await ctl.saveHomeRegion(c, null), '');
    expect(c.homeRegion, isNull);
    expect(bodies, [
      {'homeRegion': 'mn'},
      {'homeRegion': ''},
    ]);
  });

  test('CustomerRec reads homeRegion (only mb / mn)', () {
    expect(CustomerRec.fromJson({'id': '1', 'name': 'A', 'homeRegion': 'mn'}).homeRegion, 'mn');
    expect(CustomerRec.fromJson({'id': '1', 'name': 'A', 'homeRegion': 'mt'}).homeRegion, isNull);
    expect(CustomerRec.fromJson({'id': '1', 'name': 'A'}).homeRegion, isNull);
  });

  test('"Điểm ra" of Đầu on a Miền Bắc result depends on the customer region', () {
    final lr = <String, dynamic>{'dacBiet': ['70002'], 'giaiNhat': ['11120'], 'giaiBay': ['20', '15', '88', '33']};
    final e = Entry(id: 'e', customerName: 'An', entryDate: '2026-10-12', value: '20', score: '3', betType: 'dau', station: 'mb');
    double? out(String? region) => entryOutTotal(
          entry: e,
          stations: testStations(),
          accountRates: defaultRates,
          customerRates: null,
          resultOf: (st) => lr,
          customerRegion: region,
        );
    // 3 điểm × (70.000 / 1.000) × 1 hit, for a Bắc customer (giải nhất) and for a Nam customer (giải bảy)
    expect(out(null), closeTo(210, 1e-9));
    expect(out('mb'), closeTo(210, 1e-9));
    expect(out('mn'), closeTo(210, 1e-9));
    // a number only in giải nhất (11120 -> "20") vs only in giải bảy
    final onlyBay = {...lr, 'giaiNhat': ['11199']};
    expect(entryOutTotal(entry: e, stations: testStations(), accountRates: defaultRates, customerRates: null, resultOf: (st) => onlyBay), 0);
    expect(entryOutTotal(entry: e, stations: testStations(), accountRates: defaultRates, customerRates: null, resultOf: (st) => onlyBay, customerRegion: 'mn'), closeTo(210, 1e-9));
  });
}
