import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/customers/scoring_editor_model.dart';

// An account that saved the whole built-in table (what GET /me/scoring-settings answers by default).
RatesMap account() => Map<String, dynamic>.from(defaultRates);

// An account that only has the older Đề / Lô entries.
RatesMap legacyAccount() => {
      'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2},
      'lo': {'rate': 20, 'tiers': ['dacBiet', 'giaiNhat', 'giaiBay'], 'digits': 2, 'unit': 'point', 'pointValue': 23000},
    };

ScoringEditorModel customerModel([RatesMap? own, RatesMap? acc]) {
  final m = ScoringEditorModel(isCustomer: true, accountRates: acc ?? account())..load(own ?? {});
  m.buildRows();
  return m;
}

ScoringEditorModel accountModel([RatesMap? map]) => ScoringEditorModel(isCustomer: false)
  ..load(map ?? account())
  ..buildRows();

EditorRow row(ScoringEditorModel m, String type) => m.rows.firstWhere((r) => r.type == type);

void main() {
  group('customer scope', () {
    test('shows the 15 standard kinds with the account values and has nothing to save', () {
      final m = customerModel();
      expect(m.rows.map((r) => r.type), ['lo', 'lo3', 'lo4', 'dau', 'duoi', 'cang3', 'cang4', 'xien2', 'xien3', 'xien4', 'truot4', 'truot8', 'truot10', 'tai_xiu', 'chan_le']);
      expect(row(m, 'lo').price, '21600'); // Miền Bắc
      expect(row(m, 'lo').payout, '70000');
      expect(row(m, 'lo').label, 'Bao lô 2 số');
      expect(row(m, 'lo3').price, '18400');
      expect(m.tag(row(m, 'lo')), 'Mặc định');
      expect(m.dirty, isFalse);
      expect(m.resultMap(), isEmpty);
      m.switchRegion('mn');
      expect(row(m, 'lo').price, '12600');
    });

    test('changing a row in a region makes a region-only value; reverting drops it', () {
      final m = customerModel();
      row(m, 'duoi').price = '1500';
      expect(m.dirty, isTrue);
      expect(m.hasOwn(row(m, 'duoi')), isTrue);
      expect(m.tag(row(m, 'duoi')), 'Riêng');
      final map = m.resultMap();
      expect(map.keys, ['duoi@mb']);
      final saved = map['duoi@mb'] as Map;
      expect([saved['kind'], saved['price'], saved['payout']], ['duoi', 1500, 70000]);
      // the older fields travel with it
      expect([saved['unit'], saved['pointValue'], saved['digits']], ['point', 1500, 2]);
      expect(saved['rate'], closeTo(70000 / 1500, 1e-9));

      row(m, 'duoi').price = '1000';
      expect(m.dirty, isFalse);
      expect(m.resultMap(), isEmpty);
    });

    test('other regions are not touched; coming back keeps the edit', () {
      final m = customerModel();
      row(m, 'dau').payout = '80000';
      expect(m.switchRegion('mt'), '');
      expect(row(m, 'dau').payout, '70000');
      expect(m.regionHasOverride('mb'), isTrue);
      expect(m.regionHasOverride('mt'), isFalse);
      m.switchRegion('mb');
      expect(row(m, 'dau').payout, '80000');
    });

    test('a customer turns a row off for one region (and back on)', () {
      final m = customerModel()..switchRegion('mt');
      m.toggleOff(row(m, 'xien2'));
      expect(row(m, 'xien2').off, isTrue);
      expect(m.tag(row(m, 'xien2')), 'Không dùng');
      var map = m.resultMap();
      expect(map['xien2@mt'], {'disabled': true});
      expect(customerBetTypes(account(), map, 'mt'), isNot(contains('xien2')));
      expect(customerBetTypes(account(), map, 'mb'), contains('xien2'));
      // an off row is not validated and not rewritten
      row(m, 'xien2').payout;
      m.toggleOff(row(m, 'xien2'));
      expect(row(m, 'xien2').off, isFalse);
      expect(m.resultMap(), isEmpty);
      expect(m.dirty, isFalse);
    });

    test('a type disabled for every region loads as off in every region', () {
      final m = customerModel({'lo': {'disabled': true}});
      expect(row(m, 'lo').off, isTrue);
      m.switchRegion('mn');
      expect(row(m, 'lo').off, isTrue);
      m.toggleOff(row(m, 'lo'));
      expect(m.work.containsKey('lo'), isFalse);
      expect(row(m, 'lo').off, isFalse);
    });

    test('Theo chung drops a region-only value', () {
      final m = customerModel({'cang3@mb': makeRow(kind: 'cang3', price: 15000, payout: 600000)});
      expect(row(m, 'cang3').price, '15000');
      expect(m.hasOwn(row(m, 'cang3')), isTrue);
      m.resetRow(row(m, 'cang3'));
      expect(row(m, 'cang3').price, '12600');
      expect(m.work.containsKey('cang3@mb'), isFalse);
    });

    test('"Kiểu đánh khác" is added for the active region only and can be removed', () {
      final m = customerModel()..switchRegion('mt');
      expect(m.addCustom(name: 'Tài xỉu', symbol: ' TX ', allTiers: false, digits: 3, price: '10000', payout: '90000'), '');
      final added = row(m, 'tx');
      expect(added.extra, isTrue);
      expect(added.label, 'Tài xỉu');
      expect(added.symbols, 'tx');
      expect(added.digits, 3);
      expect(added.tiers, ['dacBiet']);
      final map = m.resultMap();
      expect(map.keys, ['tx@mt']);
      expect((map['tx@mt'] as Map)['kind'], 'custom');
      expect(customerBetTypes(account(), map, 'mt'), contains('tx'));
      expect(customerBetTypes(account(), map, 'mb'), isNot(contains('tx')));
      m.switchRegion('mb');
      expect(m.rows.map((r) => r.type), isNot(contains('tx')));
      m.switchRegion('mt');
      m.removeRow(row(m, 'tx'));
      expect(m.work.containsKey('tx@mt'), isFalse);
      expect(m.rows.map((r) => r.type), isNot(contains('tx')));
    });

    test('"Kiểu đánh khác" is checked: symbol, duplicates, prices', () {
      final m = customerModel();
      String add(String symbol, {String price = '1000', String payout = '2000'}) => m.addCustom(name: '', symbol: symbol, allTiers: true, digits: 2, price: price, payout: payout);
      expect(add('Có dấu'), contains('Ký hiệu'));
      expect(add('abcdefghijklm'), contains('Ký hiệu'));
      expect(add(''), contains('Ký hiệu'));
      expect(add('lo'), 'Ký hiệu này đã có'); // a standard kind
      expect(add('tx', price: '0'), contains('Giá tiền'));
      expect(add('tx', payout: '-1'), contains('Giá tiền'));
      expect(add('tx', price: 'abc'), contains('Giá tiền'));
      expect(add('tx'), '');
      expect(add('tx'), 'Ký hiệu này đã có');
      expect(row(m, 'tx').tiers, hasLength(8));
      expect(row(m, 'tx').label, 'tx'); // no name = the symbol
    });

    test('a customer-only type of the account shows in every region it exists in and removal is per key', () {
      final m = customerModel({
        'tx@mb': makeRow(kind: 'custom', price: 1000, payout: 5000, name: 'Tài xỉu'),
        'tx': makeRow(kind: 'custom', price: 2000, payout: 5000, name: 'Tài xỉu'),
      });
      expect(row(m, 'tx').price, '1000'); // the region's own value wins
      m.switchRegion('mt');
      expect(row(m, 'tx').price, '2000'); // the shared value
      m.switchRegion('mb');
      expect(m.rows.map((r) => r.type), contains('tx'));
      m.removeRow(row(m, 'tx'));
      expect(m.work.keys, isEmpty);
    });

    test('Bỏ cấu hình riêng clears everything but the saved state stays the baseline', () {
      final m = customerModel({'duoi@mb': makeRow(kind: 'duoi', price: 1500, payout: 70000)});
      expect(m.dirty, isFalse);
      m.resetAll();
      expect(m.work, isEmpty);
      expect(m.dirty, isTrue);
      expect(m.resultMap(), isEmpty);
    });

    test('an older account (Đề / Lô) reads as a table: lô = 23.000 / 460.000, Đề as an extra row', () {
      final m = customerModel(null, legacyAccount());
      expect(row(m, 'lo').price, '23000');
      expect(row(m, 'lo').payout, '460000');
      final de = row(m, 'de');
      expect(de.extra, isTrue);
      expect(de.label, 'Đề');
      expect(de.price, '1');
      expect(de.payout, '70');
    });
  });

  group('account scope', () {
    test('a fresh default table is not dirty and keeps every kind', () {
      final m = accountModel();
      expect(m.dirty, isFalse);
      expect(m.tag(row(m, 'lo')), '');
      expect(m.resultMap().keys.toSet(), defaultRates.keys.toSet());
    });

    test('region edits become kind@region and only that region changes', () {
      final m = accountModel();
      m.switchRegion('mn');
      row(m, 'xien2').payout = '1000000';
      expect(m.dirty, isTrue);
      final map = m.resultMap();
      expect((map['xien2@mn'] as Map)['payout'], 1000000);
      expect((map['xien2@mb'] as Map)['payout'], 0);
      expect((map['xien2@mn'] as Map)['price'], 12600);
    });

    test('an older account (Đề / Lô only) gets every missing kind filled in on save, nothing else changes', () {
      final m = accountModel(legacyAccount());
      expect(m.dirty, isTrue); // the missing kinds are written into the table, so saving is offered
      final map = m.resultMap();
      expect(map.keys, containsAll(['de', 'lo', 'dau@mb', 'dau@mt', 'dau@mn', 'xien4@mn', 'cang3@mb']));
      expect(map.keys, isNot(contains('lo@mb'))); // the shared lô stays as it was
      expect(map.length, 2 + 14 * 3);
      expect((map['lo'] as Map)['rate'], 20);
    });

    test('Đặt lại mặc định restores the built-in table', () {
      final saved = account()..['lo@mt'] = makeRow(kind: 'lo', price: 99, payout: 70000);
      final m = accountModel(saved)..switchRegion('mt');
      expect(row(m, 'lo').price, '99');
      m.resetAll();
      expect(row(m, 'lo').price, '12600');
      expect(m.resultMap().keys.toSet(), defaultRates.keys.toSet());
      expect(m.dirty, isTrue); // differs from what was saved
    });

    test('removing an extra row removes its shared and its region key', () {
      final m = accountModel({...account(), 'tx': makeRow(kind: 'custom', price: 1, payout: 2), 'tx@mn': makeRow(kind: 'custom', price: 3, payout: 4)});
      m.switchRegion('mn');
      m.removeRow(row(m, 'tx'));
      expect(m.work.keys, isNot(contains('tx')));
      expect(m.work.keys, isNot(contains('tx@mn')));
    });
  });

  group('thêm / xoá cách đánh', () {
    test('default scope: removing a standard row writes a marker, hides it and it can be restored', () {
      final m = accountModel()..switchRegion('mn');
      m.removeRow(row(m, 'lo3'));
      expect(m.rows.map((r) => r.type), isNot(contains('lo3')));
      expect(m.work['lo3@mn'], {'disabled': true});
      expect(m.work['lo3@mb'], isNotNull); // other regions keep it
      expect(m.restorable('lo').map((k) => k.kind), ['lo3']);
      expect(m.restorable('de'), isEmpty);
      // saving does not bring it back
      final map = m.resultMap();
      expect(map['lo3@mn'], {'disabled': true});
      expect(typesIn(map, 'mn'), isNot(contains('lo3')));
      expect(typesIn(map, 'mb'), contains('lo3'));
      expect(m.dirty, isTrue);
      // restore
      m.restoreKind('lo3');
      expect(m.rows.map((r) => r.type), contains('lo3'));
      expect(row(m, 'lo3').price, '11900'); // the built-in default again
      expect(m.dirty, isFalse);
    });

    test('a customer does not see a row the account removed, and cannot restore it', () {
      final acc = account()..['xien4@mn'] = {'disabled': true};
      final m = customerModel(null, acc)..switchRegion('mn');
      expect(m.rows.map((r) => r.type), isNot(contains('xien4')));
      expect(m.restorable('xien'), isEmpty);
      m.switchRegion('mb');
      expect(m.rows.map((r) => r.type), contains('xien4'));
      expect(customerBetTypes(acc, null, 'mn'), isNot(contains('xien4')));
      expect(customerBetTypes(acc, null, 'mb'), contains('xien4'));
    });

    test('a new custom cách đánh goes into the group it was added to (group stored unless "other")', () {
      final m = accountModel()..switchRegion('mt');
      expect(m.addCustom(group: 'de', name: 'Đề 3 số', symbol: 'd3', allTiers: false, digits: 3, price: '12600', payout: '500000'), '');
      expect(m.groups.firstWhere((g) => g.group.id == 'de').rows.map((r) => r.type), ['dau', 'duoi', 'cang3', 'cang4', 'd3']);
      final saved = m.resultMap()['d3@mt'] as Map;
      expect([saved['kind'], saved['group'], saved['name'], saved['digits']], ['custom', 'de', 'Đề 3 số', 3]);
      expect(m.addCustom(name: '', symbol: 'ot', allTiers: true, digits: 2, price: '1', payout: '0'), '');
      expect(m.work['ot@mt'], isNot(contains('group')));
      expect(m.work['ot@mt'], isNot(contains('name')));
      expect(m.groups.last.group.id, 'other');
      // reload: back in the same group, with the name
      final again = accountModel(m.resultMap())..switchRegion('mt');
      expect(again.groups.firstWhere((g) => g.group.id == 'de').rows.last.label, 'Đề 3 số');
      expect(again.dirty, isFalse);
    });

    test('a custom row can be edited on the row: name and "lấy số"', () {
      final m = accountModel()..switchRegion('mt');
      m.addCustom(group: 'thantai', name: 'Tài', symbol: 'tt', allTiers: false, digits: 2, price: '1000', payout: '2000');
      final r = row(m, 'tt');
      expect(r.srcTiers, ['dacBiet']);
      expect(m.srcCaption(r), '2 số cuối của giải đặc biệt');
      r.name = 'Tài 3';
      r.srcTiers = ['dacBiet', 'giaiNhat'];
      r.srcDigits = 3;
      r.srcPos = 'first';
      r.srcPick = '2, 1, 1';
      final saved = m.resultMap()['tt@mt'] as Map;
      expect([saved['name'], saved['digits'], saved['group']], ['Tài 3', 3, 'thantai']);
      expect(saved['tiers'], ['dacBiet', 'giaiNhat']); // mirrored for older code
      expect(saved['source'], {'tiers': ['dacBiet', 'giaiNhat'], 'position': 'first', 'digits': 3, 'pick': [1, 2]});
      r.name = ' ';
      expect((m.resultMap()['tt@mt'] as Map).containsKey('name'), isFalse);
    });

    test('lấy số of a standard row is stored only when it differs from the default; validated', () {
      final m = accountModel();
      final r = row(m, 'duoi');
      expect(m.srcChanged(r), isFalse);
      expect(m.srcCaption(r), '2 số cuối giải đặc biệt'); // the kind's own caption
      expect((m.resultMap()['duoi@mb'] as Map).containsKey('source'), isFalse);
      r.srcPos = 'first';
      expect(m.srcChanged(r), isTrue);
      expect(m.srcCaption(r), '2 số đầu của giải đặc biệt');
      expect(m.dirty, isTrue);
      expect(((m.resultMap()['duoi@mb'] as Map)['source'] as Map)['position'], 'first');
      m.resetSrc(r);
      expect(m.srcChanged(r), isFalse);
      r.srcTiers = [];
      r.srcPos = 'last';
      expect(m.validate(), contains('chọn ít nhất một giải'));
      r.srcTiers = ['dacBiet'];
      r.srcDigits = 7;
      expect(m.validate(), contains('1 đến 6'));
      r.srcDigits = 2;
      expect(m.validate(), '');
      // which fields a kind shows
      expect(m.fieldsOf(row(m, 'xien2')).pick, isFalse);
      expect(m.fieldsOf(row(m, 'tai_xiu')).digits, isFalse);
      expect(m.fieldsOf(row(m, 'tai_xiu')).pick, isTrue);
      expect(m.fieldsOf(row(m, 'lo')).position, isTrue);
    });

    test('removing a custom row deletes its keys; fillMissing does not bring back a removed standard row', () {
      final m = accountModel();
      m.removeRow(row(m, 'cang4'));
      m.switchRegion('mt');
      m.addCustom(name: '', symbol: 'zz', allTiers: false, digits: 2, price: '1', payout: '1');
      m.removeRow(row(m, 'zz'));
      expect(m.work.keys, isNot(contains('zz@mt')));
      final map = m.resultMap();
      expect(map['cang4@mb'], {'disabled': true});
      expect((map['cang4@mt'] as Map)['kind'], 'cang4');
    });

    test('an older account with a removed row marker is still filled in for the others', () {
      final m = accountModel({'de': legacyAccount()['de'], 'lo': legacyAccount()['lo'], 'dau@mn': {'disabled': true}});
      final map = m.resultMap();
      expect(map['dau@mn'], {'disabled': true});
      expect(map.containsKey('dau@mb'), isTrue);
    });
  });

  group('nhóm', () {
    test('Bao lô, Đề (4 cách đánh), Xiên (3); the group of custom rows only when there is one', () {
      final m = customerModel();
      final g = {for (final x in m.groups) x.group.id: x};
      expect(m.groups.map((x) => x.group.label), ['Lô', 'Đề', 'Xiên', 'Lô trượt', 'Thần tài (tài/xỉu, chẵn/lẻ)']);
      expect(g['de']!.rows.map((r) => r.type), ['dau', 'duoi', 'cang3', 'cang4']);
      expect(g['xien']!.rows, hasLength(3));
      expect(g['lo']!.rows.map((r) => r.type), ['lo', 'lo3', 'lo4']);
      expect(g['truot']!.rows, hasLength(3));
      expect(g['thantai']!.rows.map((r) => r.type), ['tai_xiu', 'chan_le']);
      m.addCustom(name: 'Tài xỉu', symbol: 'tx', allTiers: false, digits: 2, price: '1000', payout: '2000');
      expect(m.groups.last.group.label, 'Kiểu đánh khác');
      expect(m.groups.last.rows.single.type, 'tx');
      expect(row(customerModel(null, legacyAccount()), 'de').group, 'other');
    });
  });

  group('ký hiệu', () {
    test('lo / dau / duoi show the built-in spellings and storing them is not a change', () {
      final m = customerModel();
      expect(row(m, 'lo').editable, isTrue);
      expect(row(m, 'lo').symbolsInput, 'L, l, lo, lô, x, X');
      expect(row(m, 'dau').symbolsInput, 'Đ, D, đ, dau, đầu');
      expect(row(m, 'cang3').editable, isFalse);
      expect(row(m, 'cang3').symbolText, contains('123x10'));
      expect(m.dirty, isFalse);
      row(m, 'lo').symbolsInput = 'L l lo lô x X'; // other separators, same list
      expect(m.dirty, isFalse);
    });

    test('changed symbols are stored with the row and read back', () {
      final m = customerModel();
      row(m, 'duoi').symbolsInput = 'cc; dd, cc';
      expect(m.dirty, isTrue);
      expect(m.validate(), '');
      final map = m.resultMap();
      expect((map['duoi@mb'] as Map)['symbols'], ['cc', 'dd']);
      final again = customerModel(map);
      expect(row(again, 'duoi').symbolsInput, 'cc, dd');
      expect(again.dirty, isFalse);
      expect(kindSymbolsFor(account(), map, 'mb'), {'duoi': ['cc', 'dd']});
      expect(kindSymbolsFor(account(), map, 'mn'), isEmpty);
    });

    test('only letters, and no symbol shared by two kinds of a region (accents and case ignored)', () {
      final m = customerModel();
      row(m, 'duoi').symbolsInput = 'c1';
      expect(m.validate(), contains('chỉ được gồm chữ cái'));
      row(m, 'duoi').symbolsInput = 'abcdefghijklm';
      expect(m.validate(), contains('chỉ được gồm chữ cái'));
      row(m, 'duoi').symbolsInput = 'c, ×';
      expect(m.validate(), '');
      row(m, 'duoi').symbolsInput = 'c, Đ'; // Đ is already Đầu's
      expect(m.validate(), contains('đang dùng cho cả'));
      row(m, 'duoi').symbolsInput = 'c, dau'; // "dau" and "đầu" fold to the same
      expect(m.validate(), contains('Đầu'));
      row(m, 'duoi').symbolsInput = 'c, cuối';
      expect(m.validate(), '');
    });
  });

  group('validation', () {
    test('price must be above 0 and payout not negative; blocks save and switching region', () {
      final m = customerModel();
      row(m, 'lo').price = 'abc';
      expect(m.validate(), contains('Bao lô'));
      expect(m.switchRegion('mt'), isNotEmpty);
      expect(m.region, 'mb');
      row(m, 'lo').price = '0';
      expect(m.validate(), isNotEmpty);
      row(m, 'lo').price = '1000,5'; // a decimal comma is accepted
      expect(m.validate(), '');
      row(m, 'lo').payout = '-1';
      expect(m.validate(), contains('Giá trúng'));
      row(m, 'lo').payout = '';
      expect(m.validate(), ''); // an empty payout is 0 = "Chưa nhập"
    });

    test('off rows are not validated', () {
      final m = customerModel({'lo': {'disabled': true}});
      row(m, 'lo').price = '';
      expect(m.validate(), '');
    });

    test('xiên without a payout is flagged "chưa nhập"', () {
      final m = customerModel();
      expect(m.notSet(row(m, 'xien2')), isTrue);
      expect(m.notSet(row(m, 'lo')), isFalse);
      expect(m.notSet(row(m, 'lo3')), isTrue); // every standard row without a payout
      expect(m.notSet(row(m, 'tai_xiu')), isTrue);
      row(m, 'xien2').payout = '1000000';
      expect(m.notSet(row(m, 'xien2')), isFalse);
    });
  });

  group('helpers', () {
    test('numText drops a pointless .0', () {
      expect(numText(70.0), '70');
      expect(numText(0.5), '0.5');
      expect(numText(70), '70');
      expect(numText(null), '');
    });
    test('snapshotOf ignores key order, tier order and 70 vs 70.0', () {
      final a = {'de': {'rate': 70, 'tiers': ['b', 'a'], 'digits': 2}, 'lo': {'disabled': true}};
      final b = {'lo': {'disabled': true}, 'de': {'digits': 2.0, 'tiers': ['a', 'b'], 'rate': 70.0}};
      expect(snapshotOf(a), snapshotOf(b));
    });
  });
}
