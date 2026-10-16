// "Bảng cấu hình" (Kiểu đánh - Giá tiền/1 điểm - Giá trúng/1 điểm): how a hit is found and how the money is worked out.
// Same cases and figures as frontend/tests/scoringTable.test.mjs.
import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/scoring/entry_model.dart';
import 'package:mamba_app/features/scoring/scoring_logic.dart';

import 'scoring_fixtures.dart';

// A Miền Nam day (18 lô; giải tám 2 số, giải bảy 3 số, đặc biệt 6 số) and a Miền Bắc day (27 lô).
final LotteryResult mn = {
  'giaiTam': ['20'],
  'giaiBay': ['120'],
  'giaiSau': ['1234', '5678', '0020'],
  'giaiNam': ['9020'],
  'giaiTu': ['11111', '22222', '33333', '44444', '55555', '66666', '77720'],
  'giaiBa': ['12345', '23456'],
  'giaiNhi': ['34567'],
  'giaiNhat': ['45678'],
  'dacBiet': ['123456'],
};
final LotteryResult mb = {
  'dacBiet': ['70002'],
  'giaiNhat': ['11120'],
  'giaiNhi': ['11111', '22222'],
  'giaiBa': [for (final x in ['1', '2', '3', '4', '5', '6']) x * 5],
  'giaiTu': ['1234', '5678', '9012', '3456'],
  'giaiNam': ['1111', '2222', '3333', '4444', '5555', '6666'],
  'giaiSau': ['123', '456', '789'],
  'giaiBay': ['20', '15', '88', '33'],
};

Cfg row(String kind, [String region = 'mn']) => defaultRow(kind, region);
Entry entry(String value, num score, {String? betType, String? station}) =>
    Entry(id: 'e', customerName: 'An', entryDate: '2026-10-12', value: value, score: '$score', betType: betType, station: station);
String hits(EntryDetail d) => d.perNumber.map((p) => '${p.number}:${p.hits}').join(' ');
const mnCtx = ScoreCtx(region: 'mn');

ScoreSummary run(List<Entry> entries, RatesMap rates, LotteryResult? Function(String, String) getResult, {String? customerRegion}) =>
    summarize([DayEntries('2026-10-12', entries)], rates, null, getResult, testStations(), customerRegion: customerRegion);

void main() {
  group('hit counting', () {
    test('bao lô: 2 số so 18 lô Nam (cả giải tám), nhiều lô về thì nhân lên', () {
      // "20" về ở giải tám, giải bảy 120, giải sáu 0020, giải năm 9020, giải tư 77720 = 5 lần
      expect(hits(entryDetail(entry('20', 10), mn, row('lo'), mnCtx)), '20:5');
    });
    test('bao lô 3 số chỉ so các giải có từ 3 chữ số', () {
      expect(hits(entryDetail(entry('020', 1), mn, row('lo3'), mnCtx)), '020:2'); // 0020, 9020 -> 020; giải tám "20" không tính
    });
    test('bao lô 4 số: chỉ các lô có từ 4 chữ số', () {
      expect(hits(entryDetail(entry('9020', 1), mn, row('lo4'), mnCtx)), '9020:1');
      expect(hits(entryDetail(entry('0020', 1), mn, row('lo4'), mnCtx)), '0020:1');
      expect(hits(entryDetail(entry('1234', 1), mb, row('lo4', 'mb'), const ScoreCtx(region: 'mb'))), '1234:1');
    });
    test('mỗi miền một cách lấy số: "20" Bắc 27 lô = 2 lần, Nam 18 lô (cả giải tám) = 5 lần; bao lô 2 số chặt 2 chữ số', () {
      expect(hits(entryDetail(entry('20', 1), mb, row('lo', 'mb'), const ScoreCtx(region: 'mb'))), '20:2');
      expect(hits(entryDetail(entry('20', 1), mn, row('lo'), mnCtx)), '20:5');
      expect(hits(entryDetail(entry('020', 1), mn, row('lo'), mnCtx)), '20:5'); // lo always takes the last 2 digits
    });
    test('lô trượt: trúng khi TẤT CẢ các số đều không về, một lần; tiền xác × số số', () {
      final none = entryDetail(entry('01 02 03 04', 10), mn, row('truot4'), mnCtx);
      expect(none.totalHits, 1);
      expect(none.lots, 4);
      expect(entryDetail(entry('01 02 03 20', 10), mn, row('truot4'), mnCtx).totalHits, 0); // 20 về
      expect(entryDetail(entry('01 02 03', 10), mn, row('truot4'), mnCtx).totalHits, 0); // thiếu số
      expect(entryDetail(entry('01 01 03 04', 10), mn, row('truot4'), mnCtx).totalHits, 0); // trùng số
      expect(entryDetail(entry('01 02 03 04', 10), null, row('truot4'), mnCtx).totalHits, 0);
    });
    test('tài/xỉu và chẵn/lẻ theo đuôi giải đặc biệt', () {
      // MN đặc biệt 123456 -> đuôi 56: Tài, chẵn
      expect(entryDetail(entry('tai', 5), mn, row('tai_xiu'), mnCtx).totalHits, 1);
      expect(entryDetail(entry('xiu', 5), mn, row('tai_xiu'), mnCtx).totalHits, 0);
      expect(entryDetail(entry('chan', 5), mn, row('chan_le'), mnCtx).totalHits, 1);
      expect(entryDetail(entry('le', 5), mn, row('chan_le'), mnCtx).totalHits, 0);
      // MB đặc biệt 70002 -> đuôi 02: Xỉu, chẵn
      expect(entryDetail(entry('xiu', 5), mb, row('tai_xiu', 'mb'), const ScoreCtx(region: 'mb')).totalHits, 1);
      // each valid token is a bet; aliases and accents; a word of the other kind is ignored
      final d = entryDetail(entry('T Tài x tai le', 5), mn, row('tai_xiu'), mnCtx);
      expect(d.bets, ['tai', 'tai', 'xiu', 'tai']);
      expect(d.lots, 4);
      expect(d.totalHits, 3);
      expect(entryDetail(entry('t', 5), null, row('tai_xiu'), mnCtx).totalHits, 0);
    });
    test('đầu Nam/Trung = giải tám; đuôi = 2 số cuối giải đặc biệt', () {
      expect(hits(entryDetail(entry('20', 5), mn, row('dau'), mnCtx)), '20:1');
      expect(hits(entryDetail(entry('56', 5), mn, row('duoi'), mnCtx)), '56:1');
      expect(hits(entryDetail(entry('20', 5), mn, row('duoi'), mnCtx)), '20:0');
    });
    test('đầu ở đài Bắc: khách Bắc/chưa chọn = giải nhất (1 lô); khách Nam/Trung = 4 giải bảy, tiền xác ×4', () {
      final bac = entryDetail(entry('20', 1), mb, row('dau', 'mb'), const ScoreCtx(region: 'mb', customerRegion: 'mb'));
      expect(hits(bac), '20:1');
      expect(bac.stakeFactor, 1);
      final chua = entryDetail(entry('20', 1), mb, row('dau', 'mb'), const ScoreCtx(region: 'mb'));
      expect(chua.stakeFactor, 1);
      final nam = entryDetail(entry('20', 1), mb, row('dau', 'mb'), const ScoreCtx(region: 'mb', customerRegion: 'mn'));
      expect(hits(nam), '20:1');
      expect(nam.stakeFactor, 4);
    });
    test('3 càng / 4 càng chỉ so giải đặc biệt', () {
      expect(hits(entryDetail(entry('456', 2), mn, row('cang3'), mnCtx)), '456:1');
      expect(hits(entryDetail(entry('3456', 2), mn, row('cang4'), mnCtx)), '3456:1');
      expect(hits(entryDetail(entry('123', 2), mn, row('cang3'), mnCtx)), '123:0');
    });
    test('xiên thật: trúng khi CẢ các số cùng về, và chỉ tính một lần', () {
      expect(entryDetail(entry('20 56', 10), mn, row('xien2'), mnCtx).totalHits, 1); // 20 (nhiều lô) và 56 cùng về
      expect(entryDetail(entry('20 99', 10), mn, row('xien2'), mnCtx).totalHits, 0);
      expect(entryDetail(entry('20 56 34', 10), mn, row('xien3'), mnCtx).totalHits, 1);
      // wrong count of numbers, repeated number, no result
      expect(entryDetail(entry('20', 10), mn, row('xien2'), mnCtx).totalHits, 0);
      expect(entryDetail(entry('20 20', 10), mn, row('xien2'), mnCtx).totalHits, 0);
      expect(entryDetail(entry('20 56', 10), null, row('xien2'), mnCtx).totalHits, 0);
    });
    test('kiểu đánh khác (custom) và dòng cũ vẫn dùng luật tiers + digits', () {
      final custom = makeRow(kind: 'custom', price: 1000, payout: 80000, tiers: ['dacBiet'], digits: 3);
      expect(hits(entryDetail(entry('456', 1), mn, custom, mnCtx)), '456:1');
      final legacy = {'rate': 70, 'tiers': ['giaiNhat'], 'digits': 2};
      expect(hits(entryDetail(entry('78', 1), mn, legacy, mnCtx)), '78:1');
    });
  });

  group('money', () {
    test('tiền xác = điểm × giá tiền; trúng = lần trúng × điểm × giá trúng; lợi nhuận = xác - trúng', () {
      // bao lô Nam 30 điểm số 20: về 5 lần. xác = 30 × 12.600 = 378.000; trúng = 5 × 30 × 70.000 = 10.500.000
      final s = run([entry('20', 30, betType: 'lo', station: 'mn-dongnai')], defaultRates, (d, st) => mn);
      expect(s.sentMoney, 378000);
      expect(s.wonMoney, 10500000);
      expect(s.remaining, 378000 - 10500000);
    });
    test('xiên 2: xác = điểm × 2 × giá tiền; trúng một lần = điểm × giá trúng', () {
      final rates = {...defaultRates, 'xien2@mn': makeRow(kind: 'xien2', price: 12600, payout: 1000000)};
      final s = run([entry('20 56', 10, betType: 'xien2', station: 'mn-dongnai')], rates, (d, st) => mn);
      expect(s.sentMoney, 10 * 2 * 12600);
      expect(s.wonMoney, 10 * 1000000);
      expect(s.won.single.hits, 1);
    });
    test('đầu đài Bắc, khách Nam/Trung: 1 điểm = 4.000đ', () {
      final s = run([entry('20', 3, betType: 'dau', station: 'mb')], defaultRates, (d, st) => mb, customerRegion: 'mn');
      expect(s.sentMoney, 3 * 4 * 1000);
      expect(s.wonMoney, 3 * 1 * 70000);
      // the same entry for a customer without a region: 1 lô
      final bac = run([entry('20', 3, betType: 'dau', station: 'mb')], defaultRates, (d, st) => mb);
      expect(bac.sentMoney, 3 * 1000);
      expect(bac.wonMoney, 3 * 70000);
    });
    test('lô trượt có cả phần tiền; tài/xỉu: xác = điểm × giá tiền × số lần đánh', () {
      final rates = {...defaultRates, 'truot4@mn': makeRow(kind: 'truot4', price: 12600, payout: 50000)};
      final s = run([entry('01 02 03 04', 10, betType: 'truot4', station: 'mn-dongnai')], rates, (d, st) => mn);
      expect(s.sentMoney, 10 * 4 * 12600);
      expect(s.wonMoney, 10 * 50000);
      final rates2 = {...defaultRates, 'tai_xiu@mn': makeRow(kind: 'tai_xiu', price: 12600, payout: 90000)};
      final t = run([entry('tai xiu', 2, betType: 'tai_xiu', station: 'mn-dongnai')], rates2, (d, st) => mn);
      expect(t.sentMoney, 2 * 2 * 12600);
      expect(t.wonMoney, 2 * 90000); // only "tai" is right
    });
    test('chưa có kết quả: tiền xác tính vào "chưa có kết quả", chưa có tiền trúng', () {
      final s = run([entry('20', 2, betType: 'duoi', station: 'mn-dongnai')], defaultRates, (d, st) => null);
      expect(s.pendingMoney, 2 * 1000);
      expect(s.wonMoney, 0);
      expect(s.settledMoney, 0);
    });
    test('cấu hình cũ (rate, unit, pointValue) vẫn tính như trước và hiện được trong bảng', () {
      final legacy = {
        'lo': {'rate': 20, 'tiers': allBaseTiers, 'digits': 2, 'unit': 'point', 'pointValue': 23000},
      };
      final s = run([entry('20', 1, betType: 'lo', station: 'mb')], legacy, (d, st) => mb);
      expect(s.sentMoney, 23000);
      expect(s.wonMoney, 1 * 20 * 23000 * 2); // giải nhất 11120 và giải bảy 20
      final t = toTableRow('lo', legacy['lo'])!;
      expect(t['price'], 23000);
      expect(t['payout'], 460000);
      expect(t['kind'], 'lo');
    });
    test('điểm ra của dòng mới = điểm × rate × số lần trúng (rate = giá trúng / giá tiền)', () {
      final d = entryDetail(entry('20', 10), mn, row('lo'), mnCtx);
      expect(d.out, closeTo(10 * (70000 / 12600) * 5, 1e-9));
    });
  });

  group('lấy số', () {
    Cfg withSource(String kind, Map<String, dynamic> source, [String region = 'mn']) => {...defaultRow(kind, region), 'source': source};

    test('lấy số tuỳ chỉnh: giải nào, vị trí đầu/cuối, bao nhiêu số, lô thứ mấy', () {
      // đầu của giải đặc biệt Nam 123456: 2 số đầu = "12"
      final head = withSource('duoi', {'tiers': ['dacBiet'], 'position': 'first', 'digits': 2});
      expect(hits(entryDetail(entry('12', 1), mn, head, mnCtx)), '12:1');
      expect(hits(entryDetail(entry('56', 1), mn, head, mnCtx)), '56:0');
      // 3 số cuối của giải đặc biệt và giải nhất (45678 -> 678)
      final two = withSource('cang3', {'tiers': ['dacBiet', 'giaiNhat'], 'position': 'last', 'digits': 3});
      expect(hits(entryDetail(entry('678', 1), mn, two, mnCtx)), '678:1');
      // chỉ lô thứ 2 của giải ba (23456 -> 56) trong khi lô thứ 1 là 12345
      final pick = withSource('duoi', {'tiers': ['giaiBa'], 'position': 'last', 'digits': 2, 'pick': [2]});
      expect(hits(entryDetail(entry('56', 1), mn, pick, mnCtx)), '56:1');
      expect(hits(entryDetail(entry('45', 1), mn, pick, mnCtx)), '45:0');
      // 4 số cuối của cả giải sáu (4 chữ số): "5678"
      final sau = withSource('lo4', {'tiers': ['giaiSau'], 'position': 'last', 'digits': 4});
      expect(hits(entryDetail(entry('5678', 1), mn, sau, mnCtx)), '5678:1');
      // đầu ở đài Bắc khi đã chỉnh lấy số thì không còn tự đổi theo miền của khách
      final custom = withSource('dau', {'tiers': ['giaiBay'], 'position': 'last', 'digits': 2}, 'mb');
      final d = entryDetail(entry('20', 1), mb, custom, const ScoreCtx(region: 'mb', customerRegion: 'mn'));
      expect(d.stakeFactor, 1);
      expect(hits(d), '20:1');
    });
    test('xiên / trượt dùng số chữ số của lấy số; thần tài lấy số đầu tiên đọc được', () {
      final x = withSource('xien2', {'tiers': ['dacBiet', 'giaiNhat'], 'position': 'last', 'digits': 3});
      expect(entryDetail(entry('456 678', 1), mn, x, mnCtx).totalHits, 1);
      expect(entryDetail(entry('456 111', 1), mn, x, mnCtx).totalHits, 0);
      // tài/xỉu on the first number read: the first prize (45678 -> 78 = tài); chẵn/lẻ on its last digit (8 = chẵn)
      final tx = withSource('tai_xiu', {'tiers': ['giaiNhat'], 'position': 'last', 'digits': 2});
      expect(entryDetail(entry('tai', 1), mn, tx, mnCtx).totalHits, 1);
      final cl = withSource('chan_le', {'tiers': ['giaiNhat'], 'position': 'last', 'digits': 1});
      expect(entryDetail(entry('chan', 1), mn, cl, mnCtx).totalHits, 1);
      expect(entryDetail(entry('le', 1), mn, cl, mnCtx).totalHits, 0);
      // lô thứ 2 of giải ba: 23456 -> last digit 6 chẵn; the 1st would be 12345 -> lẻ
      final c2 = withSource('chan_le', {'tiers': ['giaiBa'], 'position': 'last', 'digits': 1, 'pick': [1]});
      expect(entryDetail(entry('le', 1), mn, c2, mnCtx).totalHits, 1);
    });
    test('kind custom: có source đi đường mới, không có thì đường cũ', () {
      final viaSource = makeRow(kind: 'custom', price: 1000, payout: 80000, source: {'tiers': ['dacBiet'], 'position': 'first', 'digits': 3});
      expect(viaSource['tiers'], ['dacBiet']);
      expect(viaSource['digits'], 3);
      expect(hits(entryDetail(entry('123', 1), mn, viaSource, mnCtx)), '123:1');
      final legacy = makeRow(kind: 'custom', price: 1000, payout: 80000, tiers: ['dacBiet'], digits: 3);
      expect(hits(entryDetail(entry('123', 1), mn, legacy, mnCtx)), '123:0'); // last 3 = 456
      expect(hits(entryDetail(entry('456', 1), mn, legacy, mnCtx)), '456:1');
    });
    test('normalizeSource / defaultSource / effectiveSource / describeSource / sameSource', () {
      final n = normalizeSource({'tiers': ['dacBiet', 'zzz', 'dacBiet', 'giaiTam'], 'position': 'x', 'digits': 9, 'pick': [3, '1', 1, 0, 31, 'a']});
      expect(n, {'tiers': ['dacBiet', 'giaiTam'], 'position': 'last', 'digits': 6, 'pick': [1, 3]});
      expect(normalizeSource({'tiers': [], 'digits': 0})['digits'], 2);
      expect(defaultSource('lo', 'mn')['tiers'], hasLength(9)); // + giải tám
      expect(defaultSource('lo', 'mb')['tiers'], hasLength(8));
      expect(defaultSource('lo3', 'mb')['digits'], 3);
      expect(defaultSource('lo4', 'mn')['digits'], 4);
      expect(defaultSource('dau', 'mb')['tiers'], ['giaiNhat']);
      expect(defaultSource('dau', 'mt')['tiers'], ['giaiTam']);
      expect(defaultSource('chan_le', 'mn')['digits'], 1);
      expect(defaultSource('tai_xiu', 'mn')['digits'], 2);
      expect(defaultSource('cang4', 'mn')['tiers'], ['dacBiet']);
      expect(defaultSource('custom', 'mn', {'tiers': ['giaiNhat'], 'digits': 3}), {'tiers': ['giaiNhat'], 'position': 'last', 'digits': 3});
      expect(effectiveSource(defaultRow('duoi'), 'duoi', 'mb'), defaultSource('duoi'));
      expect(describeSource(defaultSource('lo', 'mb')), '2 số cuối của cả 27 lô');
      expect(describeSource(defaultSource('lo', 'mn'), 'mn'), '2 số cuối của cả 18 lô');
      expect(describeSource({'tiers': ['dacBiet', 'giaiNhat'], 'position': 'first', 'digits': 3, 'pick': [1, 2]}), '3 số đầu của giải đặc biệt, giải nhất (lô thứ 1, 2)');
      expect(sameSource({'tiers': ['dacBiet']}, {'tiers': ['dacBiet'], 'position': 'last', 'digits': 2}), isTrue);
      expect(sameSource({'tiers': ['dacBiet']}, {'tiers': ['giaiNhat']}), isFalse);
      expect(sourceFields('xien3').position, isFalse);
      expect(sourceFields('lo').pick, isTrue);
    });
    test('sameConfig so cả source', () {
      final a = makeRow(kind: 'duoi', price: 1000, payout: 70000, source: {'tiers': ['dacBiet'], 'position': 'first', 'digits': 2});
      expect(sameConfig(a, makeRow(kind: 'duoi', price: 1000, payout: 70000, source: {'tiers': ['dacBiet'], 'position': 'first'})), isTrue);
      expect(sameConfig(a, makeRow(kind: 'duoi', price: 1000, payout: 70000)), isFalse);
    });
  });

  group('config', () {
    test('mặc định khớp backend: 15 kiểu × 3 miền', () {
      expect(defaultRates.length, 45);
      expect(defaultRates.keys, contains('chan_le@mn'));
      Map r(String k) => defaultRates[k] as Map;
      List pp(String k) => [r(k)['price'], r(k)['payout']];
      expect(pp('lo@mb'), [21600, 70000]);
      expect(pp('lo@mt'), [12600, 70000]);
      expect(pp('lo3@mb'), [18400, 0]);
      expect(pp('lo3@mn'), [11900, 0]);
      expect(pp('lo4@mb'), [16000, 0]);
      expect(pp('lo4@mn'), [11200, 0]);
      expect(r('lo3@mn')['digits'], 3);
      expect(r('lo4@mn')['digits'], 4);
      expect(r('lo3@mn')['tiers'], hasLength(8));
      expect(pp('dau@mn'), [1000, 70000]);
      expect(r('dau@mb')['tiers'], ['giaiNhat']);
      expect(r('dau@mt')['tiers'], ['giaiTam']);
      expect(pp('duoi@mb'), [1000, 70000]);
      expect(pp('cang3@mn'), [12600, 500000]);
      expect(pp('cang4@mn'), [12600, 5000000]);
      for (final k in ['xien2', 'xien3', 'xien4', 'truot4', 'truot8', 'truot10', 'tai_xiu', 'chan_le']) {
        expect(pp('$k@mn'), [12600, 0], reason: k);
        expect(pp('$k@mb'), [21600, 0], reason: k);
      }
      expect(r('truot8@mn')['tiers'], hasLength(8));
      expect(r('tai_xiu@mn')['tiers'], ['dacBiet']);
      expect(kindSource('lo', 'mb'), '2 số cuối của cả 27 lô');
      expect(kindSource('lo3', 'mn'), '3 số cuối của 17 lô có từ 3 chữ số');
      expect(kindSource('dau', 'mn'), 'Giải tám (2 số)');
      expect(kindSource('dau', 'mb'), contains('Khách Bắc'));
      expect(kindSource('truot8', 'mt'), 'Cả 8 cặp số đều không về trong 18 lô, tiền xác × 8');
    });
    test('mỗi dòng mới mang cả các trường cũ', () {
      final r = makeRow(kind: 'lo', price: 12600, payout: 70000);
      expect(r['unit'], 'point');
      expect(r['pointValue'], 12600);
      expect(r['rate'], closeTo(70000 / 12600, 1e-12));
      expect(r['tiers'], hasLength(8));
      expect(r['digits'], 2);
      expect(makeRow(kind: 'cang3', price: 1, payout: 1)['digits'], 3);
      expect(makeRow(kind: 'cang4', price: 1, payout: 1)['digits'], 4);
      expect(makeRow(kind: 'duoi', price: 1, payout: 1)['tiers'], ['dacBiet']);
    });
    test('toTableRow: dòng cũ đơn vị tiền có giá tiền 1, giá trúng = rate', () {
      final t = toTableRow('de', {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2})!;
      expect(t['kind'], 'custom');
      expect(t['price'], 1);
      expect(t['payout'], 70);
      expect(toTableRow('lo', null), isNull);
      final kinded = defaultRow('lo', 'mb');
      expect(toTableRow('lo', kinded)!['price'], 21600);
    });
    test('sameConfig: dòng mới so kind + giá; custom so thêm số cuối và tập giải', () {
      expect(sameConfig(row('lo'), row('lo')), isTrue);
      expect(sameConfig(row('lo'), makeRow(kind: 'lo', price: 12600, payout: 70001)), isFalse);
      expect(sameConfig(row('lo'), row('dau')), isFalse);
      final a = makeRow(kind: 'custom', price: 1, payout: 2, tiers: ['dacBiet', 'giaiNhat'], digits: 2);
      expect(sameConfig(a, makeRow(kind: 'custom', price: 1, payout: 2, tiers: ['giaiNhat', 'dacBiet'], digits: 2)), isTrue);
      expect(sameConfig(a, makeRow(kind: 'custom', price: 1, payout: 2, tiers: ['dacBiet'], digits: 2)), isFalse);
      expect(sameConfig(a, makeRow(kind: 'custom', price: 1, payout: 2, tiers: ['dacBiet', 'giaiNhat'], digits: 3)), isFalse);
      // older rows
      final old = {'rate': 20, 'tiers': ['dacBiet'], 'digits': 2, 'unit': 'point', 'pointValue': 23000};
      expect(sameConfig(old, {...old}, 'lo'), isTrue);
      expect(sameConfig(old, {...old, 'pointValue': 1}, 'lo'), isFalse);
    });
    test('ký hiệu: parseSymbols, makeRow, sameConfig and kindSymbolsFor', () {
      expect(parseSymbols(' L, l;lo  lô,l '), ['L', 'l', 'lo', 'lô']);
      expect(parseSymbols(List.generate(20, (i) => 's$i').join(',')), hasLength(12));
      expect(defaultSymbols('lo'), ['L', 'l', 'lo', 'lô', 'x', 'X']);
      expect(defaultSymbols('nope'), isEmpty);
      final a = makeRow(kind: 'duoi', price: 1000, payout: 70000, symbols: ['cc']);
      expect(a['symbols'], ['cc']);
      expect(makeRow(kind: 'duoi', price: 1000, payout: 70000).containsKey('symbols'), isFalse);
      expect(sameConfig(a, makeRow(kind: 'duoi', price: 1000, payout: 70000)), isFalse);
      expect(sameConfig(a, makeRow(kind: 'duoi', price: 1000, payout: 70000, symbols: ['cc'])), isTrue);
      final customer = {'lo@mn': makeRow(kind: 'lo', price: 12600, payout: 70000, symbols: ['bl'])};
      final account = {...defaultRates, 'dau@mn': makeRow(kind: 'dau', price: 1000, payout: 70000, symbols: ['dd'])};
      expect(kindSymbolsFor(account, customer, 'mn'), {'lo': ['bl'], 'dau': ['dd']});
      expect(kindSymbolsFor(account, customer, 'mb'), isEmpty);
      expect(kindSymbolsFor(null, null), isEmpty);
    });
    test('dòng tài khoản đã xoá: typesIn / typesOf bỏ qua, effectiveConfig dùng mặc định có sẵn', () {
      final acc = {
        ...defaultRates,
        'lo3@mn': {'disabled': true},
        'tx@mn': makeRow(kind: 'custom', price: 1, payout: 2),
        'tx': {'disabled': true},
        'old': {'disabled': true},
      };
      expect(typesIn(acc, 'mn'), isNot(contains('lo3')));
      expect(typesIn(acc, 'mb'), contains('lo3'));
      expect(typesIn(acc, 'mn'), contains('tx')); // the region's own value wins over a shared marker
      expect(typesIn(acc, 'mt'), isNot(contains('tx')));
      expect(typesIn(acc, 'mt'), isNot(contains('old')));
      expect(typesOf(acc), isNot(contains('old')));
      expect(effectiveConfig(acc, null, 'lo3', 'mn')['price'], 11900); // built-in default of the kind
      expect(effectiveConfig(acc, null, 'lo3', 'mb')['price'], 18400);
      expect(effectiveConfig(acc, null, 'old', 'mn'), fallbackDe);
      // entries already saved with the removed row are still scored
      final s = run([entry('020', 1, betType: 'lo3', station: 'mn-dongnai')], acc, (d, st) => mn);
      expect(s.sentMoney, 11900);
    });
    test('sameConfig so cả tên và nhóm', () {
      final a = makeRow(kind: 'custom', price: 1, payout: 2, name: 'A', group: 'de');
      expect(sameConfig(a, makeRow(kind: 'custom', price: 1, payout: 2, name: 'A', group: 'de')), isTrue);
      expect(sameConfig(a, makeRow(kind: 'custom', price: 1, payout: 2, name: 'B', group: 'de')), isFalse);
      expect(sameConfig(a, makeRow(kind: 'custom', price: 1, payout: 2, name: 'A')), isFalse);
      expect(a['group'], 'de');
    });
    test('effectiveConfig: dòng riêng của miền thắng, khách tắt dòng thì theo cấu hình mặc định', () {
      final customer = {'lo@mn': makeRow(kind: 'lo', price: 10000, payout: 60000), 'duoi@mn': {'disabled': true}};
      expect(effectiveConfig(defaultRates, customer, 'lo', 'mn')['price'], 10000);
      expect(effectiveConfig(defaultRates, customer, 'lo', 'mt')['price'], 12600);
      expect(effectiveConfig(defaultRates, customer, 'duoi', 'mn')['price'], 1000);
      expect(effectiveConfig(defaultRates, null, 'lo', 'mb')['price'], 21600);
      expect(effectiveConfig(defaultRates, null, 'de', 'mb'), fallbackDe);
    });
  });
}
