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
// Compact ("liền") notation from docs "Cấu hình tính toán" - number + symbol + điểm, no spaces:
//   20lo100 70lo500   -> Lô 20 @100, Lô 70 @500       (symbols l, lo, lô, x)
//   20dau10 20c10     -> Đầu 20 @10, Đuôi 20 @10       (d, dau, đầu / c, cuoi, cuối)
//   20d10c20          -> Đầu 20 @10 AND Đuôi 20 @20
//   123x100 5000x100  -> 3 càng / 4 càng (by number of digits)
//   20x02lo10         -> Xiên 2 (20 + 02 @10); dotted "20.02x10" only when the account has a Xiên type
// Rows whose bet type the account does not have are flagged (and left unticked), never silently
// saved. `decodeMessage` shows each compact token in its canonical spelling ("20lo100" -> "20lô100")
// for the side-by-side check; it never changes a number.
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

// ---- Compact notation ---------------------------------------------------------------------
const POINTS_RE = '(\\d+(?:[.,]\\d+)?)'
const BARE_X = ['x', '×'] // as a symbol = bao lô; the legacy parser reads it as "× điểm" with the customer's type
const TYPE_LABEL = { lo: 'Lô', dau: 'Đầu', duoi: 'Đuôi', cang3: '3 càng', cang4: '4 càng', xien2: 'Xiên 2', xien3: 'Xiên 3', xien4: 'Xiên 4' }
const CANON_SYMBOL = { lo: 'lô', dau: 'đầu', duoi: 'đuôi', cang: 'càng', xien: 'xiên' }
export const typeLabel = (t) => TYPE_LABEL[t] || t

// folded symbol -> { kind, type? }. Built-ins first, then spelled bet types ("de", custom keys), then the
// customer's own aliases (they win, like everywhere else in this file).
function compactSymbols(aliasMap, cfg) {
  const m = new Map()
  for (const s of ['lo', 'l', 'x', '×']) m.set(s, { kind: 'lo' })
  for (const s of ['d', 'dau']) m.set(s, { kind: 'dau' })
  for (const s of ['c', 'cuoi', 'duoi']) m.set(s, { kind: 'duoi' })
  // Ký hiệu the customer set in the bảng cấu hình (Cấu hình tính điểm): they add to the built-in spellings.
  for (const [kind, list] of Object.entries(cfg.kindSymbols || {})) {
    for (const sym of list || []) {
      const k = fold(sym)
      if (/^[a-z×]+$/.test(k)) m.set(k, { kind })
    }
  }
  m.set('cang', { kind: 'cang' })
  m.set('xien', { kind: 'xien' })
  for (const [a, t] of Object.entries(aliasMap)) if (/^[a-z]+$/.test(a) && !m.has(a)) m.set(a, { kind: 'custom', type: t })
  for (const [a, t] of Object.entries(cfg.typeAliases || {})) {
    const k = fold(a)
    if (/^[a-z×]+$/.test(k)) m.set(k, t === 'lo' ? { kind: 'lo' } : { kind: 'custom', type: t })
  }
  return m
}

// Returns compact(token, ctxType) -> { rows, canon } | null for one FOLDED whitespace-free token.
// null = "not compact notation": the caller falls back to the legacy parser, so nothing that worked before changes.
function makeCompactParser(symbols, betTypes) {
  const alt = (pred) =>
    [...symbols.entries()].filter(([k, v]) => pred(v, k)).map(([k]) => k).sort((a, b) => b.length - a.length).map(escapeRe).join('|')
  const all = alt(() => true)
  const lo = alt((v) => v.kind === 'lo')
  const reXien = lo ? new RegExp(`^(\\d{2}(?:(?:[.,]|${lo})\\d{2}){1,})(${lo}|xien)${POINTS_RE}$`) : null
  // "22.67lo10" / "81.24.69lo10": several numbers of the same length joined by dots (or commas), one symbol and one điểm for all.
  const allNoX = alt((v, k) => !BARE_X.includes(k)) // "20.02x10" stays with the legacy reading (x = × điểm)
  const reListDouble = new RegExp(`^(\\d{2,4}(?:[.,]\\d{2,4})+)(${allNoX})${POINTS_RE}(${allNoX})${POINTS_RE}$`)
  const reList = new RegExp(`^(\\d{2,4}(?:[.,]\\d{2,4})+)(${allNoX})${POINTS_RE}$`)
  const reDouble = new RegExp(`^(\\d+)(${all})${POINTS_RE}(${all})${POINTS_RE}$`)
  const reSingle = new RegExp(`^(\\d+)(${all})${POINTS_RE}$`)
  const has = (t) => betTypes.includes(t)

  // One "number + symbol + điểm" instruction -> row + canonical text, or null.
  const one = (value, sym, points, ctxType) => {
    const info = symbols.get(sym)
    const digits = value.length
    let type
    let canonSym
    if (info.kind === 'lo') {
      if (BARE_X.includes(sym) && digits === 2 && ctxType) { type = ctxType; canonSym = sym } // legacy meaning kept
      else if (digits === 3) { type = 'cang3'; canonSym = CANON_SYMBOL.cang }
      else if (digits === 4) { type = 'cang4'; canonSym = CANON_SYMBOL.cang }
      else { type = 'lo'; canonSym = CANON_SYMBOL.lo }
    } else if (info.kind === 'dau') { type = 'dau'; canonSym = CANON_SYMBOL.dau }
    else if (info.kind === 'duoi') {
      // "Đuôi" = the last two digits of the special prize, which is exactly what the account's Đề already is.
      type = has('duoi') ? 'duoi' : has('de') ? 'de' : 'duoi'
      canonSym = CANON_SYMBOL.duoi
    } else if (info.kind === 'cang') {
      type = digits === 4 ? 'cang4' : 'cang3'
      canonSym = CANON_SYMBOL.cang
    } else if (info.kind === 'xien') return null // a single number cannot be a xiên
    else { type = info.type; canonSym = sym }

    const reasons = []
    if (!has(type)) reasons.push(`Loại "${typeLabel(type)}" chưa có trong cấu hình`)
    const want = type === 'cang3' ? 3 : type === 'cang4' ? 4 : 2
    if (digits !== want) reasons.push(`Số không phải ${want} chữ số`)
    return { row: { type, value, score: points.replace(',', '.'), reasons }, canon: `${value}${canonSym}${points}` }
  }

  const run = (tok, ctxType = '') => {
    let m = reXien && tok.match(reXien)
    if (m) {
      const nums = m[1].match(/\d{2}/g)
      const dotsOnly = !/[a-z×]/.test(m[1])
      const type = `xien${nums.length}`
      // "20.02x10" is also how some customers list several plain numbers, so it only means xiên when the
      // account has that Xiên type; "20x02lo10" / "20.02xiên10" cannot mean anything else.
      // "22.67lo10" (numbers joined by dots, then a spelled lô symbol and điểm) is a xiên: 2 numbers = xiên 2, 3 = xiên 3, 4 = xiên 4.
      // More than 4 numbers is not a xiên the system knows: it is kept as one flagged row for the user to check.
      const spelledLo = dotsOnly && !BARE_X.includes(m[2]) && symbols.get(m[2])?.kind === 'lo'
      if (spelledLo || !(dotsOnly && m[2] !== 'xien' && !has(type))) {
        const reasons = [
          ...(nums.length > 4 ? [`Xiên ${nums.length} số: hệ thống chỉ có xiên 2, 3, 4, hãy kiểm tra`] : []),
          ...(has(type) ? [] : [`Loại "${typeLabel(type)}" chưa có trong cấu hình`]),
        ]
        return {
          rows: [{ type, value: nums.join(' '), score: m[3].replace(',', '.'), reasons }],
          canon: `${nums.join('.')}${CANON_SYMBOL.xien}${m[3]}`,
        }
      }
    }
    m = tok.match(reListDouble)
    if (m) {
      const nums = m[1].split(/[.,]/)
      // (a lô symbol after several 2-digit numbers is a xiên, handled above: no list of numbers with two symbols)
      if (nums.every((n) => n.length === nums[0].length) && !(nums[0].length === 2 && [m[2], m[4]].some((x) => symbols.get(x)?.kind === 'lo'))) {
        const made = nums.flatMap((n) => [one(n, m[2], m[3], ctxType), one(n, m[4], m[5], ctxType)])
        if (made.every(Boolean)) return { rows: made.map((x) => x.row), canon: made.map((x) => x.canon).join(' ') }
      }
    }
    m = tok.match(reList)
    if (m) {
      const nums = m[1].split(/[.,]/)
      if (nums.every((n) => n.length === nums[0].length)) {
        const made = nums.map((n) => one(n, m[2], m[3], ctxType))
        if (made.every(Boolean)) return { rows: made.map((x) => x.row), canon: made.map((x) => x.canon).join(' ') }
      }
    }
    m = tok.match(reDouble)
    if (m) {
      const a = one(m[1], m[2], m[3], ctxType)
      const b = one(m[1], m[4], m[5], ctxType)
      if (a && b) return { rows: [a.row, b.row], canon: `${a.canon} ${b.canon}` }
    }
    m = tok.match(reSingle)
    if (m) {
      const a = one(m[1], m[2], m[3], ctxType)
      if (a) return { rows: [a.row], canon: a.canon }
    }
    return null
  }

  // Loosely written compact notation -> the strict spelling the matchers above read: groups divided by ; / | or " - ",
  // numbers of one group divided by spaces, dots, commas or dashes, the symbol / điểm separated by spaces or followed by "điểm".
  // "22 67 lo 10; 50-65 lô 20" -> "22.67lo10 50.65lo20". Bare x / × is left alone (the legacy parser owns "× điểm").
  const symAlt = alt((v, k) => !BARE_X.includes(k))
  const reGroup = symAlt
    ? new RegExp(`(?<![\\d.,])((?:\\d{2,4}[ .,\\-]+)*\\d{2,4})\\s*(${symAlt})\\s*(\\d+(?:[.,]\\d+)?)(?:\\s*diem)?(?![\\d])`, 'g')
    : null
  // "22.67lo10 de5" / "22.67lo10de5": the second symbol re-uses the numbers in front of the first.
  const reAttach = symAlt
    ? new RegExp(`((?:\\d{2,4}\\.)*\\d{2,4})(${symAlt})(\\d+(?:[.,]\\d+)?)\\s*(${symAlt})(\\d+(?:[.,]\\d+)?)(?![\\d.,]|\\s*[a-z])`, 'g')
    : null
  run.normalize = (f) => {
    if (!reGroup || !reAttach) return f
    return f
      .replace(/\s*[;|/]\s*|\s+-\s+/g, ' ')
      .replace(reGroup, (_all, nums, sym, pts) => `${nums.split(/[ .,-]+/).join('.')}${sym}${pts}`)
      .replace(reAttach, '$1$2$3$4$5')
      .replace(/\s+/g, ' ')
      .trim()
  }
  return run
}

export function parseMessage(text, { betTypes = ['de', 'lo'], template = null, kindSymbols = null } = {}) {
  const cfg = { ...emptyTemplate(), ...(template || {}), kindSymbols }
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
  const compact = makeCompactParser(compactSymbols(aliasMap, cfg), betTypes)

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

    // Compact notation: only when EVERY space-separated token of the line is one ("20lo100 70lo500 54lo300").
    // A line that mixes in anything else goes through the legacy path below, exactly as before.
    const ctxType = stickyType || cfg.defaultType
    let toks = f.split(/\s+/).filter(Boolean)
    let parsed = toks.map((t) => compact(t, ctxType))
    if (!parsed.every(Boolean)) {
      // The same line written loosely ("22 67 lo 10", "22-67 lô10; 50.65 lo20"): tidy it and try again.
      const tidy = compact.normalize(f).split(/\s+/).filter(Boolean)
      const again = tidy.map((t) => compact(t, ctxType))
      if (tidy.length && again.every(Boolean)) {
        toks = tidy
        parsed = again
      }
    }
    if (toks.length && parsed.every(Boolean)) {
      for (const p of parsed) for (const r of p.rows) rows.push({ ...r, raw: line, uncertain: r.reasons.length > 0 })
      continue
    }

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

// Side-by-side check ("Đối chiếu"): for every line, each compact token in its canonical spelling next to the
// original. Never changes a number, never guesses: a token that is not compact notation is kept exactly as typed
// and reported as `plain`/`unknown` so the user checks it. Pure function; whitespace is preserved.
export function decodeMessage(text, { betTypes = ['de', 'lo'], template = null, kindSymbols = null } = {}) {
  const cfg = { ...emptyTemplate(), ...(template || {}), kindSymbols }
  const aliasMap = { ...BUILTIN_ALIASES }
  for (const t of betTypes) aliasMap[fold(t)] = t
  for (const [a, t] of Object.entries(cfg.typeAliases || {})) aliasMap[fold(a)] = t
  const compact = makeCompactParser(compactSymbols(aliasMap, cfg), betTypes)
  return String(text || '').split(/\r?\n/).map((original) => {
    const parts = original.split(/(\s+)/).filter((p) => p !== '').map((tok) => {
      if (/^\s+$/.test(tok)) return { text: tok, decoded: tok, status: 'space' }
      const p = compact(fold(tok), cfg.defaultType)
      if (!p) return { text: tok, decoded: tok, status: /\d/.test(tok) ? 'unknown' : 'plain' }
      return { text: tok, decoded: p.canon, status: p.canon === tok ? 'same' : 'changed' }
    })
    return {
      original,
      decoded: parts.map((x) => x.decoded).join(''),
      parts,
      changed: parts.some((x) => x.status === 'changed'),
      unknown: parts.some((x) => x.status === 'unknown'),
    }
  })
}
