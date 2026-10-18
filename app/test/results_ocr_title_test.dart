import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/results/lottery_columns.dart';

import 'scoring_fixtures.dart';

OcrWord w(String t, double x, double y) => OcrWord(t, x, y, x + 60, y + 24);

void main() {
  test('Miền Bắc: the title row "XSMB 18 10 2026" does not take prize slots', () {
    final words = [
      w('18', 100, 0),
      w('10', 180, 0),
      w('2026', 260, 0),
      w('38115', 300, 60), // đặc biệt
      w('97733', 300, 110),
      w('7663', 90, 160),
      w('85', 100, 210),
    ];
    final text = orderedDigitText(words);
    expect(text.startsWith('38115'), isTrue);
    final form = <String, List<String>>{'dacBiet': [''], 'giaiNhat': [''], 'giaiTu': ['', '', '', ''], 'giaiBay': ['', '', '', '']};
    guessNorthForm(text, form);
    expect(form['giaiTu']!.first, '7663');
    expect(form['giaiBay']!.first, '85');
  });

  test('a photo without any 5-digit number keeps every row', () {
    expect(orderedDigitText([w('18', 0, 0), w('7663', 0, 50)]), '18 7663');
  });

  test('the region needs the whole word in the title area', () {
    final title = [w('XSMT', 0, 0), w('09/10/2026', 100, 0), w('48', 0, 400), w('xsmn', 0, 600)];
    expect(regionFromTitle(title), 'mt');
    expect(regionFromTitle([w('Hôm', 0, 0), w('48', 0, 300), w('XSMN', 0, 600)]), isNull); // only in the footer
    expect(regionFromTitle([w('MYXSMTX', 0, 0), w('48', 0, 600)]), isNull); // not a whole token
  });

  test('an impossible OCR date (31/02) is not used', () {
    final words = [w('31/02/2026', 0, 0)];
    expect(parseColumns(words, testStations()).date, isNull);
  });
}
