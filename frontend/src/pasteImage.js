// Paste an image into the OCR areas (Nhập số, Nhập kết quả): Ctrl/Cmd+V anywhere on the page while the area is
// shown, or the "Dán ảnh" button (asks the browser for the clipboard). Only pictures are taken; ordinary text pastes
// into inputs are left alone.
import { onBeforeUnmount, onMounted } from 'vue'

const isImage = (f) => f && /^image\//.test(f.type)

// The first picture in a paste event, or null.
export function imageFromPasteEvent(e) {
  const files = [...(e.clipboardData?.files || [])]
  const direct = files.find(isImage)
  if (direct) return direct
  for (const item of e.clipboardData?.items || []) {
    if (item.kind === 'file' && /^image\//.test(item.type)) return item.getAsFile()
  }
  return null
}

// Calls `handler(file)` for every image pasted while `isActive()` is true. Registers on mount, removes on unmount.
export function usePasteImage(handler, isActive = () => true) {
  const onPaste = (e) => {
    if (!isActive()) return
    const file = imageFromPasteEvent(e)
    if (!file) return
    e.preventDefault()
    handler(file)
  }
  onMounted(() => document.addEventListener('paste', onPaste))
  onBeforeUnmount(() => document.removeEventListener('paste', onPaste))
}

// Reads a picture from the clipboard on a button press (needs a secure page: https or localhost, and the browser may
// ask permission). Resolves a File, or throws an Error with a message for the user.
export async function readClipboardImage() {
  if (!navigator.clipboard?.read) {
    throw new Error('Trình duyệt này không cho đọc ảnh từ bộ nhớ tạm bằng nút. Hãy bấm Ctrl+V (hoặc Cmd+V) để dán ảnh.')
  }
  let items
  try {
    items = await navigator.clipboard.read()
  } catch {
    throw new Error('Không đọc được bộ nhớ tạm (chưa cho phép hoặc trang không an toàn). Hãy bấm Ctrl+V (hoặc Cmd+V) để dán ảnh.')
  }
  for (const item of items) {
    const type = item.types.find((t) => t.startsWith('image/'))
    if (type) {
      const blob = await item.getType(type)
      return new File([blob], `anh-dan.${type.split('/')[1] || 'png'}`, { type })
    }
  }
  throw new Error('Bộ nhớ tạm chưa có ảnh. Hãy chụp màn hình hoặc sao chép một ảnh rồi dán lại.')
}
