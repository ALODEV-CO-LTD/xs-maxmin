import test from 'node:test'
import assert from 'node:assert/strict'
import { buildQuery, hasFilter, formatMoney, viewFromSearch, csvFileName, STATUS_TABS, statusLabels, PAGE } from '../src/features/admin/paymentLogic.js'

test('buildQuery: trạng thái, tìm kiếm cắt khoảng trắng, khoảng ngày, phân trang', () => {
  assert.equal(buildQuery({ status: 'pending' }), 'status=pending')
  assert.equal(buildQuery({ status: 'all', q: '  an ', from: '2026-10-01', to: '2026-10-19' }, { limit: PAGE, offset: 30 }), 'status=all&q=an&from=2026-10-01&to=2026-10-19&limit=30&offset=30')
  assert.equal(buildQuery({ status: 'all', q: '   ' }), 'status=all')
})
test('bộ lọc, tiền, tab xem, tên file CSV', () => {
  assert.ok(!hasFilter({ q: '', from: '', to: '' }))
  assert.ok(hasFilter({ q: '', from: '2026-10-01', to: '' }))
  assert.match(formatMoney(1500000), /^1[., ]?500[., ]?000 đ$/)
  assert.equal(viewFromSearch('?view=renewals'), 'renewals')
  assert.equal(viewFromSearch('?view=x'), 'requests')
  assert.equal(viewFromSearch(''), 'requests')
  assert.equal(csvFileName(new Date('2026-10-19T05:00:00Z')), 'thanh-toan-2026-10-19.csv')
  assert.equal(STATUS_TABS.length, 5)
  assert.equal(statusLabels.cancelled, 'Người dùng huỷ')
})
