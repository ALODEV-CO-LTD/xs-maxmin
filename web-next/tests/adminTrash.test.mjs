// Chạy: cd web-next && npm test
// Thùng rác Admin + khôi phục dữ liệu một khách (cùng chữ với app: app/test/admin_trash_restore_test.dart).
import test from 'node:test'
import assert from 'node:assert/strict'
import { backupSourceLabel, canRestoreCustomer, countsSummary, customerTitle, filterBackupCustomers, restoreResultText, timeLeft, trashKindIcon, trashKindLabel } from '../src/features/admin/trashLogic.js'

test('nhãn loại mục trong thùng rác; loại lạ giữ nguyên tên', () => {
  assert.equal(trashKindLabel('user'), 'Tài khoản khách hàng')
  assert.equal(trashKindLabel('staff'), 'Tài khoản nhân viên')
  assert.equal(trashKindLabel('announcement'), 'Thông báo')
  assert.equal(trashKindLabel('package'), 'Gói dịch vụ')
  assert.equal(trashKindLabel('setting'), 'Cài đặt')
  assert.equal(trashKindLabel('khac'), 'khac')
  assert.equal(trashKindIcon('user'), 'users')
  assert.equal(trashKindIcon('khac'), 'settings')
})

test('tóm tắt số lượng theo thứ tự cố định, bỏ số 0, bảng lạ hiện tên bảng', () => {
  assert.equal(countsSummary({ lottery_results: 85, customers: 2, data_entries: 19 }), '2 khách hàng · 19 số liệu · 85 kết quả xổ số')
  assert.equal(countsSummary({ customers: 0, data_entries: 0 }), '')
  assert.equal(countsSummary({ bang_la: 3, customers: 1 }), '1 khách hàng · 3 bang_la')
  assert.equal(countsSummary(undefined), '')
})

test('còn bao nhiêu ngày', () => {
  assert.equal(timeLeft(7), 'Còn 7 ngày')
  assert.equal(timeLeft(2), 'Còn 2 ngày')
  assert.equal(timeLeft(1), 'Còn dưới 1 ngày')
  assert.equal(timeLeft(0), 'Còn dưới 1 ngày')
})

test('nguồn bản sao lưu', () => {
  assert.equal(backupSourceLabel('cron'), 'Tự động hằng ngày')
  assert.equal(backupSourceLabel('manual'), 'Tạo trong app')
})

test('tìm khách trong bản sao lưu theo tên đăng nhập hoặc tên', () => {
  const list = [{ id: '1', username: 'an', name: 'Nguyễn An' }, { id: '2', username: 'binh', name: '' }]
  assert.deepEqual(filterBackupCustomers(list, '').map((c) => c.id), ['1', '2'])
  assert.deepEqual(filterBackupCustomers(list, 'nguyễn').map((c) => c.id), ['1'])
  assert.deepEqual(filterBackupCustomers(list, ' BINH ').map((c) => c.id), ['2'])
  assert.deepEqual(filterBackupCustomers(list, 'zzz'), [])
  assert.equal(customerTitle(list[0]), 'an (Nguyễn An)')
  assert.equal(customerTitle(list[1]), 'binh')
})

test('chỉ khôi phục được tài khoản còn tồn tại; chế độ thay thế phải gõ đúng tên đăng nhập', () => {
  const c = { id: '1', username: 'An', name: '', now: { customers: 1 } }
  assert.equal(canRestoreCustomer({ customer: null }), false)
  assert.equal(canRestoreCustomer({ customer: { ...c, now: null } }), false) // tài khoản đã bị xoá: dùng Thùng rác
  assert.equal(canRestoreCustomer({ customer: c, replace: false }), true)
  assert.equal(canRestoreCustomer({ customer: c, replace: false, working: true }), false)
  assert.equal(canRestoreCustomer({ customer: c, replace: true, confirmText: '' }), false)
  assert.equal(canRestoreCustomer({ customer: c, replace: true, confirmText: 'sai' }), false)
  assert.equal(canRestoreCustomer({ customer: c, replace: true, confirmText: ' an ' }), true) // không phân biệt hoa thường
})

test('dòng kết quả sau khi khôi phục', () => {
  const c = { id: '1', username: 'an', name: 'Nguyễn An' }
  assert.equal(restoreResultText(c, { data_entries: 5 }, 'safety.db'), 'Đã khôi phục cho an (Nguyễn An): đã ghi 5 số liệu. Đã tạo thêm bản sao lưu an toàn safety.db trước khi làm.')
  assert.match(restoreResultText(c, {}, 'x'), /không có dòng nào cần thêm/)
})
