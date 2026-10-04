// Promise-based confirmation dialog (replaces window.confirm).
//
//   import { showConfirm } from '../confirm'
//   if (!(await showConfirm({ title: 'Xoá', message: '...', confirmText: 'Xoá', danger: true }))) return
//
// The dialog itself is <ConfirmDialog /> (mounted once in AppShell); this
// module only holds its state. Opening a second dialog while one is showing
// cancels the first (resolves false).
import { reactive } from 'vue'

export const confirmState = reactive({
  open: false,
  title: '',
  message: '',
  confirmText: 'Đồng ý',
  cancelText: 'Huỷ',
  danger: false,
})

let resolver = null

export function showConfirm({ title = 'Xác nhận', message = '', confirmText = 'Đồng ý', cancelText = 'Huỷ', danger = false } = {}) {
  if (resolver) resolver(false)
  Object.assign(confirmState, { open: true, title, message, confirmText, cancelText, danger })
  return new Promise((resolve) => {
    resolver = resolve
  })
}

export function resolveConfirm(value) {
  confirmState.open = false
  const r = resolver
  resolver = null
  if (r) r(value)
}
