import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/scoring_config.dart';

void main() {
  test('effectiveConfig: customer region value wins, then customer, then account', () {
    final account = {
      'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2},
      'de@mn': {'rate': 80, 'tiers': ['dacBiet'], 'digits': 2},
    };
    final customer = {
      'de': {'rate': 75, 'tiers': ['dacBiet'], 'digits': 2},
    };
    expect(effectiveConfig(account, customer, 'de', 'mb')['rate'], 75);
    expect(effectiveConfig(account, null, 'de', 'mn')['rate'], 80);
    expect(effectiveConfig(account, null, 'de', 'mb')['rate'], 70);
    expect(effectiveConfig(account, {'de': {'disabled': true}}, 'de', 'mb')['rate'], 70);
  });

  test('typesIn: shared plus region-only types', () {
    final rates = {'de': {}, 'lo': {}, 'xiu@mn': {}};
    expect(typesIn(rates, 'mn'), ['de', 'lo', 'xiu']);
    expect(typesIn(rates, 'mb'), ['de', 'lo']);
  });
}
