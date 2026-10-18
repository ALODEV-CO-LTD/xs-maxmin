import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/results/lottery_columns.dart';

// The XSMB table of 08/08/2021 as the reader sees it: words with positions, handed over COLUMN by column (the order that
// used to scatter the prizes).
OcrWord w(String t, double x, double y) => OcrWord(t, x, y, x + 60, y + 24);

void main() {
  test('Miền Bắc photo: prizes follow the printed rows, whatever order the reader returns the words in', () {
    final rows = <List<(String, double)>>[
      [('38115', 300)],
      [('97733', 300)],
      [('21143', 150), ('52941', 450)],
      [('12914', 120), ('26998', 300), ('10224', 480)],
      [('63551', 120), ('85741', 300), ('77963', 480)],
      [('7663', 90), ('1599', 230), ('9528', 370), ('3603', 510)],
      [('6707', 120), ('5085', 300), ('3629', 480)],
      [('5755', 120), ('2682', 300), ('1939', 480)],
      [('455', 120), ('297', 300), ('980', 480)],
      [('85', 100), ('67', 250), ('16', 400), ('92', 550)],
    ];
    final words = <OcrWord>[];
    for (var r = 0; r < rows.length; r++) {
      for (final (t, x) in rows[r]) {
        words.add(w(t, x, 60.0 + r * 50 + (x % 7))); // a few pixels of jitter inside a row
      }
    }
    words
      ..add(w('1', 20, 160)) // row labels and the header are not prizes
      ..add(w('2', 20, 210))
      ..add(w('7', 20, 560));
    // column-major order, like the reader's blocks
    words.sort((a, b) => a.x0.compareTo(b.x0));

    final form = <String, List<String>>{
      'dacBiet': [''],
      'giaiNhat': [''],
      'giaiNhi': ['', ''],
      'giaiBa': List.filled(6, ''),
      'giaiTu': List.filled(4, ''),
      'giaiNam': List.filled(6, ''),
      'giaiSau': List.filled(3, ''),
      'giaiBay': List.filled(4, ''),
    };
    guessNorthForm(orderedDigitText(words), form);
    expect(form['dacBiet'], ['38115']);
    expect(form['giaiNhat'], ['97733']);
    expect(form['giaiNhi'], ['21143', '52941']);
    expect(form['giaiBa'], ['12914', '26998', '10224', '63551', '85741', '77963']);
    expect(form['giaiTu'], ['7663', '1599', '9528', '3603']);
    expect(form['giaiNam'], ['6707', '5085', '3629', '5755', '2682', '1939']);
    expect(form['giaiSau'], ['455', '297', '980']);
    expect(form['giaiBay'], ['85', '67', '16', '92']);
  });
}
