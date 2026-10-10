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
}
