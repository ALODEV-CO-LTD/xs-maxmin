import 'package:server/src/lottery_stations.dart';
import 'package:test/test.dart';

void main() {
  int boxes(Region r) => r.structure.fold(0, (n, p) => n + p.count);

  test('prize structures: Miền Bắc 27 numbers, Miền Nam / Miền Trung 18 with a 6-digit special prize', () {
    expect(boxes(regions['mb']!), 27);
    expect(boxes(regions['mn']!), 18);
    expect(boxes(regions['mt']!), 18);
    expect(regions['mb']!.structure.first.digits, 5);
    expect(regions['mn']!.structure.first.digits, 6);
    expect(regions['mn']!.structure.last.tier, 'giaiTam');
  });

  test('every weekday has stations in every region, all of them known', () {
    for (final r in regions.values) {
      for (var wd = 1; wd <= 7; wd++) {
        final list = r.schedule[wd]!;
        expect(list, isNotEmpty, reason: '${r.id} weekday $wd');
        for (final st in list) {
          expect(r.stations.containsKey(st), isTrue, reason: st);
        }
      }
    }
  });

  test('Saturday has 4 Miền Nam stations (TP.HCM, Long An, Bình Phước, Hậu Giang), Monday 3', () {
    final sat = DateTime(2026, 10, 10); // a Saturday
    final mon = DateTime(2026, 10, 12);
    expect(stationsOn('mn', sat), ['mn-tphcm', 'mn-longan', 'mn-binhphuoc', 'mn-haugiang']);
    expect(stationsOn('mn', mon).length, 3);
    expect(stationsOn('mb', sat), ['mb']);
  });

  test('station codes', () {
    expect(isResultStation('mb'), isTrue);
    expect(isResultStation('mn-tphcm'), isTrue);
    expect(isResultStation('mn'), isFalse); // a region is not a single draw
    expect(isResultStation('zzz'), isFalse);
    expect(isEntryStation('mn'), isTrue);
    expect(isEntryStation('mt-hue'), isTrue);
    expect(isEntryStation('zzz'), isFalse);
    expect(regionOf('mt-danang')!.id, 'mt');
  });
}
