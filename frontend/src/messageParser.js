// Parses a pasted chat message ("Nhập từ tin nhắn", K13/K16) into candidate
// entry rows. Pure functions, no network, nothing is saved here: EntriesView
// shows the result as a preview and the user confirms before anything is
// stored. Lines the parser is not sure about are flagged `uncertain` (with
// `reasons`) so the UI can highlight them and leave them unticked.
//
// Understood layout (one or more per line, case/diacritic-insensitive):
//   [hạng mục]  số số số  [dấu điểm]  điểm
//   de 12 34 56 x 10         -> three "Đề" rows, 10 điểm each
//   lô 45,78 con 3           -> two "Lô" rows, 3 điểm each
//   12=50                    -> one row (type = sticky/default type, flagged if unknown)
//   de: / lo                 -> a line holding only a hạng mục sets the type for the lines below
// Per-customer template (`config`, saved only when the user confirms it):
//   { defaultType: 'de', typeAliases: { dd: 'de', l: 'lo' }, stakeMarkers: ['x', 'con'] }

export const DEFAULT_STAKE_MARKERS = ['x', '×', '*', 'con', '=', 'diem']

// Built-in spellings -> bet type key.
const BUILTIN_ALIASES = { de: 'de', dde: 'de', lo: 'lo' }

// lowercase + strip Vietnamese diacritics, keeping string length (so indexes
// found on the folded text are valid on the original).
export function fold(s) {
  return [...String(s).normalize('NFC').toLowerCase()]
    .map((ch) => (ch === 'đ' ? 'd' : ch.normalize('NFD').replace(/[̀-ͯ]/g, '')))
    .join('')
}

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

export function emptyTemplate() {
  return { defaultType: '', typeAliases: {}, stakeMarkers: [...DEFAULT_STAKE_MARKERS] }
}

// "dd=de, l=lo" <-> { dd: 'de', l: 'lo' } (used by the template editor)
export function aliasesToText(aliases) {
  return Object.entries(aliases || {})
    .map(([a, t]) => `${a}=${t}`)
    .join(', ')
}
export function textToAliases(text, validTypes) {
  const out = {}
  for (const part of String(text || '').split(/[,;\n]/)) {
    const [a, t] = part.split('=').map((x) => x.trim())
    if (a && t && (!validTypes || validTypes.includes(t))) out[fold(a)] = t
  }
  return out
}

export function parseMessage(text, { betTypes = ['de', 'lo'], template = null } = {}) {
  const cfg = { ...emptyTemplate(), ...(template || {}) }
  const markers = (cfg.stakeMarkers?.length ? cfg.stakeMarkers : DEFAULT_STAKE_MARKERS).map(fold)

  // alias (folded) -> type key; later sources win: built-in < bet types < template
  const aliasMap = { ...BUILTIN_ALIASES }
  for (const t of betTypes) aliasMap[fold(t)] = t
  for (const [a, t] of Object.entries(cfg.typeAliases || {})) aliasMap[fold(a)] = t
  const aliasKeys = Object.keys(aliasMap).filter(Boolean).sort((a, b) => b.length - a.length)
  const aliasRe = aliasKeys.length ? new RegExp(`(?<![a-z0-9])(${aliasKeys.map(escapeRe).join('|')})(?![a-z0-9])`, 'g') : null
  const stakeRe = new RegExp(`^(.*?)(?:${markers.map(escapeRe).join('|')})\\s*(\\d+(?:[.,]\\d+)?)\\s*(?:diem|d)?\\s*$`)

  const rows = []
  const ignored = []
  let stickyType = ''

  const push = (type, assumed, value, score, raw, extra = []) => {
    const reasons = [...extra]
    if (assumed) reasons.push('Chưa rõ hạng mục, tạm dùng mặc định')
    if (!score) reasons.push('Chưa có điểm')
    if (!/^\d{2}$/.test(value)) reasons.push('Số không phải 2 chữ số')
    rows.push({ type, value, score, raw, uncertain: reasons.length > 0, reasons })
  }

  for (const rawLine of String(text || '').split(/\r?\n/)) {
    const line = rawLine.trim()
    if (!line) continue
    const f = fold(line)

    // split the line into [type, text] segments at every hạng mục keyword
    const segments = []
    let last = 0
    let curType = null
    if (aliasRe) {
      for (const m of f.matchAll(aliasRe)) {
        const before = f.slice(last, m.index)
        if (before.trim() || curType) segments.push({ type: curType, text: before })
        curType = aliasMap[m[1]]
        last = m.index + m[0].length
      }
    }
    segments.push({ type: curType, text: f.slice(last) })

    let produced = false
    for (const seg of segments) {
      const body = seg.text.replace(/^[\s:.\-–]+|[\s:.\-–]+$/g, '')
      if (!/\d/.test(body)) {
        // keyword only ("de:", "lo") -> remember it for the following lines
        if (seg.type && !body) {
          stickyType = seg.type
          produced = true
        }
        continue
      }
      if (seg.type) stickyType = seg.type
      const type = seg.type || stickyType || cfg.defaultType || betTypes[0] || 'de'
      const assumed = !seg.type && !stickyType && !cfg.defaultType

      let left = body
      let score = ''
      const m = body.match(stakeRe)
      if (m) {
        left = m[1]
        score = m[2].replace(',', '.')
      }
      const extra = []
      if (/[^\d\s,.;\-/]/.test(left)) extra.push('Có ký tự lạ trong phần số')
      const numbers = left.match(/\d+/g) || []
      if (numbers.length === 0) {
        push(type, assumed, '', score, line, ['Không đọc được số'])
      } else {
        for (const n of numbers) push(type, assumed, n, score, line, extra)
      }
      produced = true
    }
    if (!produced) ignored.push(line)
  }
  return { rows, ignored }
}
