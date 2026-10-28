// Chạy: cd web-next && npm test
// Màn khoá báo số lần sai và đếm ngược (cùng chữ với app: app/test/lock_attempts_test.dart).
import test from 'node:test'
import assert from 'node:assert/strict'
import { formatLockWait, lockLeftAt, lockSeconds, wrongMessage } from '../src/lib/lockAttempts.js'

test('thời gian chờ: giây, phút, phút + giây', () => {
  assert.equal(formatLockWait(45), '45 giây')
  assert.equal(formatLockWait(59), '59 giây')
  assert.equal(formatLockWait(60), '1 phút')
  assert.equal(formatLockWait(65), '1 phút 05 giây')
  assert.equal(formatLockWait(125), '2 phút 05 giây')
  assert.equal(formatLockWait(900), '15 phút')
  assert.equal(formatLockWait(0), '0 giây')
  assert.equal(formatLockWait(-3), '0 giây')
})

test('sai mật khẩu: đã sai X/Y lần, còn N lần trước khi bị khoá', () => {
  const d = { failedAttempts: 3, maxAttempts: 5, attemptsLeft: 2 }
  assert.equal(wrongMessage('Mật khẩu không đúng', d), 'Mật khẩu không đúng. Đã sai 3/5 lần. Còn 2 lần thử trước khi bị khoá tạm.')
  assert.equal(wrongMessage('Mật khẩu không đúng', { failedAttempts: 4, maxAttempts: 5, attemptsLeft: 1 }), 'Mật khẩu không đúng. Đã sai 4/5 lần. Còn 1 lần thử trước khi bị khoá tạm.')
  assert.equal(wrongMessage('Mật khẩu không đúng', { failedAttempts: 5, maxAttempts: 5, attemptsLeft: 0 }), 'Mật khẩu không đúng. Đã sai 5/5 lần. Lần sai tiếp theo sẽ bị khoá tạm.')
})

test('máy chủ cũ không trả số lần: giữ nguyên câu của máy chủ', () => {
  assert.equal(wrongMessage('Mật khẩu không đúng', null), 'Mật khẩu không đúng')
  assert.equal(wrongMessage('Mật khẩu không đúng', { failedAttempts: 1 }), 'Mật khẩu không đúng')
})

test('số giây bị khoá: retryAfterSeconds, rồi chữ trong câu, rồi 30', () => {
  assert.equal(lockSeconds('x', { retryAfterSeconds: 125 }), 125)
  assert.equal(lockSeconds('x', { retryAfterSeconds: 0 }), 1)
  assert.equal(lockSeconds('Vui lòng thử lại sau 45 giây.', null), 45)
  assert.equal(lockSeconds('lỗi lạ', undefined), 30)
})

test('đếm ngược theo đồng hồ, làm tròn lên, không âm', () => {
  const t0 = 1_000_000
  assert.equal(lockLeftAt(t0 + 30_000, t0), 30)
  assert.equal(lockLeftAt(t0 + 30_000, t0 + 1_200), 29) // 28,8 giây còn lại: hiện 29
  assert.equal(lockLeftAt(t0 + 30_000, t0 + 30_000), 0)
  assert.equal(lockLeftAt(t0 + 30_000, t0 + 99_000), 0)
})
