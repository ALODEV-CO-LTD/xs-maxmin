import 'package:flutter_test/flutter_test.dart';
import 'package:mamba_app/features/admin/settings/settings_logic.dart';
import 'package:mamba_app/features/admin/settings/settings_ui.dart';

void main() {
  group('bank form', () {
    test('requires bank, account and holder; body carries bank_name', () {
      expect(const BankForm().validate(), isNotNull);
      expect(const BankForm(bin: '970436', account: ' ', holder: 'A').validate(), isNotNull);
      const ok = BankForm(bin: '970436', account: ' 123 ', holder: ' NGUYEN A ');
      expect(ok.validate(), isNull);
      expect(ok.toBody(), {'bank_bin': '970436', 'bank_name': 'Vietcombank', 'bank_account_number': '123', 'bank_account_holder': 'NGUYEN A'});
      expect(vietQrBanks, hasLength(20));
    });
  });

  group('max ids', () {
    test('1-100, empty means 5', () {
      expect(validateMaxIds(''), isNull);
      expect(validateMaxIds('1'), isNull);
      expect(validateMaxIds('100'), isNull);
      expect(validateMaxIds('0'), isNotNull);
      expect(validateMaxIds('101'), isNotNull);
      expect(validateMaxIds('abc'), isNotNull);
      expect(maxIdsBody(' '), '5');
      expect(maxIdsBody(' 7 '), '7');
    });
  });

  group('packages', () {
    test('ranges like the backend', () {
      expect(parsePackageForm('', '30', '0').error, 'Tên gói phải từ 1 đến 60 ký tự');
      expect(parsePackageForm('a' * 61, '30', '0').error, isNotNull);
      expect(parsePackageForm('x', '0', '0').error, 'Thời hạn phải từ 1 đến 3650 ngày');
      expect(parsePackageForm('x', '3651', '0').error, isNotNull);
      expect(parsePackageForm('x', '30', '-1').error, 'Giá không hợp lệ');
      expect(parsePackageForm('x', '30', '1000000001').error, isNotNull);
      final ok = parsePackageForm(' 2 tháng ', '60', '300000');
      expect(ok.error, isNull);
      expect(ok.body, {'label': '2 tháng', 'durationDays': 60, 'priceVnd': 300000});
    });
    test('duration text and usage', () {
      expect(formatDuration(365), '365 ngày (1 năm)');
      expect(formatDuration(90), '90 ngày (3 tháng)');
      expect(formatDuration(45), '45 ngày');
      expect(
        PackageItem.fromJson({
          'type': 'p',
          'label': 'L',
          'durationDays': 30,
          'priceVnd': 1,
          'active': false,
          'usage': {'users': 0, 'requests': 1, 'transactions': 0},
        }).inUse,
        isTrue,
      );
    });
  });

  group('security policy', () {
    test('ranges and cross-field rule', () {
      expect(const SecurityPolicyForm().validate(), isNull);
      expect(const SecurityPolicyForm(loginFreeAttempts: 2).validate(), contains('3 đến 20'));
      expect(const SecurityPolicyForm(loginFreeAttempts: 21).validate(), isNotNull);
      expect(const SecurityPolicyForm(loginBaseLockSeconds: 4).validate(), isNotNull);
      expect(const SecurityPolicyForm(loginBaseLockSeconds: 3601, loginMaxLockSeconds: 86400).validate(), isNotNull);
      expect(const SecurityPolicyForm(loginMaxLockSeconds: 29).validate(), isNotNull);
      expect(const SecurityPolicyForm(loginMaxLockSeconds: 86401).validate(), isNotNull);
      expect(const SecurityPolicyForm(tokenDays: 0).validate(), isNotNull);
      expect(const SecurityPolicyForm(tokenDays: 366).validate(), isNotNull);
      expect(const SecurityPolicyForm(autoLockMinutes: 0).validate(), isNull);
      expect(const SecurityPolicyForm(autoLockMinutes: 241).validate(), isNotNull);
      expect(const SecurityPolicyForm(loginBaseLockSeconds: 100, loginMaxLockSeconds: 50).validate(), 'Thời gian khoá tối đa không được nhỏ hơn thời gian khoá lần đầu');
    });
    test('json round trip incl. blurOnHideEnabled and example', () {
      final f = SecurityPolicyForm.fromJson({'blurOnHideEnabled': true, 'tokenDays': 7, 'watermarkEnabled': true});
      expect(f.blurOnHideEnabled, isTrue);
      expect(f.screenshotGuardEnabled, isTrue); // default kept
      expect(f.toJson()['blurOnHideEnabled'], true);
      expect(f.toJson().keys, hasLength(8));
      expect(f.withNumber('tokenDays', 9).tokenDays, 9);
      expect(const SecurityPolicyForm().lockExample, '30 giây → 1 phút → 2 phút → 4 phút');
      expect(const SecurityPolicyForm(loginBaseLockSeconds: 600, loginMaxLockSeconds: 900).lockExample, '10 phút → 15 phút → 15 phút → 15 phút');
    });
  });

  group('edit session', () {
    test('Sửa -> Huỷ restores, Lưu commits', () {
      final s = EditSession<BankForm>(const BankForm(bin: '1', account: 'a', holder: 'h'));
      expect(s.editing, isFalse);
      s.begin();
      expect(s.editing, isTrue);
      expect(s.dirty(const BankForm(bin: '1', account: 'b', holder: 'h')), isTrue);
      expect(s.dirty(const BankForm(bin: '1', account: 'a', holder: 'h')), isFalse);
      expect(s.cancel().account, 'a');
      expect(s.editing, isFalse);
      s.begin();
      s.commit(const BankForm(bin: '2'));
      expect(s.editing, isFalse);
      expect(s.saved.bin, '2');
    });
  });

  group('sections', () {
    test('only allowed pills', () {
      List<String> keys({bool st = false, bool sec = false, bool pol = false, bool bk = false, bool other = false}) =>
          settingsSections(settings: st, security: sec, policy: pol, backups: bk, hasOtherKeys: other).map((e) => e.key).toList();
      expect(keys(), isEmpty);
      expect(keys(st: true), ['payment', 'prices', 'limits']);
      expect(keys(sec: true, bk: true), ['security', 'backups']);
      expect(keys(st: true, sec: true, pol: true, bk: true, other: true), ['payment', 'prices', 'limits', 'security', 'policy', 'backups', 'other']);
      expect(keys(other: true), isEmpty);
    });
    test('other keys hide dedicated and internal ones', () {
      expect(otherSettingKeys({'bank_bin': '1', 'package_price_x': '1', 'unread_epoch': '1', 'max_virtual_ids': '5', 'lottery_payout_rate': '0.8'}), ['lottery_payout_rate']);
    });
    test('backup size', () {
      expect(formatBackupSize(100), '1 KB');
      expect(formatBackupSize(2048), '2 KB');
      expect(formatBackupSize(3 * 1024 * 1024), '3.0 MB');
    });
  });
}
