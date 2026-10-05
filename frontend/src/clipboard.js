// Copying entry data to the clipboard (K18), shared by EntriesView and
// CustomersView. Entry data is sensitive (money), so the user can turn on
// "ask before copying": the preference lives in localStorage.
import { showConfirm } from './confirm'
import { betTypeLabel } from './betTypes'

const KEY = 'xoso_confirm_copy'

export function confirmCopyEnabled() {
  try {
    return localStorage.getItem(KEY) === '1'
  } catch {
    return false
  }
}
export function setConfirmCopy(on) {
  try {
    localStorage.setItem(KEY, on ? '1' : '0')
  } catch {
    /* ignore */
  }
}

/** Plain-text table of entries: one line per record, tab separated. */
export function entriesToText(entries, { withCustomer = false } = {}) {
  const head = [...(withCustomer ? ['Khách hàng'] : []), 'Ngày', 'Hạng mục', 'Số', 'Điểm vào', 'Điểm ra', 'Ghi chú']
  const lines = [head.join('\t')]
  for (const e of entries) {
    lines.push(
      [
        ...(withCustomer ? [e.customerName || ''] : []),
        e.entryDate || '',
        betTypeLabel(e.betType || 'de'),
        e.value || '',
        e.score || '',
        e.result || '',
        (e.note || '').replace(/\s+/g, ' '),
      ].join('\t'),
    )
  }
  return lines.join('\n')
}

async function writeClipboard(text) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(text)
    return
  }
  // fallback for insecure origins / old browsers
  const ta = document.createElement('textarea')
  ta.value = text
  ta.style.position = 'fixed'
  ta.style.opacity = '0'
  document.body.appendChild(ta)
  ta.select()
  const ok = document.execCommand('copy')
  document.body.removeChild(ta)
  if (!ok) throw new Error('copy failed')
}

/** Copies `entries`; asks first when the user enabled the confirmation.
 *  Resolves 'copied' | 'cancelled' | 'failed'. */
export async function copyEntries(entries, { label = '', withCustomer = false } = {}) {
  if (!entries.length) return 'failed'
  if (confirmCopyEnabled()) {
    const ok = await showConfirm({
      title: 'Sao chép số liệu',
      message: `Sao chép ${entries.length} số liệu${label ? ` (${label})` : ''} vào bộ nhớ tạm? Dữ liệu này nhạy cảm, chỉ dán ở nơi bạn tin tưởng.`,
      confirmText: 'Sao chép',
    })
    if (!ok) return 'cancelled'
  }
  try {
    await writeClipboard(entriesToText(entries, { withCustomer }))
    return 'copied'
  } catch {
    return 'failed'
  }
}
