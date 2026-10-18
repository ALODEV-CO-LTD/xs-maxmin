import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/number_text.dart';
import 'package:mamba_app/features/account/stats_logic.dart' as stats;
import 'package:mamba_app/features/entries/entry_model.dart' as em;
import 'package:mamba_app/features/scoring/scoring_logic.dart';

void main() {
  test('normalizeNumberText', () {
    expect(normalizeNumberText('1,5'), '1.5');
    expect(normalizeNumberText('0,125'), '0.125');
    expect(normalizeNumberText('1,500'), '1500');
    expect(normalizeNumberText('1,500,000'), '1500000');
    expect(normalizeNumberText('1,234.5'), '1,234.5'.replaceAll(',', ''));
    expect(normalizeNumberText('-2,5'), '-2.5');
    expect(normalizeNumberText('100'), '100');
    expect(normalizeNumberText('abc,5'), 'abc,5');
  });

  test('toNumber treats a decimal comma as a decimal (no 10x error)', () {
    expect(toNumber('1,5'), 1.5);
    expect(toNumber('1,500'), 1500);
    expect(em.toNumber('1,5'), 1.5);
    expect(stats.toNumber('1,5'), 1.5);
    expect(toNumber('12.5'), 12.5);
  });
}
