import test from 'node:test'
import assert from 'node:assert/strict'
import { buildTabs, resolveTab, nextTabKey, kindLabel } from '../src/features/admin/noticesLogic.js'

test('tab theo quyền: thông báo và bảo trì tách riêng', () => {
  assert.deepEqual(buildTabs({ canAnnounce: true, canMaintenance: true, sentCount: 3 }).map((t) => t.key), ['sent', 'compose', 'maintenance'])
  assert.equal(buildTabs({ canAnnounce: true, canMaintenance: false, sentCount: 3 })[0].label, 'Đã gửi (3)')
  assert.deepEqual(buildTabs({ canAnnounce: false, canMaintenance: true }).map((t) => t.key), ['maintenance'])
  assert.deepEqual(buildTabs({ canAnnounce: false, canMaintenance: false }), [])
})
test('?tab= không hợp lệ hoặc không có quyền thì về tab đầu', () => {
  const tabs = buildTabs({ canAnnounce: false, canMaintenance: true })
  assert.equal(resolveTab(tabs, 'compose'), 'maintenance')
  assert.equal(resolveTab(tabs, undefined), 'maintenance')
  assert.equal(resolveTab([], 'x'), undefined)
})
test('phím mũi tên chuyển tab vòng tròn', () => {
  const tabs = buildTabs({ canAnnounce: true, canMaintenance: true })
  assert.equal(nextTabKey(tabs, 'maintenance', 'ArrowRight'), 'sent')
  assert.equal(nextTabKey(tabs, 'sent', 'ArrowLeft'), 'maintenance')
  assert.equal(nextTabKey(tabs, 'sent', 'Enter'), null)
  assert.equal(kindLabel('policy'), 'Đổi chính sách')
  assert.equal(kindLabel('zzz'), 'zzz')
})
