import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/results/lottery_columns.dart';

import 'scoring_fixtures.dart';

OcrWord w(String text, double cx, double cy, {double width = 60}) => OcrWord(text, cx - width / 2, cy - 10, cx + width / 2, cy + 10);

/// The OCR words of one column: tokens laid out like the printed table.
List<OcrWord> columnWords(double x, int seed, {Set<String> drop = const {}}) {
  String num(int digits, int k) => (seed * 1000 + k * 37 + 11).toString().padLeft(digits, '0').substring(0, digits);
  final out = <OcrWord>[];
  var k = 0;
  void add(String tier, int digits, double y) {
    k++;
    if (drop.contains('$tier:${y.toInt()}')) return;
    out.add(w(num(digits, k), x, y));
  }

  add('giaiTam', 2, 100);
  add('giaiBay', 3, 130);
  for (final y in [160.0, 190.0, 220.0]) {
    add('giaiSau', 4, y);
  }
  add('giaiNam', 4, 250);
  for (var i = 0; i < 7; i++) {
    add('giaiTu', 5, 280.0 + i * 30);
  }
  for (final y in [490.0, 520.0]) {
    add('giaiBa', 5, y);
  }
  add('giaiNhi', 5, 550);
  add('giaiNhat', 5, 580);
  add('dacBiet', 6, 610);
  return out;
}

List<OcrWord> titleWords() => [
      w('99999', 400, 5), // noise above the date line
      w('XSMN', 250, 20),
      w('Thứ', 330, 20),
      w('4', 380, 20),
      w('»', 410, 20),
      w('XSMN', 470, 20),
      w('07/10/2026', 580, 20, width: 110),
      w('2026', 700, 20), // a stray year: 4 digits that must not become a prize
    ];

void main() {
  _extraColumnTests();
  final st = testStations();
  const xs = [200.0, 500.0, 800.0];

  List<OcrWord> table({List<String> headers = const ['Đồng Nai', 'Cần Thơ', 'Sóc Trăng'], Map<int, Set<String>> drop = const {}}) => [
        ...titleWords(),
        for (var i = 0; i < 3; i++) ...[
          for (final (j, part) in headers[i].split(' ').indexed) if (part.isNotEmpty) w(part, xs[i] - 30 + j * 50, 60),
          ...columnWords(xs[i], i + 1, drop: drop[i] ?? const {}),
        ],
      ];

  test('a prize that looks like a year (2052) must not cut away the rows above it', () {
    // Vĩnh Long / Bình Dương / Trà Vinh photo without any title: Bình Dương's first 6th-prize number is "2052"
    final cols = [
      ['73', '146', '5360', '2815', '6283', '5214', '14220', '92710', '07252', '03703', '20758', '27029', '12926', '52437', '37278', '06581', '78961', '411227'],
      ['75', '838', '2052', '5358', '0033', '2129', '22657', '78872', '99561', '37045', '95520', '84016', '37139', '75935', '31234', '82353', '11152', '962651'],
      ['07', '714', '9964', '9486', '0272', '1370', '09732', '05315', '62014', '47278', '39003', '04156', '08477', '91109', '22196', '02853', '03625', '855406'],
    ];
    final names = [['Vĩnh', 'Long'], ['Bình', 'Dương'], ['Trà', 'Vinh']];
    final words = [
      for (var i = 0; i < 3; i++) ...[
        for (final (j, n) in names[i].indexed) w(n, xs[i] - 30 + j * 60, 30),
        for (final (r, v) in cols[i].indexed) w(v, xs[i], 80 + r * 30.0),
      ],
    ];
    final p = parseColumns(words, st);
    expect(p.columns.length, 3);
    for (final (i, c) in p.columns.indexed) {
      expect(c.issues, isEmpty);
      expect(c.complete, isTrue);
      expect(c.values['giaiTam'], [cols[i][0]]);
      expect(c.values['giaiBay'], [cols[i][1]]);
      expect(c.values['giaiSau'], cols[i].sublist(2, 5));
    }
  });

  test('parses a 3-station table: columns, prizes in table order, title digits ignored', () {
    final p = parseColumns(table(), st);
    expect(p.columns.length, 3);
    expect(p.date, '2026-10-07');
    for (final c in p.columns) {
      expect(c.complete, isTrue, reason: c.issues.join(','));
      expect(c.values['giaiTam']!.length, 1);
      expect(c.values['giaiBay']!.length, 1);
      expect(c.values['giaiSau']!.length, 3);
      expect(c.values['giaiNam']!.length, 1);
      expect(c.values['giaiTu']!.length, 7);
      expect(c.values['giaiBa']!.length, 2);
      expect(c.values['giaiNhi']!.length, 1);
      expect(c.values['giaiNhat']!.length, 1);
      expect(c.values['dacBiet']!.length, 1);
      expect(c.values['giaiTam']!.single.length, 2);
      expect(c.values['giaiBay']!.single.length, 3);
      expect(c.values['giaiSau']!.every((v) => v.length == 4), isTrue);
      expect(c.values['giaiTu']!.every((v) => v.length == 5), isTrue);
      expect(c.values['dacBiet']!.single.length, 6);
      // nothing from the title leaked in
      final every = c.values.values.expand((l) => l);
      expect(every, isNot(contains('2026')));
      expect(every, isNot(contains('99999')));
    }
    // columns are ordered left to right and numbers come from the right column
    expect(p.columns[0].x < p.columns[1].x && p.columns[1].x < p.columns[2].x, isTrue);
    final firstTu = columnWords(200, 1).where((x) => x.text.length == 5).map((x) => x.text).toList();
    expect(p.columns[0].values['giaiTu'], firstTu.sublist(0, 7)); // G4 x7 top down
    expect(p.columns[0].values['giaiBa'], firstTu.sublist(7, 9)); // then G3 x2
    expect(p.columns[0].values['giaiNhi'], [firstTu[9]]);
    expect(p.columns[0].values['giaiNhat'], [firstTu[10]]);
  });

  test('G6 are the first three 4-digit numbers, G5 the fourth', () {
    final p = parseColumns(table(), st);
    final fours = columnWords(500, 2).where((x) => x.text.length == 4).map((x) => x.text).toList();
    expect(p.columns[1].values['giaiSau'], fours.sublist(0, 3));
    expect(p.columns[1].values['giaiNam'], [fours[3]]);
  });

  test('station names are matched from the header', () {
    final p = parseColumns(table(), st);
    expect(p.columns.map((c) => c.station), ['mn-dongnai', 'mn-cantho', 'mn-soctrang']);
    assignStations(p.columns, ['mn-dongnai', 'mn-cantho', 'mn-soctrang'], st);
    expect(p.columns.map((c) => c.station), ['mn-dongnai', 'mn-cantho', 'mn-soctrang']);
    expect(p.columns.every((c) => c.source == 'tiêu đề'), isTrue);
  });

  test('garbled headers still match fuzzily and the left-over columns follow the page order', () {
    final p = parseColumns(table(headers: ['Dong Nal', '', 'Soc Trang']), st);
    // the middle header is unreadable
    assignStations(p.columns, ['mn-dongnai', 'mn-cantho', 'mn-soctrang'], st);
    expect(p.columns.map((c) => c.station), ['mn-dongnai', 'mn-cantho', 'mn-soctrang']);
    expect(p.columns[1].source, 'theo thứ tự');
  });

  test('without any header the stations are taken in page order', () {
    final p = parseColumns(table(headers: ['', '', '']), st);
    assignStations(p.columns, ['mn-soctrang', 'mn-dongnai', 'mn-cantho'], st);
    expect(p.columns.map((c) => c.station), ['mn-soctrang', 'mn-dongnai', 'mn-cantho']);
  });

  test('a missing number is reported and the column is not complete', () {
    final p = parseColumns(table(drop: {1: {'giaiTu:340'}}), st);
    expect(p.columns[0].complete, isTrue);
    expect(p.columns[1].complete, isFalse);
    expect(p.columns[1].issues.single, '5 chữ số: đọc được 10/11');
    expect(p.columns[1].values['giaiNhat']!.single, '');
    expect(p.columns[2].complete, isTrue);
  });

  test('no 6-digit special prize -> no columns', () {
    expect(parseColumns([w('12', 100, 100), w('123', 100, 130)], st).columns, isEmpty);
  });

  test('foldText removes accents', () {
    expect(foldText('Thừa Thiên Huế'), 'thua thien hue');
    expect(foldText('ĐỒNG  NAI!'), 'dong nai');
    expect(matchStation('XSMN Cần Thơ', st), 'mn-cantho');
    expect(matchStation('TP HCM', st), 'mn-tphcm');
    expect(matchStation('', st), isNull);
  });

  test('Miền Bắc photo: digit-only words fill the empty boxes in order', () {
    final form = {
      'dacBiet': [''],
      'giaiNhat': [''],
      'giaiNhi': ['', ''],
      'giaiBa': List.filled(6, ''),
      'giaiTu': List.filled(4, ''),
      'giaiNam': List.filled(6, ''),
      'giaiSau': List.filled(3, ''),
      'giaiBay': List.filled(4, ''),
    };
    final five = ['10001', '20002', '30003', '30004', '40001', '40002', '40003', '40004', '40005', '40006'];
    final four = List.generate(10, (i) => '${1000 + i}');
    const text = 'ĐB 13GH 2026 hello';
    guessNorthForm('$text ${five.join(' ')} ${four.join(' ')} 111 222 333 44 55 66 77', form);
    expect(form['dacBiet'], ['10001']);
    expect(form['giaiNhi'], ['30003', '30004']);
    expect(form['giaiBa'], ['40001', '40002', '40003', '40004', '40005', '40006']);
    expect(form['giaiTu'], ['2026', '1000', '1001', '1002']); // the year is noise the user reviews (as on the web)
    expect(form['giaiSau'], ['111', '222', '333']);
    expect(form['giaiBay'], ['44', '55', '66', '77']);
    // a second reading does not overwrite what is there
    guessNorthForm('99999', form);
    expect(form['dacBiet'], ['10001']);
  });
}

// A stray "/" read from a table line below the title must not swallow the first prize rows, and a column with exactly
// 18 numbers is placed by position even when one number lost a digit.
void _extraColumnTests() {
  group('parseColumns robustness', () {
    List<OcrWord> table({bool strayLine = false, bool lostDigit = false}) {
      const seq = [2, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6];
      final words = <OcrWord>[const OcrWord('07/10/2026', 10, 5, 120, 25)];
      for (var c = 0; c < 3; c++) {
        for (var r = 0; r < seq.length; r++) {
          var t = List.generate(seq[r], (i) => '${(c + r + i) % 10}').join();
          if (lostDigit && c == 1 && r == 8) t = t.substring(0, 4);
          words.add(OcrWord(t, 100.0 + c * 200, 100.0 + r * 40, 160.0 + c * 200, 130.0 + r * 40));
        }
      }
      if (strayLine) words.add(const OcrWord('/', 30, 400, 40, 430)); // a table border read as a slash, mid-table
      return words;
    }

    test('stray slash below the title does not hide rows', () {
      final p = parseColumns(table(strayLine: true), testStations());
      expect(p.columns.length, 3);
      expect(p.columns.every((c) => c.complete), isTrue);
    });

    test('exactly 18 numbers: positional, wrong-length cell flagged without shifting', () {
      final p = parseColumns(table(lostDigit: true), testStations());
      final c = p.columns[1];
      expect(c.complete, isFalse);
      expect(c.issues.length, 1);
      expect(c.values['giaiTu']![2], hasLength(4));
      expect(c.values['giaiTu']!.length, 7);
      expect(c.values['giaiBa']!.length, 2);
      expect(p.columns[0].complete, isTrue);
    });
  });
}
