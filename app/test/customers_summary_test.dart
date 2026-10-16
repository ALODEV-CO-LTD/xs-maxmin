import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/customers/customer_model.dart';
import 'package:mamba_app/features/customers/customers_controller.dart';
import 'package:mamba_app/features/entries/entry_model.dart';

Entry e(String id, String customer, String date, {String? score, String? result, String value = '12', String? type, String? note}) =>
    Entry(id: id, customerName: customer, entryDate: date, value: value, score: score, result: result, betType: type, note: note);

void main() {
  test('toNumber / fmtPoints follow the web conventions', () {
    expect(toNumber('1.500'), 1.5); // the dot is a decimal point in the stored text
    expect(toNumber('5 điểm'), 5);
    expect(toNumber(''), 0);
    expect(toNumber(null), 0);
    expect(toNumber('abc'), 0);
    expect(toNumber('-3.5'), -3.5);
    expect(fmtPoints(''), '-');
    expect(fmtPoints('5000'), '5.000');
    expect(fmtPoints('2 con'), '2 con');
  });

  test('summarizeCustomers: roster first, totals from entries, names only in entries, sort by last date', () {
    final roster = [Customer(id: '1', name: 'An', phone: '0901'), Customer(id: '2', name: 'Bình'), Customer(id: '3', name: 'Chi')];
    final entries = [
      e('a', 'An', '2026-10-01', score: '10', result: '4'),
      e('b', 'An', '2026-10-05', score: '5'),
      e('c', 'Dũng', '2026-10-09', score: '7', result: '20'),
      e('d', 'Bình', '2026-10-02', score: ''),
    ];
    final list = summarizeCustomers(roster, entries);
    expect(list.map((s) => s.name), ['Chi', 'Dũng', 'An', 'Bình']); // no entries first, then newest first
    final an = list.firstWhere((s) => s.name == 'An');
    expect((an.count, an.vao, an.ra, an.chenhLech, an.lastDate, an.phone), (2, 15.0, 4.0, 11.0, '2026-10-05', '0901'));
    expect(list.firstWhere((s) => s.name == 'Dũng').customer, isNull);
    expect(list.firstWhere((s) => s.name == 'Dũng').chenhLech, -13);
    expect(list.firstWhere((s) => s.name == 'Chi').count, 0);
  });

  test('searchCustomers is accent-insensitive', () {
    final list = summarizeCustomers([Customer(id: '1', name: 'Đỗ Ngọc Mai'), Customer(id: '2', name: 'Lan')], []);
    expect(searchCustomers(list, 'do ngoc').map((s) => s.name), ['Đỗ Ngọc Mai']);
    expect(searchCustomers(list, '  '), hasLength(2));
  });

  test('parseCustomers reads the API shape', () {
    final l = parseCustomers({
      'customers': [
        {'id': 'x', 'name': 'An', 'phone': '', 'scoringRates': {'de': {'rate': 1}}, 'defaultStation': 'mn-tphcm', 'homeRegion': 'mn', 'createdAt': 't'},
        {'id': 'y', 'name': 'Bo', 'phone': null, 'scoringRates': null, 'defaultStation': null},
        {'id': 'z', 'name': 'Chi', 'homeRegion': 'xx'},
      ],
    });
    expect(l[0].stationCode, 'mn-tphcm');
    expect(l[0].scoringRates, isNotNull);
    expect(l[1].stationCode, 'mb');
    expect(l[1].phone, '');
    expect(l[0].homeRegion, 'mn');
    expect(l[1].homeRegion, isNull);
    expect(l[2].homeRegion, isNull); // only 'mb' / 'mn' are known
  });

  group('entry list helpers', () {
    final list = [
      e('1', 'An', '2026-10-01', score: '10', type: 'de', note: 'gấp'),
      e('2', 'An', '2026-10-02', score: '5', type: 'lo', value: '45'),
      e('3', 'Bình', '2026-10-02', score: '7', type: 'de', value: '99'),
    ];
    test('filters by customer, date, type and text', () {
      expect(filterEntries(list, EntryFilter(), customerName: 'An', masked: false).map((x) => x.id), ['1', '2']);
      expect(filterEntries(list, EntryFilter(), customerName: '', masked: false), isEmpty);
      expect(filterEntries(list, EntryFilter(all: true), customerName: '', masked: false), hasLength(3));
      expect(filterEntries(list, EntryFilter(all: true, date: '2026-10-02'), customerName: '', masked: false).map((x) => x.id), ['2', '3']);
      expect(filterEntries(list, EntryFilter(all: true, type: 'lo'), customerName: '', masked: false).map((x) => x.id), ['2']);
      expect(filterEntries(list, EntryFilter(all: true, q: 'GẤP'), customerName: '', masked: false).map((x) => x.id), ['1']);
      expect(filterEntries(list, EntryFilter(all: true, q: '99'), customerName: '', masked: false).map((x) => x.id), ['3']);
    });
    test('while masked, searching cannot reveal figures', () {
      expect(filterEntries(list, EntryFilter(all: true, q: '99'), customerName: '', masked: true), isEmpty);
      expect(filterEntries(list, EntryFilter(all: true, q: 'bình'), customerName: '', masked: true).map((x) => x.id), ['3']);
    });
    test('totals', () {
      final t = totalsOf(list);
      expect((t.vao, t.ra, t.chenhLech), (22.0, 0.0, 22.0));
    });
    test('copy text is tab separated with an optional customer column', () {
      final text = entriesToText([list[0]], withCustomer: true);
      expect(text.split('\n'), ['Khách hàng\tNgày\tHạng mục\tSố\tĐiểm vào\tĐiểm ra\tGhi chú', 'An\t2026-10-01\tĐề\t12\t10\t\tgấp']);
      expect(entriesToText([list[1]]).split('\n').last, '2026-10-02\tLô\t45\t5\t\t');
    });
  });
}
