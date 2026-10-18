// Copying entry data to the clipboard (K18), shared by EntriesView and CustomersView.
import { betTypeLabel } from './betTypes'

// "Ask before copying" was removed: copying never asks. An old setting saved by an earlier version is forgotten.
try {
  localStorage.removeItem('xoso_confirm_copy')
} catch {
  /* ignore */
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

const escHtml = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')

/** The same table as HTML where every cell is formatted as TEXT
 *  (mso-number-format), so Excel keeps "05" instead of turning it into 5.
 *  Plain-text targets still get the tab separated text. */
function textToHtml(text) {
  const rows = text.split('\n').map((line) => {
    const cells = line.split('\t').map((c) => `<td style="mso-number-format:'\\@'">${escHtml(c)}</td>`)
    return `<tr>${cells.join('')}</tr>`
  })
  return `<table>${rows.join('')}</table>`
}

// last resort for insecure origins / old browsers / a refused permission
function execCommandCopy(text) {
  const ta = document.createElement('textarea')
  ta.value = text
  ta.setAttribute('readonly', '')
  ta.style.position = 'fixed'
  ta.style.opacity = '0'
  document.body.appendChild(ta)
  ta.select()
  let ok = false
  try {
    ok = document.execCommand('copy')
  } finally {
    document.body.removeChild(ta)
  }
  if (!ok) throw new Error('copy failed')
}

async function writeClipboard(text) {
  // 1) rich copy (text + HTML with text-formatted cells) so leading zeros survive in Excel
  if (navigator.clipboard?.write && typeof ClipboardItem !== 'undefined') {
    try {
      await navigator.clipboard.write([
        new ClipboardItem({
          'text/plain': new Blob([text], { type: 'text/plain' }),
          'text/html': new Blob([textToHtml(text)], { type: 'text/html' }),
        }),
      ])
      return
    } catch {
      /* fall through to plain text */
    }
  }
  // 2) plain text
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text)
      return
    } catch {
      /* permission refused: fall through */
    }
  }
  // 3) execCommand fallback (throws if that fails too)
  execCommandCopy(text)
}

/** Copies `entries`. Resolves 'copied' | 'failed'. */
export async function copyEntries(entries, { withCustomer = false } = {}) {
  if (!entries.length) return 'failed'
  try {
    await writeClipboard(entriesToText(entries, { withCustomer }))
    return 'copied'
  } catch {
    return 'failed'
  }
}
