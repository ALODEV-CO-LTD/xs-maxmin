import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/core/scoring_config.dart';
import 'package:mamba_app/features/customers/scoring_editor_model.dart';

RatesMap account() => {
      'de': {'rate': 70, 'tiers': ['dacBiet'], 'digits': 2},
      'lo': {'rate': 20, 'tiers': ['dacBiet', 'giaiNhat', 'giaiBay'], 'digits': 2, 'unit': 'point', 'pointValue': 23000},
    };

ScoringEditorModel customerModel([RatesMap? own]) {
  final m = ScoringEditorModel(isCustomer: true, accountRates: account())..load(own ?? {});
  m.buildRows();
  return m;
}

EditorRow row(ScoringEditorModel m, String type) => m.rows.firstWhere((r) => r.type == type);

void main() {
  group('customer scope', () {
    test('starts on the account values with nothing to save', () {
      final m = customerModel();
      expect(m.rows.map((r) => r.type), ['de', 'lo']);
      expect(row(m, 'de').rate, '70');
      expect(row(m, 'lo').unit, 'point');
      expect(row(m, 'de').unit, 'money');
      expect(m.tag(row(m, 'de')), 'Mặc định');
      expect(m.dirty, isFalse);
      expect(m.resultMap(), isEmpty);
    });

    test('changing a row in a region makes a region-only value; reverting drops it', () {
      final m = customerModel();
      row(m, 'de').rate = '80';
      expect(m.dirty, isTrue);
      expect(m.isRegionOnly(row(m, 'de')), isTrue);
      expect(m.tag(row(m, 'de')), 'Riêng khách · miền này');
      final map = m.resultMap();
      expect(map.keys, ['de@mb']);
      expect((map['de@mb'] as Map)['rate'], 80);

      row(m, 'de').rate = '70';
      expect(m.dirty, isFalse);
      expect(m.resultMap(), isEmpty);
    });

    test('other regions are not touched and show the general value', () {
      final m = customerModel();
      row(m, 'de').rate = '80';
      expect(m.switchRegion('mt'), '');
      expect(row(m, 'de').rate, '70');
      expect(m.regionHasOverride('mb'), isTrue);
      expect(m.regionHasOverride('mt'), isFalse);
      // and coming back keeps it
      m.switchRegion('mb');
      expect(row(m, 'de').rate, '80');
    });

    test('removing a type for one region writes a disabled marker; it can be restored', () {
      final m = customerModel()..switchRegion('mt');
      final de = row(m, 'de');
      expect(m.removeKind(de), RemoveKind.thisRegionOnly);
      m.removeRow(de);
      expect(row(m, 'de').off, isTrue);
      expect(m.tag(row(m, 'de')), 'Đã bỏ');
      final map = m.resultMap();
      expect(map['de@mt'], {'disabled': true});
      expect(customerBetTypes(account(), map, 'mt'), ['lo']);
      expect(customerBetTypes(account(), map, 'mb'), ['de', 'lo']);

      m.restoreRow(row(m, 'de'));
      expect(row(m, 'de').off, isFalse);
      expect(m.resultMap(), isEmpty);
      expect(m.dirty, isFalse);
    });

    test('a type the customer disabled everywhere loads as off in every region', () {
      final m = customerModel({'lo': {'disabled': true}});
      expect(row(m, 'lo').off, isTrue);
      m.switchRegion('mn');
      expect(row(m, 'lo').off, isTrue);
      m.restoreRow(row(m, 'lo'));
      expect(m.work.containsKey('lo'), isFalse);
    });

    test('a customer-only type: tagged, and removing it deletes it everywhere', () {
      final m = customerModel({
        'xien': {'rate': 15, 'tiers': ['dacBiet'], 'digits': 2},
        'xien@mt': {'rate': 16, 'tiers': ['dacBiet'], 'digits': 2},
      });
      final r = row(m, 'xien');
      expect(r.custom, isTrue);
      expect(m.tag(r), 'Chỉ khách này');
      expect(m.removeKind(r), RemoveKind.everywhere);
      m.removeRow(r);
      expect(m.work.keys, isEmpty);
      expect(m.rows.map((x) => x.type), ['de', 'lo']);
    });

    test('adding a type is region-only and visible in that region only', () {
      final m = customerModel()..switchRegion('mt');
      expect(m.addType(key: 'bao-lo', rate: 80, tiers: ['dacBiet', 'giaiTam'], digits: 3, unit: 'point', pointValue: 20000), isTrue);
      expect(m.typeKeys, contains('bao-lo'));
      final added = row(m, 'bao-lo');
      expect(added.regionType, isTrue);
      expect(m.tag(added), 'Riêng khách · chỉ miền này'.replaceFirst('Riêng khách · chỉ', 'Riêng khách · chỉ'));
      expect(m.addType(key: 'bao-lo', rate: 1, tiers: ['dacBiet'], digits: 2, unit: 'money', pointValue: 0), isFalse);
      final map = m.resultMap();
      expect(map.keys, contains('bao-lo@mt'));
      expect(customerBetTypes(account(), map, 'mt'), contains('bao-lo'));
      expect(customerBetTypes(account(), map, 'mb'), isNot(contains('bao-lo')));
      m.switchRegion('mb');
      expect(m.rows.map((r) => r.type), ['de', 'lo']);
      // removing a region type only deletes the region key
      m.switchRegion('mt');
      m.removeRow(row(m, 'bao-lo'));
      expect(m.work.containsKey('bao-lo@mt'), isFalse);
    });

    test('Theo chung drops a region-only value', () {
      final m = customerModel({'de@mb': {'rate': 90, 'tiers': ['dacBiet'], 'digits': 2}});
      expect(row(m, 'de').rate, '90');
      expect(m.isRegionOnly(row(m, 'de')), isTrue);
      m.resetRow(row(m, 'de'));
      expect(row(m, 'de').rate, '70');
      expect(m.work.containsKey('de@mb'), isFalse);
    });

    test('tiers: the SET matters, not the order', () {
      final m = customerModel();
      final lo = row(m, 'lo');
      lo.tiers = ['giaiBay', 'dacBiet', 'giaiNhat'];
      expect(m.dirty, isFalse);
      lo.toggleTier('giaiNhi');
      expect(m.dirty, isTrue);
      lo.toggleTier('giaiNhi');
      expect(m.dirty, isFalse);
    });

    test('unit and price per point count as changes', () {
      final m = customerModel();
      final lo = row(m, 'lo');
      lo.pointValue = '25000';
      expect(m.dirty, isTrue);
      lo.pointValue = '23000';
      lo.unit = 'money';
      expect(m.dirty, isTrue);
    });

    test('Bỏ cấu hình riêng clears everything but the saved state stays the baseline', () {
      final m = customerModel({'de@mb': {'rate': 90, 'tiers': ['dacBiet'], 'digits': 2}});
      expect(m.dirty, isFalse);
      m.resetAll();
      expect(m.work, isEmpty);
      expect(m.dirty, isTrue); // differs from what was saved
      expect(m.resultMap(), isEmpty);
    });
  });

  group('account scope', () {
    ScoringEditorModel accountModel() => ScoringEditorModel(isCustomer: false)
      ..load(account())
      ..buildRows();

    test('rows come from the account map; region edits become type@region', () {
      final m = accountModel();
      expect(m.tag(row(m, 'de')), 'Chung các miền');
      m.switchRegion('mn');
      row(m, 'de').rate = '75';
      final map = m.resultMap();
      expect(map.keys.toSet(), {'de', 'lo', 'de@mn'});
      expect((map['de'] as Map)['rate'], 70);
    });

    test('removing a shared type removes it from every region, region-only types stay region-only', () {
      final m = ScoringEditorModel(isCustomer: false)
        ..load({...account(), 'de@mt': {'rate': 71, 'tiers': ['dacBiet'], 'digits': 2}, 'ba-cang@mn': {'rate': 900, 'tiers': ['dacBiet'], 'digits': 3}})
        ..buildRows();
      expect(m.removeKind(row(m, 'de')), RemoveKind.everywhere);
      m.removeRow(row(m, 'de'));
      expect(m.work.keys.toSet(), {'lo', 'ba-cang@mn'});
      m.switchRegion('mn');
      expect(m.removeKind(row(m, 'ba-cang')), RemoveKind.regionType);
    });

    test('defaults can be restored', () {
      final m = accountModel();
      row(m, 'de').rate = '99';
      m.resetAll();
      expect(row(m, 'de').rate, '70');
      expect(m.resultMap().keys.toSet(), {'de', 'lo'});
    });
  });

  group('validation', () {
    test('bad rate or no prize group blocks save and switching region', () {
      final m = customerModel();
      row(m, 'de').rate = 'abc';
      expect(m.validate(), contains('Đề'));
      expect(m.switchRegion('mt'), isNotEmpty);
      expect(m.region, 'mb');
      row(m, 'de').rate = '0';
      expect(m.validate(), isNotEmpty);
      row(m, 'de').rate = '0,5'; // a decimal comma is accepted
      expect(m.validate(), '');
      row(m, 'de').tiers = [];
      expect(m.validate(), contains('ít nhất một giải'));
    });

    test('off rows are not validated', () {
      final m = customerModel({'lo': {'disabled': true}});
      row(m, 'lo').rate = '';
      expect(m.validate(), '');
    });
  });

  group('helpers', () {
    test('numText drops a pointless .0', () {
      expect(numText(70.0), '70');
      expect(numText(0.5), '0.5');
      expect(numText(70), '70');
    });
    test('snapshotOf ignores key order, tier order and 70 vs 70.0', () {
      final a = {'de': {'rate': 70, 'tiers': ['b', 'a'], 'digits': 2}, 'lo': {'disabled': true}};
      final b = {'lo': {'disabled': true}, 'de': {'digits': 2.0, 'tiers': ['a', 'b'], 'rate': 70.0}};
      expect(snapshotOf(a), snapshotOf(b));
    });
    test('betTypeKey', () {
      // kept in add_bet_type_dialog.dart
      expect(' Xiên  2 '.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '-'), 'xiên-2');
    });
  });
}
