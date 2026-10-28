// Chạy: cd web-next && npm test
// Thẻ "Thiết bị nhắn tin" (cùng chữ với app: app/test/chat_devices_card_test.dart).
import test from 'node:test'
import assert from 'node:assert/strict'
import { canRemoveChatDevice, chatDeviceName, chatDeviceRemoveMessage } from '../src/features/account/chatDevicesLogic.js'

test('tên thiết bị: 4 ký tự cuối của mã, viết hoa; khoá chung có tên riêng', () => {
  assert.equal(chatDeviceName({ id: 'a1b2c3d48f2k' }), 'Thiết bị ·8F2K')
  assert.equal(chatDeviceName({ id: 'ab' }), 'Thiết bị ·AB')
  assert.equal(chatDeviceName({ id: 'legacy' }), 'Trình duyệt web / bản app cũ (một khoá chung)')
})

test('khoá chung không xoá được từ web (chính trình duyệt này dùng nó); máy khác xoá được', () => {
  assert.equal(canRemoveChatDevice({ id: 'legacy' }), false)
  assert.equal(canRemoveChatDevice({ id: 'abcd1234' }), true)
})

test('lời nhắc khi xoá nêu đúng tên máy', () => {
  assert.match(chatDeviceRemoveMessage({ id: 'zzzz9999' }), /"Thiết bị ·9999"/)
})
