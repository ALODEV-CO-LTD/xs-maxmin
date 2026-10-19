import test from 'node:test'
import assert from 'node:assert/strict'
import { generatePassword, listPath, lockConfirm, mergeRow, statusLabel, supportBody, supportNoteOf } from '../src/features/admin/usersLogic.js'

test('mật khẩu ngẫu nhiên: 10 ký tự, vị trí 4 và 8 là chữ số, không có ký tự dễ nhầm', () => {
  for (let k = 0; k < 50; k++) {
    const pw = generatePassword(Uint32Array.from({ length: 10 }, () => Math.floor(Math.random() * 2 ** 32)))
    assert.equal(pw.length, 10)
    assert.match(pw[3], /[2-9]/)
    assert.match(pw[7], /[2-9]/)
    assert.doesNotMatch(pw, /[Il1O0o]/)
  }
  assert.equal(generatePassword(new Uint32Array(10)).length, 10) // dùng crypto khi không truyền
})
test('đường dẫn danh sách mã hoá từ khoá', () => {
  assert.equal(listPath(''), '/admin/users')
  assert.equal(listPath('lê hoa&x'), '/admin/users?q=l%C3%AA%20hoa%26x')
})
test('hộp xác nhận khoá / mở khoá', () => {
  const lock = lockConfirm({ name: 'An', accountLocked: false })
  assert.equal(lock.title, 'Khoá tài khoản')
  assert.ok(lock.danger)
  assert.match(lock.message, /"An"/)
  const unlock = lockConfirm({ name: 'An', accountLocked: true })
  assert.equal(unlock.confirmText, 'Mở khoá')
  assert.ok(!unlock.danger)
})
test('hỗ trợ khôi phục và gộp dòng danh sách', () => {
  assert.deepEqual(supportBody('code'), { reissueRecoveryCode: true })
  assert.deepEqual(supportBody('unlock'), { clearLockouts: true })
  assert.match(supportNoteOf('code'), /mã khôi phục mới/)
  assert.match(supportNoteOf('unlock'), /gỡ mọi khoá/)
  const l = mergeRow([{ id: '1', name: 'a', accountLocked: false }, { id: '2', name: 'b' }], { id: '1', accountLocked: true })
  assert.deepEqual(l[0], { id: '1', name: 'a', accountLocked: true })
  assert.equal(l[1].name, 'b')
  assert.equal(statusLabel('active'), 'Hoạt động')
  assert.equal(statusLabel('expired'), 'Hết hạn')
})
