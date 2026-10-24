import test from 'node:test'
import assert from 'node:assert/strict'
import { applyNotices, useMaintenanceStore, DEFAULT_MAINTENANCE_MESSAGE } from '../src/lib/maintenanceStore.js'

test('bảo trì: bật thì giữ lời nhắn của Admin, tắt thì xoá, trống thì dùng câu mặc định', () => {
  applyNotices({ enabled: true, message: '  Bảo trì 23h  ' })
  assert.equal(useMaintenanceStore.getState().message, 'Bảo trì 23h')
  applyNotices({ enabled: true, message: '' })
  assert.equal(useMaintenanceStore.getState().message, DEFAULT_MAINTENANCE_MESSAGE)
  applyNotices({ enabled: false, message: 'x' })
  assert.equal(useMaintenanceStore.getState().message, null)
  applyNotices(undefined)
  assert.equal(useMaintenanceStore.getState().message, null)
})
