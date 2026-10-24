import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/results/lottery_columns.dart';

import 'scoring_fixtures.dart';

OcrWord w(String t, double x, double y) => OcrWord(t, x, y, x + 60, y + 24);

void main() {
  sideColumnTests();
  layoutTests();
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

void layoutTests() {
  // Layout of xskt.com.vn: đặc biệt .. giải bảy, plus a đầu / đuôi table on the right (1-digit numbers and "0,2,3" lists)
  // and a "Mã ĐB" footer.
  test('Miền Bắc: bảng có thêm bảng đầu / đuôi và mã ĐB bên cạnh', () {
    final words = [
      w('19640', 170, 100), w('0', 310, 100), w('5', 380, 100),
      w('50576', 170, 140), w('1', 310, 140), w('7', 380, 140),
      w('71187', 100, 180), w('68099', 220, 180), w('2', 310, 180), w('0,', 380, 180), w('2,', 395, 180), w('3', 410, 180),
      w('40352', 60, 215), w('53320', 130, 215), w('45756', 200, 215), w('3', 310, 215), w('6', 380, 215),
      w('74599', 60, 245), w('97405', 130, 245), w('47672', 200, 245), w('4', 310, 245),
      w('4336', 60, 280), w('4243', 130, 280), w('5099', 200, 280), w('3698', 270, 280), w('5', 310, 280),
      w('6988', 60, 315), w('6117', 130, 315), w('9223', 200, 315), w('6', 310, 315),
      w('2181', 60, 345), w('7486', 130, 345), w('3164', 200, 345), w('7', 310, 345),
      w('241', 80, 380), w('365', 160, 380), w('669', 240, 380), w('8', 310, 380),
      w('48', 60, 413), w('94', 130, 413), w('22', 200, 413), w('74', 270, 413), w('9', 310, 413),
      w('7ZY', 20, 440), w('8ZY', 80, 440),
    ];
    final form = <String, List<String>>{
      'dacBiet': [''], 'giaiNhat': [''], 'giaiNhi': ['', ''], 'giaiBa': List.filled(6, ''),
      'giaiTu': List.filled(4, ''), 'giaiNam': List.filled(6, ''), 'giaiSau': List.filled(3, ''), 'giaiBay': List.filled(4, ''),
    };
    guessNorthForm(orderedDigitText(words), form);
    expect(form['dacBiet'], ['19640']);
    expect(form['giaiBa'], ['40352', '53320', '45756', '74599', '97405', '47672']);
    expect(form['giaiNam'], ['6988', '6117', '9223', '2181', '7486', '3164']);
    expect(form['giaiBay'], ['48', '94', '22', '74']);
  });

  test('Miền Bắc: giải ba và giải năm in một hàng 6 số, nhãn "6 ô · 5 số" đọc "ô" thành chữ số', () {
    final words = [
      w('1', 10, 100), w('0', 40, 100), w('5', 70, 100), w('19640', 300, 100),
      w('1', 10, 140), w('50576', 300, 140),
      w('71187', 150, 180), w('68099', 500, 180), w('2', 10, 180), w('60', 40, 180),
      for (var i = 0; i < 6; i++) w(['40352', '53320', '45756', '74599', '97405', '47672'][i], 60 + i * 110, 220),
      w('60', 40, 220),
      w('4336', 100, 260), w('4243', 250, 260), w('5099', 400, 260), w('3698', 550, 260), w('40', 40, 260),
      for (var i = 0; i < 6; i++) w(['6988', '6117', '9223', '2181', '7486', '3164'][i], 60 + i * 110, 300),
      w('241', 100, 340), w('365', 300, 340), w('669', 500, 340), w('30', 40, 340),
      w('05', 100, 380), w('36', 250, 380), w('48', 400, 380), w('94', 550, 380), w('40', 40, 380),
    ];
    final form = <String, List<String>>{
      'dacBiet': [''], 'giaiNhat': [''], 'giaiNhi': ['', ''], 'giaiBa': List.filled(6, ''),
      'giaiTu': List.filled(4, ''), 'giaiNam': List.filled(6, ''), 'giaiSau': List.filled(3, ''), 'giaiBay': List.filled(4, ''),
    };
    guessNorthForm(orderedDigitText(words), form);
    expect(form['giaiNhi'], ['71187', '68099']);
    expect(form['giaiBay'], ['05', '36', '48', '94']);
    expect(form['giaiSau'], ['241', '365', '669']);
    expect(form['giaiTu'], ['4336', '4243', '5099', '3698']);
  });
}

void sideColumnTests() {
  test('Miền Bắc: nhãn bên trái ("ĐB" đọc thành 08, "G7" ...) không chiếm giải bảy', () {
    final words = [
      w('08', 5, 100), w('19640', 170, 100), w('62', 5, 140), w('50576', 170, 140), w('71187', 100, 180), w('68099', 220, 180),
      w('40352', 60, 215), w('53320', 130, 215), w('45756', 200, 215), w('74599', 60, 245), w('97405', 130, 245), w('47672', 200, 245),
      w('4336', 60, 280), w('4243', 130, 280), w('5099', 200, 280), w('3698', 270, 280),
      w('6988', 60, 315), w('6117', 130, 315), w('9223', 200, 315), w('2181', 60, 345), w('7486', 130, 345), w('3164', 200, 345),
      w('241', 80, 380), w('365', 160, 380), w('669', 240, 380), w('59', 5, 380),
      w('48', 60, 413), w('94', 130, 413), w('22', 200, 413), w('74', 270, 413),
    ];
    final form = <String, List<String>>{'giaiSau': List.filled(3, ''), 'giaiBay': List.filled(4, '')};
    guessNorthForm(orderedDigitText(words), form);
    expect(form['giaiBay'], ['48', '94', '22', '74']);
    expect(form['giaiSau'], ['241', '365', '669']);
  });
}
