import test from 'node:test'
import assert from 'node:assert/strict'
import { BANKS, otherKeysOf, bankPayload, maxIdsPayload, packageBody, packageInUse, settingsTabs, formatDuration, lockExample, mins, policyBody, POLICY_DEFAULT, formatSize, bankFormOf } from '../src/features/admin/settingsLogic.js'

test('khoá khác: bỏ giá gói, app_, ngân hàng, giới hạn ID và dấu nội bộ', () => {
  const raw = { package_price_m1: '1', app_x: '1', bank_bin: '1', max_virtual_ids: '5', unread_epoch: '1', lottery_payout_rate: '80', zzz: '1' }
  assert.deepEqual(otherKeysOf(raw), ['lottery_payout_rate', 'zzz'])
})
test('form ngân hàng: cần đủ ba ô, tên ngân hàng lấy từ BIN', () => {
  assert.ok(bankPayload({ bank_bin: '', bank_account_number: '1', bank_account_holder: 'A' }).error)
  assert.ok(bankPayload({ bank_bin: '970436', bank_account_number: ' ', bank_account_holder: 'A' }).error)
  const ok = bankPayload({ bank_bin: '970436', bank_account_number: ' 123 ', bank_account_holder: ' NGUYEN A ' })
  assert.deepEqual(ok.body, { bank_bin: '970436', bank_name: 'Vietcombank', bank_account_number: '123', bank_account_holder: 'NGUYEN A' })
  assert.equal(BANKS.length, 20)
  assert.deepEqual(bankFormOf({}), { bank_bin: '', bank_account_number: '', bank_account_holder: '' })
})
test('giới hạn ID mặc định 5; gói dịch vụ', () => {
  assert.deepEqual(maxIdsPayload('  '), { max_virtual_ids: '5' })
  assert.deepEqual(maxIdsPayload(' 8 '), { max_virtual_ids: '8' })
  assert.deepEqual(packageBody({ label: ' 2 tháng ', durationDays: '60', priceVnd: '100000' }), { label: '2 tháng', durationDays: 60, priceVnd: 100000 })
  assert.ok(packageInUse({ usage: { users: 0, requests: 1, transactions: 0 } }))
  assert.ok(!packageInUse({ usage: { users: 0, requests: 0, transactions: 0 } }))
  assert.equal(formatDuration(365), '365 ngày (1 năm)')
  assert.equal(formatDuration(90), '90 ngày (3 tháng)')
  assert.equal(formatDuration(45), '45 ngày')
})
test('tab theo quyền', () => {
  const k = (o) => settingsTabs({ canSettings: false, canSecurity: false, canPolicy: false, canBackups: false, hasOther: false, ...o }).map((t) => t.key)
  assert.deepEqual(k({}), [])
  assert.deepEqual(k({ canSettings: true }), ['payment', 'prices', 'limits', 'appversion'])
  assert.deepEqual(k({ canSettings: true, hasOther: true, canBackups: true }), ['payment', 'prices', 'limits', 'appversion', 'backups', 'other'])
  assert.deepEqual(k({ canSecurity: true, canPolicy: true }), ['security', 'policy'])
  assert.deepEqual(k({ hasOther: true }), []) // "Khoá khác" cần settings.manage
})
test('chính sách bảo mật: ví dụ khoá liên tiếp và thân PUT', () => {
  assert.equal(mins(30), '30 giây')
  assert.equal(mins(120), '2 phút')
  assert.equal(lockExample(30, 900), '30 giây → 1 phút → 2 phút → 4 phút')
  assert.equal(lockExample(300, 600), '5 phút → 10 phút → 10 phút → 10 phút')
  const b = policyBody({ ...POLICY_DEFAULT, tokenDays: '14', watermarkEnabled: true })
  assert.equal(b.tokenDays, 14)
  assert.equal(b.watermarkEnabled, true)
  assert.equal(b.screenshotGuardEnabled, true)
})
test('dung lượng sao lưu', () => {
  assert.equal(formatSize(100), '1 KB')
  assert.equal(formatSize(2048), '2 KB')
  assert.equal(formatSize(3 * 1024 * 1024), '3.0 MB')
})
