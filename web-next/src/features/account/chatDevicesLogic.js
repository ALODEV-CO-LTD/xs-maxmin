// Pure helpers of the "Thiết bị nhắn tin" card (Tài khoản > Thiết bị & riêng tư). Same texts as the app
// (app/lib/features/account/account_devices_tab.dart). API: GET /me/e2ee-devices, DELETE /me/e2ee-devices/:id

/** The id the server gives the single key that older versions (and this web) publish: it can't be removed from here. */
export const LEGACY_DEVICE_ID = 'legacy'

/** "Thiết bị ·8F2K" (the last characters of its random id), or the shared-key entry. */
export function chatDeviceName(d) {
  const id = String(d?.id ?? '')
  if (id === LEGACY_DEVICE_ID) return 'Trình duyệt web / bản app cũ (một khoá chung)'
  return `Thiết bị ·${(id.length > 4 ? id.slice(-4) : id).toUpperCase()}`
}

/** A device can be removed unless it is the shared key (the web itself uses it: removing it would cut this browser off). */
export const canRemoveChatDevice = (d) => String(d?.id ?? '') !== LEGACY_DEVICE_ID

export const CHAT_DEVICES_INTRO = 'Mỗi thiết bị có khoá mã hoá riêng; bạn bè mã hoá từng tin cho từng thiết bị của bạn. Máy bị mất có thể xoá ở đây.'
export const chatDeviceRemoveMessage = (d) => `Bạn bè sẽ không mã hoá tin nhắn gửi cho "${chatDeviceName(d)}" nữa, máy đó không nhận được tin mới. Nếu máy đó vẫn đang dùng, nó tự đăng ký lại khi mở app.`
