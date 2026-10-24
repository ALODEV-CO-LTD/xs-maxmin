import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/results/lottery_columns.dart';

import 'scoring_fixtures.dart';

OcrWord w(String text, double cx, double cy, {double width = 60}) =>
    OcrWord(text, cx - width / 2, cy - 10, cx + width / 2, cy + 10);

// ---- Miền Bắc: the printed table plus other things in the same photo -------------------------------------------------------
const _north = <List<String>>[
  ['38115'],
  ['97733'],
  ['21143', '52941'],
  ['12914', '26998', '10224'],
  ['63551', '85741', '77963'],
  ['7663', '1599', '9528', '3603'],
  ['6707', '5085', '3629'],
  ['5755', '2682', '1939'],
  ['455', '297', '980'],
  ['85', '67', '16', '92'],
];

List<OcrWord> _tableAt(double top) => [
  for (var r = 0; r < _north.length; r++)
    for (var c = 0; c < _north[r].length; c++)
      w(
        _north[r][c],
        150.0 + c * (600.0 / _north[r].length) + 300 / _north[r].length,
        top + r * 40,
      ),
];

Map<String, List<String>> _blank() => {
  'dacBiet': [''],
  'giaiNhat': [''],
  'giaiNhi': ['', ''],
  'giaiBa': List.filled(6, ''),
  'giaiTu': List.filled(4, ''),
  'giaiNam': List.filled(6, ''),
  'giaiSau': List.filled(3, ''),
  'giaiBay': List.filled(4, ''),
};

Map<String, List<String>> _read(List<OcrWord> words) {
  final form = _blank();
  guessNorthForm(orderedDigitText(words), form);
  return form;
}

void main() {
  final clean = _read(_tableAt(200));

  test('Miền Bắc: the plain table reads as before', () {
    expect(clean['dacBiet'], ['38115']);
    expect(clean['giaiNhat'], ['97733']);
    expect(clean['giaiNhi'], ['21143', '52941']);
    expect(clean['giaiBay'], ['85', '67', '16', '92']);
  });

  test('Miền Bắc: title, draw code, phone number and a lô tô table around the table change nothing', () {
    final words = [
      w(
        '54321',
        400,
        20,
      ), // a 5-digit draw / ticket code in the header, above the đặc biệt
      w('18', 300, 60),
      w('10', 360, 60),
      w('2026', 430, 60),
      w('77', 400, 100), // two 2-digit numbers of the header line
      w('12', 460, 100),
      ..._tableAt(200),
      // under the table: a lô tô summary (heads and tails), a phone number, the year and another 5-digit code
      for (var r = 0; r < 10; r++) ...[
        w('$r', 200, 640.0 + r * 30),
        w('${r}5', 300, 640.0 + r * 30),
        w('${r}8', 380, 640.0 + r * 30),
      ],
      w('09123', 600, 960),
      w('99999', 600, 1000),
    ];
    expect(_read(words), clean);
  });

  test('Miền Bắc: a stray number of the same length at the side of a row does not take a prize slot', () {
    final words = [
      ..._tableAt(200),
      w('44444', 900, 280),
      w('22', 900, 360),
      w('33', 960, 360),
    ]; // beside giải nhì and giải bảy
    expect(_read(words), clean);
  });

  // ---- Miền Nam / Miền Trung ------------------------------------------------------------------------------------------------
  OcrWord W(String t, double x, double y) => w(t, x, y);
  List<OcrWord> column(double x, int seed) {
    String num(int digits, int k) => (seed * 1000 + k * 37 + 11)
        .toString()
        .padLeft(digits, '0')
        .substring(0, digits);
    final out = <OcrWord>[];
    var k = 0;
    void add(int digits, double y) {
      k++;
      out.add(W(num(digits, k), x, y));
    }

    add(2, 100);
    add(3, 130);
    for (final y in [160.0, 190.0, 220.0]) {
      add(4, y);
    }
    add(4, 250);
    for (var i = 0; i < 7; i++) {
      add(5, 280.0 + i * 30);
    }
    for (final y in [490.0, 520.0]) {
      add(5, y);
    }
    add(5, 550);
    add(5, 580);
    add(6, 610);
    return out;
  }

  List<OcrWord> south({List<OcrWord> extra = const []}) => [
    W('Đồng', 170, 60),
    W('Nai', 230, 60),
    W('Cần', 470, 60),
    W('Thơ', 530, 60),
    W('Sóc', 770, 60),
    W('Trăng', 830, 60),
    for (var i = 0; i < 3; i++) ...column(200.0 + i * 300, i + 1),
    ...extra,
  ];

  test('Miền Nam: a clean 3-station table is complete', () {
    final p = parseColumns(south(), testStations());
    expect(p.columns.length, 3);
    expect(
      p.columns.every((c) => c.complete),
      isTrue,
      reason: p.columns.map((c) => c.issues).join(' | '),
    );
  });

  test('Miền Nam: footer rows under the table (lô tô, 2-digit numbers, a 6-digit code, a phone number) are not prizes', () {
    final extra = [
      for (var r = 0; r < 6; r++)
        for (var c = 0; c < 3; c++)
          W('${r}7', 200.0 + c * 300, 700.0 + r * 30), // a lô tô table below
      W('123456', 500, 900), // a 6-digit code in a footer
      W('0901234567', 500, 940),
      W('2026', 500, 980),
    ];
    final plain = parseColumns(south(), testStations());
    final p = parseColumns(south(extra: extra), testStations());
    expect(
      p.columns.length,
      3,
      reason: 'the footer code must not become a 4th special prize',
    );
    for (var i = 0; i < 3; i++) {
      expect(
        p.columns[i].complete,
        isTrue,
        reason: p.columns[i].issues.join(','),
      );
      expect(p.columns[i].values, plain.columns[i].values);
    }
  });

  test('Miền Nam: a 6-digit draw code in the header is not a column', () {
    final p = parseColumns([...south(), W('654321', 500, 30)], testStations());
    expect(p.columns.length, 3);
    expect(
      p.columns.every((c) => c.complete),
      isTrue,
      reason: p.columns.map((c) => c.issues).join(' | '),
    );
  });
}
