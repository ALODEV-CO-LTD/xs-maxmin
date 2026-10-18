import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mamba_app/core/api_client.dart';
import 'package:mamba_app/core/auth_store.dart';
import 'package:mamba_app/core/lottery_catalog.dart';
import 'package:mamba_app/core/lottery_stations.dart';
import 'package:shared_preferences/shared_preferences.dart';

ApiClient _api({bool offline = false, Object? body}) => ApiClient(
      AuthStore()..token = 'x.eyJzdWIiOiJ1MSJ9.y',
      client: MockClient((r) async {
        if (offline) throw http.ClientException('no network');
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );

Map<String, dynamic> _json(List<Region> rs) => {
      'regions': [
        for (final r in rs)
          {
            'id': r.id,
            'name': r.name,
            'stations': r.stations,
            'schedule': {for (final e in r.schedule.entries) '${e.key}': e.value},
            'structure': [for (final p in r.structure) {'tier': p.tier, 'label': p.label, 'count': p.count, 'digits': p.digits}],
          },
      ],
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the built-in catalog has the three regions, their stations by weekday and prize structure', () {
    final s = LotteryStations();
    expect(s.regionList.map((r) => r.id), ['mb', 'mt', 'mn']);
    expect(s.regionOf('mn').stations.length, 21);
    expect(s.regionOf('mt').stations.length, 14);
    expect(s.stationsOn('mb', '2026-10-07'), ['mb']);
    expect(s.stationsOn('mn', '2026-10-07'), ['mn-dongnai', 'mn-cantho', 'mn-soctrang']); // Wednesday
    expect(s.stationsOn('mt', '2026-10-11'), ['mt-kontum', 'mt-khanhhoa', 'mt-hue']); // Sunday
    expect(s.regionOf('mn').structure.map((p) => p.digits * p.count).fold<int>(0, (a, b) => a + b), 6 + 5 + 5 + 10 + 35 + 4 + 12 + 3 + 2);
    expect(s.stationName('mt-hue'), 'Thừa Thiên Huế');
  });

  test('no network: load() does not fail and the built-in catalog stays', () async {
    final s = LotteryStations();
    await s.load(_api(offline: true));
    expect(s.loaded, isFalse);
    expect(s.regionList.length, 3);
  });

  test('the server copy replaces the built-in one and is kept for the next time the network is down', () async {
    final changed = [
      ...builtInRegions.where((r) => r.id != 'mn'),
      Region(id: 'mn', name: 'Miền Nam', stations: {...builtInRegions.last.stations, 'mn-moi': 'Đài mới'}, schedule: builtInRegions.last.schedule, structure: builtInRegions.last.structure),
    ];
    final online = LotteryStations();
    await online.load(_api(body: _json(changed)));
    expect(online.loaded, isTrue);
    expect(online.stationName('mn-moi'), 'Đài mới');

    // a later start with no network: the kept copy, not just the built-in one
    final offline = LotteryStations();
    await offline.load(_api(offline: true));
    expect(offline.stationName('mn-moi'), 'Đài mới');
  });
}
