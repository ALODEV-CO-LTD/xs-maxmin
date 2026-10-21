import 'package:server/src/scoring_rates.dart';
import 'package:test/test.dart';

void main() {
  const cfg = {'rate': 3.5, 'tiers': ['dacBiet'], 'digits': 2, 'unit': 'point', 'pointValue': 23000};

  test('a rates map accepts `type` and `type@region` keys, with unit and point value', () {
    final (map, error) = normalizeRatesMap({'lo': cfg, 'lo@mn': {...cfg, 'rate': 5}, 'de@mb': cfg});
    expect(error, isNull);
    expect(map!.keys, containsAll(['lo', 'lo@mn', 'de@mb']));
    expect(map['lo@mn']['rate'], 5);
    expect(map['lo']['unit'], 'point');
    expect(map['lo']['pointValue'], 23000);
  });

  test('unknown regions and odd keys are refused', () {
    expect(normalizeRatesMap({'lo@xx': cfg}).$2, isNotNull);
    expect(normalizeRatesMap({'lo@': cfg}).$2, isNotNull);
    expect(normalizeRatesMap({'@mn': cfg}).$2, isNotNull);
    expect(normalizeRatesMap({'a b': cfg}).$2, isNotNull);
  });

  test('disabled markers only where allowed (per-customer overrides)', () {
    expect(normalizeRatesMap({'de@mn': {'disabled': true}}).$2, isNotNull);
    final (map, error) = normalizeRatesMap({'de@mn': {'disabled': true}}, allowDisabled: true);
    expect(error, isNull);
    expect(map!['de@mn'], {'disabled': true});
  });

  test('eighth prize is a valid tier; a bad rate or empty tiers are refused', () {
    expect(normalizeRateEntry({...cfg, 'tiers': ['giaiTam']}), isNotNull);
    expect(normalizeRateEntry({...cfg, 'rate': 0}), isNull);
    expect(normalizeRateEntry({...cfg, 'tiers': []}), isNull);
  });

  test('table rows (kind + price + payout): accepted, legacy fields derived, bad values refused', () {
    final n = normalizeRateEntry({'kind': 'lo', 'price': 12600, 'payout': 70000})!;
    expect(n['kind'], 'lo');
    expect(n['pointValue'], 12600);
    expect(n['unit'], 'point');
    expect((n['rate'] as num) * 12600, closeTo(70000, 0.001));
    expect(normalizeRateEntry({'kind': 'xien2', 'price': 12600, 'payout': 0}), isNotNull); // payout not set yet
    expect(normalizeRateEntry({'kind': 'lo', 'price': 0, 'payout': 1}), isNull);
    expect(normalizeRateEntry({'kind': 'lo', 'price': 1, 'payout': -1}), isNull);
    expect(normalizeRateEntry({'kind': 'nope', 'price': 1, 'payout': 1}), isNull);
    final (map, error) = normalizeRatesMap(defaultTableRates());
    expect(error, isNull);
    expect(map!['lo@mb']['price'], 21600);
    expect(map['dau@mb']['tiers'], ['giaiNhat']);
    expect(map['dau@mn']['tiers'], ['giaiTam']);
    expect(map['cang3@mt']['payout'], 500000);
    expect(map['lo3@mb']['digits'], 3);
    expect(map['lo3@mn']['price'], 11900);
    expect(map['truot8@mn']['payout'], 350000); // demo placeholder
    expect(map.keys.where((k) => k.endsWith('@mb')).length, 15);
  });

  test('ký hiệu của dòng bảng: giữ danh sách hợp lệ, bỏ ký hiệu có khoảng trắng hoặc quá dài', () {
    final n = normalizeRateEntry({'kind': 'lo', 'price': 12600, 'payout': 70000, 'symbols': ['bl', ' L ', 'a b', 'quadailongsymbol', 'bl']})!;
    expect(n['symbols'], ['bl', 'L']);
    expect(normalizeRateEntry({'kind': 'lo', 'price': 1, 'payout': 1, 'symbols': []})!.containsKey('symbols'), isFalse);
  });

  test('tài khoản có thể xoá một dòng bằng dấu {disabled: true}; dòng tuỳ chỉnh giữ nhóm và tên', () {
    final (map, error) = normalizeRatesMap({'xien4@mn': {'disabled': true}, 'lo@mn': {'kind': 'lo', 'price': 12600, 'payout': 70000}}, allowDisabled: true);
    expect(error, isNull);
    expect(map!['xien4@mn'], {'disabled': true});
    final c = normalizeRateEntry({'kind': 'custom', 'price': 1000, 'payout': 5000, 'name': 'Đầu 3', 'group': 'de', 'tiers': ['dacBiet']})!;
    expect(c['group'], 'de');
    expect(c['name'], 'Đầu 3');
    expect(normalizeRateEntry({'kind': 'custom', 'price': 1, 'payout': 1, 'group': 'nope'})!.containsKey('group'), isFalse);
  });

  test('lấy số: giải, vị trí đầu/cuối, số chữ số, lô thứ - giữ danh sách hợp lệ, sai thì từ chối', () {
    final n = normalizeRateEntry({
      'kind': 'duoi', 'price': 1000, 'payout': 70000,
      'source': {'tiers': ['dacBiet', 'giaiNhat', 'bogus'], 'position': 'first', 'digits': 3, 'pick': [2, 1, 2, 99]},
    })!;
    expect(n['source'], {'tiers': ['dacBiet', 'giaiNhat'], 'position': 'first', 'digits': 3, 'pick': [1, 2]});
    expect(n['digits'], 3);
    expect(normalizeRateEntry({'kind': 'duoi', 'price': 1, 'payout': 1, 'source': {'tiers': ['bogus']}}), isNull);
    expect(normalizeRateEntry({'kind': 'duoi', 'price': 1, 'payout': 1, 'source': {'tiers': ['dacBiet'], 'digits': 99}})!['source']['digits'], 2);
  });

  // The SAME table is asserted in app/test/default_rates_test.dart and web-next/tests/defaultRates.test.mjs: the defaults of
  // every kind must be identical in the backend, the app and the web. [kind, price Bắc, payout Bắc, price Nam/Trung, payout Nam/Trung]
  test('default table rates: every kind has a price and a payout, identical in all three code bases', () {
    final map = defaultTableRates();
    const table = [
    ['lo', 21600, 70000, 12600, 70000],
    ['lo3', 18400, 500000, 11900, 500000],
    ['lo4', 16000, 5000000, 11200, 5000000],
    ['dau', 1000, 70000, 1000, 70000],
    ['duoi', 1000, 70000, 1000, 70000],
    ['cang3', 12600, 500000, 12600, 500000],
    ['cang4', 12600, 5000000, 12600, 5000000],
    ['xien2', 21600, 430000, 12600, 250000],
    ['xien3', 21600, 2590000, 12600, 1500000],
    ['xien4', 21600, 8640000, 12600, 5000000],
    ['truot4', 21600, 225000, 12600, 90000],
    ['truot8', 21600, 1350000, 12600, 350000],
    ['truot10', 21600, 2800000, 12600, 630000],
    ['tai_xiu', 1000, 1900, 1000, 1900],
    ['chan_le', 1000, 1900, 1000, 1900],
    ];
    for (final r in table) {
      expect([map['${r[0]}@mb']['price'], map['${r[0]}@mb']['payout']], [r[1], r[2]], reason: '${r[0]} Bắc');
      for (final region in ['mt', 'mn']) {
        expect([map['${r[0]}@$region']['price'], map['${r[0]}@$region']['payout']], [r[3], r[4]], reason: '${r[0]} $region');
      }
    }
  });
}
