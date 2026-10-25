import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/lottery_stations.dart';
import 'package:mamba_app/features/results/lottery_columns.dart';

OcrWord w(String text, double cx, double cy, {double width = 60}) => OcrWord(text, cx - width / 2, cy - 10, cx + width / 2, cy + 10);

/// One column of a Miền Nam photo, numbers top to bottom in table order.
List<OcrWord> column(double x, int seed) {
  String num(int digits, int k) => (seed * 1000 + k * 37 + 11).toString().padLeft(digits, '0').substring(0, digits);
  var k = 0;
  final out = <OcrWord>[];
  void add(int digits, double y) => out.add(w(num(digits, ++k), x, y));
  add(2, 100);
  add(3, 130);
  for (final y in [160.0, 190.0, 220.0, 250.0]) {
    add(4, y);
  }
  for (var i = 0; i < 11; i++) {
    add(5, 280.0 + i * 30);
  }
  add(6, 610);
  return out;
}

/// A table like the printed photo: title, a label column on the left, headers "NAME + code" over each column.
List<OcrWord> photo(List<String> headers, {String? dateText = '19/10/2026', List<String> title = const ['KQXS', 'Miền', 'Nam']}) {
  const xs = [200.0, 500.0, 800.0];
  return [
    for (final (i, t) in title.indexed) w(t, 250.0 + i * 90, 12),
    if (dateText != null) ...[w('Ngày', 560, 12), w(dateText, 680, 12, width: 110)],
    w('19/10', 40, 60),
    w('2026', 40, 80),
    for (var i = 0; i < 3; i++) ...[
      for (final (j, part) in headers[i].split(' ').indexed) w(part, xs[i] - 40 + j * 45, 60),
      ...column(xs[i], i + 1),
    ],
  ];
}

void main() {
  final st = LotteryStations();
  const headersHcm = ['TP. HCM 10D2', 'ĐỒNG THÁP V42', 'CÀ MAU 26-T10K3'];

  List<String?> detect(List<OcrWord> words, String selectedDate) {
    final parsed = parseColumns(words, st);
    final region = regionFromTitle(words) ?? regionFromColumns(parsed.columns, st) ?? 'mn';
    var date = parsed.date ?? selectedDate;
    if (parsed.date == null) {
      date = inferDateFromStations(region, [for (final c in parsed.columns) if (c.station != null) c.station!], selectedDate, st) ?? selectedDate;
    }
    assignStations(parsed.columns, st.stationsOn(region, date), st, others: st.regionOf(region).stations.keys.toList());
    return [for (final c in parsed.columns) c.station];
  }

  test('headers with a code next to the name still name the station', () {
    expect(detect(photo(headersHcm), '2026-10-19'), ['mn-tphcm', 'mn-dongthap', 'mn-camau']);
  });

  test('the selected day is another weekday: the stations come from the headers, not the schedule of the selected day', () {
    // 2026-10-20 is a Tuesday (Bến Tre / Vũng Tàu / Bạc Liêu); the photo is Monday's
    expect(detect(photo(headersHcm), '2026-10-20'), ['mn-tphcm', 'mn-dongthap', 'mn-camau']);
  });

  test('a misread accent or letter in a header does not lose the station', () {
    expect(detect(photo(['TP HCM', 'DONG THAF V42', 'CA MAU']), '2026-10-20'), ['mn-tphcm', 'mn-dongthap', 'mn-camau']);
  });

  test('no printed date: the day is inferred from the stations named in the headers', () {
    final words = photo(headersHcm, dateText: null);
    final parsed = parseColumns(words, st);
    expect(parsed.date, isNull);
    final named = [for (final c in parsed.columns) c.station!];
    expect(inferDateFromStations('mn', named, '2026-10-20', st), '2026-10-19'); // Monday, the day before the selected Tuesday
    expect(inferDateFromStations('mn', named, '2026-10-19', st), '2026-10-19');
    expect(inferDateFromStations('mn', ['mn-tphcm'], '2026-10-20', st), isNull); // one station is not enough to pick a day
  });

  test('the region comes from "Miền Nam" in the title or from the station names', () {
    expect(regionFromTitle(photo(headersHcm)), 'mn');
    expect(regionFromTitle(photo(headersHcm, title: const ['Xổ', 'số', 'miền', 'Trung'])), 'mt');
    final parsed = parseColumns(photo(headersHcm, title: const ['KQXS']), st);
    expect(regionFromTitle(photo(headersHcm, title: const ['KQXS'])), isNull);
    expect(regionFromColumns(parsed.columns, st), 'mn');
  });

  test('a column whose header is unreadable takes the remaining station of the day', () {
    expect(detect(photo(['TP. HCM 10D2', '#### ###', 'CÀ MAU']), '2026-10-19'), ['mn-tphcm', 'mn-dongthap', 'mn-camau']);
  });

  group('prize values', () {
    // the printed table: label column on the left ("100N"... read as bare numbers) and the date cell in the header
    List<OcrWord> withLabels(List<OcrWord> words) => [
          ...words,
          w('100', 40, 100),
          w('200', 40, 130),
          w('400', 40, 190),
          w('1', 40, 250),
          w('3', 40, 400),
          w('10', 40, 500),
          w('15', 40, 550),
          w('30', 40, 580),
        ];

    test('label column and header date cell never become prizes of the first column', () {
      final p = parseColumns(withLabels(photo(headersHcm)), st);
      expect(p.columns.length, 3);
      for (var i = 0; i < 3; i++) {
        final expected = column([200.0, 500.0, 800.0][i], i + 1).map((x) => x.text).toList();
        final c = p.columns[i];
        expect(c.complete, isTrue, reason: c.issues.join(','));
        final got = [for (final t in ['giaiTam', 'giaiBay', 'giaiSau', 'giaiNam', 'giaiTu', 'giaiBa', 'giaiNhi', 'giaiNhat', 'dacBiet']) ...c.values[t]!];
        expect(got, expected, reason: 'column $i');
      }
    });

    test('a digit read as a similar letter is repaired (O->0, l->1, S->5, B->8)', () {
      final words = photo(headersHcm);
      final i = words.indexWhere((x) => x.text.length == 6);
      final orig = words[i].text;
      final broken = OcrWord(orig.replaceFirst(orig[1], 'O'), words[i].x0, words[i].y0, words[i].x1, words[i].y1);
      words[i] = broken;
      final p = parseColumns(words, st);
      expect(p.columns[0].values['dacBiet'], [orig]);
      expect(p.columns[0].complete, isTrue);
    });

    test('words that are not numbers are not turned into numbers', () {
      final p = parseColumns([...photo(headersHcm), w('SO', 40, 300), w('BOB', 40, 320), w('TRUNG', 40, 340)], st);
      expect(p.columns[0].complete, isTrue, reason: p.columns[0].issues.join(','));
    });
  });

  group('Miền Trung photo with "Thứ hai", Phú Yên and Thừa T. Huế (it was read as Kon Tum + Huế)', () {
    // xskt-style table: the top-left cell says the weekday, the headers say the name and a short code under it
    List<OcrWord> photoMt({required List<String> head1, required List<String> head2, String weekday = 'Thứ hai'}) => [
          for (final (i, t) in weekday.split(' ').indexed) w(t, 40 + i * 30, 40, width: 50),
          for (final (j, t) in head1.indexed) w(t, 200 - 30 + j * 45, 30),
          for (final (j, t) in head2.indexed) w(t, 500 - 30 + j * 45, 30),
          ...column(200, 1),
          ...column(500, 2),
        ];

    test('the weekday word is found in the top cell: Thứ hai, Thứ 3, Chủ nhật; not further down', () {
      expect(weekdayFromWords(photoMt(head1: ['Phú', 'Yên'], head2: ['Thừa', 'Huế'])), 1);
      expect(weekdayFromWords(photoMt(head1: ['x'], head2: ['y'], weekday: 'Thứ 3')), 2);
      expect(weekdayFromWords(photoMt(head1: ['x'], head2: ['y'], weekday: 'Thứ tư')), 3);
      expect(weekdayFromWords(photoMt(head1: ['x'], head2: ['y'], weekday: 'Thứ bảy')), 6);
      expect(weekdayFromWords(photoMt(head1: ['x'], head2: ['y'], weekday: 'Chủ nhật')), 7);
      expect(weekdayFromWords(photoMt(head1: ['x'], head2: ['y'], weekday: 'Bảng')), isNull);
      // a "thu hai" far down the picture (a footer) does not count
      expect(weekdayFromWords([...column(200, 1), w('Thứ', 100, 900), w('hai', 150, 900)]), isNull);
    });

    test('the day is the latest one of that weekday up to today', () {
      expect(dateOfWeekdayOnOrBefore(1, '2026-10-25'), '2026-10-19'); // Sunday 25/10 -> Monday 19/10
      expect(dateOfWeekdayOnOrBefore(7, '2026-10-25'), '2026-10-25'); // today is that weekday
      expect(dateOfWeekdayOnOrBefore(2, '2026-10-25'), '2026-10-20');
    });

    // what the controller does, step by step
    List<String?> read(List<OcrWord> words, String selected) {
      final parsed = parseColumns(words, st);
      final region = regionFromTitle(words) ?? regionFromColumns(parsed.columns, st) ?? 'mt';
      final weekday = weekdayFromWords(words);
      final date = parsed.date ?? (weekday != null ? dateOfWeekdayOnOrBefore(weekday, selected) : selected);
      assignStations(parsed.columns, st.stationsOn(region, date), st, others: st.regionOf(region).stations.keys.toList());
      return [for (final c in parsed.columns) c.station];
    }

    test('Phú Yên header unreadable, Sunday selected: the weekday word gives Monday, so it is Phú Yên (not Kon Tum)', () {
      final ids = read(photoMt(head1: ['###', '??'], head2: ['Thừa', 'T.', 'Huế', 'TTH']), '2026-10-25'); // 25/10/2026 is a Sunday
      expect(ids, ['mt-phuyen', 'mt-hue']);
    });

    test('both names garbled but the codes PY and TTH are there', () {
      final ids = read(photoMt(head1: ['Phi', 'Yem', 'PY'], head2: ['Thva', 'T.', 'Hue', 'TTH']), '2026-10-25');
      expect(ids, ['mt-phuyen', 'mt-hue']);
      final codesOnly = read(photoMt(head1: ['PY'], head2: ['TTH'], weekday: 'Bảng'), '2026-10-25'); // no weekday: the codes alone
      expect(codesOnly, ['mt-phuyen', 'mt-hue']);
    });

    test('the readable names alone are enough, with the wrong day selected', () {
      expect(read(photoMt(head1: ['Phú', 'Yên', 'PY'], head2: ['Thừa', 'T.', 'Huế', 'TTH']), '2026-10-25'), ['mt-phuyen', 'mt-hue']);
    });

    test('no weekday and only Huế named: it draws on Monday and Sunday, but a two-column photo can only be Monday (Sunday has three)', () {
      final words = photoMt(head1: ['###'], head2: ['Thừa', 'T.', 'Huế'], weekday: 'Bảng');
      final parsed = parseColumns(words, st);
      expect(parsed.columns[1].station, 'mt-hue');
      expect(inferDateFromStations('mt', ['mt-hue'], '2026-10-25', st), isNull); // Huế alone is ambiguous (Mon / Sun)
      expect(inferDateFromStations('mt', ['mt-hue'], '2026-10-25', st, columnCount: 2), '2026-10-19'); // 2 columns: Monday
      expect(inferDateFromStations('mt', ['mt-hue'], '2026-10-25', st, columnCount: 3), '2026-10-25'); // 3 columns: Sunday
      // TP. Hồ Chí Minh draws on Monday AND Saturday (3 and 4 stations): the column count tells them apart
      expect(inferDateFromStations('mn', ['mn-tphcm'], '2026-10-25', st), isNull);
      expect(inferDateFromStations('mn', ['mn-tphcm'], '2026-10-25', st, columnCount: 3), '2026-10-19');
      expect(inferDateFromStations('mn', ['mn-tphcm'], '2026-10-25', st, columnCount: 4), '2026-10-24');
    });

    test('a photo with no weekday, no date and an unreadable Phú Yên header still ends with Phú Yên: the column count picks Monday', () {
      final words = photoMt(head1: ['###'], head2: ['Thừa', 'T.', 'Huế'], weekday: 'Bảng');
      final parsed = parseColumns(words, st);
      final named = [for (final c in parsed.columns) if (c.station != null) c.station!];
      final date = inferDateFromStations('mt', named, '2026-10-25', st, columnCount: parsed.columns.length)!;
      assignStations(parsed.columns, st.stationsOn('mt', date), st, others: st.regionOf('mt').stations.keys.toList());
      expect([for (final c in parsed.columns) c.station], ['mt-phuyen', 'mt-hue']);
    });
  });
}

