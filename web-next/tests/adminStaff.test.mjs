import test from 'node:test'
import assert from 'node:assert/strict'
import { PRESETS, togglePerm, samePerms, canSavePerms } from '../src/features/admin/staffLogic.js'

test('togglePerm thêm/bớt quyền và không đổi mảng gốc', () => {
  const a = ['users.view']
  assert.deepEqual(togglePerm(a, 'stats.view'), ['users.view', 'stats.view'])
  assert.deepEqual(togglePerm(a, 'users.view'), [])
  assert.deepEqual(a, ['users.view'])
})
test('samePerms bỏ qua thứ tự; canSavePerms cần có quyền và có thay đổi', () => {
  assert.ok(samePerms(['a', 'b'], ['b', 'a']))
  assert.ok(!samePerms(['a'], ['a', 'b']))
  assert.ok(!canSavePerms([], ['a']))
  assert.ok(!canSavePerms(['a'], ['a']))
  assert.ok(canSavePerms(['a', 'b'], ['a']))
})
test('hai mẫu chọn nhanh', () => {
  assert.deepEqual(PRESETS.map((p) => p.label), ['Chăm sóc khách hàng', 'Quản lý hệ thống'])
  assert.ok(PRESETS[0].keys.includes('support.messages'))
})
