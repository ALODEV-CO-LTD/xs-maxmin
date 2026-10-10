// Rebuilds a Miền Nam / Miền Trung result table from OCR words with positions (ocr.js recognizeLotteryWords):
// one column per station, prizes in table order. Pure functions (no DOM / network), see the checks at the bottom
// of the Nhập kết quả flow (ResultsView) - the result is only ever a SUGGESTION the user reviews before saving.
//
// Table layout (top to bottom): G.8 (2 digits x1), G.7 (3 x1), G.6 (4 x3), G.5 (4 x1), G.4 (5 x7), G.3 (5 x2), G.2 (5 x1),
// G.1 (5 x1), G.ĐB (6 x1). So per column: the 2-digit number is G8, the 3-digit G7, the four 4-digit numbers are G6 x3 then
// G5, the eleven 5-digit numbers are G4 x7, G3 x2, G2, G1 (reading order), the 6-digit number is the special prize.
import { regionList, stationName } from './lotteryStations'

const fold = (s) =>
  String(s || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/gi, 'd')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()

// Extra spellings seen in headers (folded). The catalog names themselves are matched too.
const ALIASES = {
  'mn-tphcm': ['tp hcm', 'tphcm', 'hcm', 'ho chi minh', 'tp ho chi minh'],
  'mt-hue': ['hue', 'thua thien hue', 'tt hue'],
  'mn-vungtau': ['vung tau', 'ba ria vung tau', 'brvt'],
  'mt-daklak': ['dak lak', 'daklak', 'dac lac'],
  'mt-daknong': ['dak nong', 'daknong', 'dac nong'],
  'mn-dalat': ['da lat', 'lam dong'],
}

const SPEC = [
  { len: 2, take: [['giaiTam', 1]] },
  { len: 3, take: [['giaiBay', 1]] },
  { len: 4, take: [['giaiSau', 3], ['giaiNam', 1]] },
  { len: 5, take: [['giaiTu', 7], ['giaiBa', 2], ['giaiNhi', 1], ['giaiNhat', 1]] },
  { len: 6, take: [['dacBiet', 1]] },
]
const EXPECTED_BY_LEN = Object.fromEntries(SPEC.map((s) => [s.len, s.take.reduce((n, [, c]) => n + c, 0)]))

const centreX = (w) => (w.x0 + w.x1) / 2
const centreY = (w) => (w.y0 + w.y1) / 2

// station id from header text (folded), or null
export function matchStation(text) {
  const t = fold(text)
  if (!t) return null
  for (const r of regionList()) {
    for (const [id, name] of Object.entries(r.stations || {})) {
      if (id === 'mb') continue
      const names = [fold(name), ...(ALIASES[id] || [])]
      if (names.some((n) => n && (t === n || t.includes(n) || (n.length > 4 && n.includes(t) && t.length > 3)))) return id
    }
  }
  return null
}

function levenshtein(a, b) {
  const dp = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)])
  for (let j = 1; j <= b.length; j++) dp[0][j] = j
  for (let i = 1; i <= a.length; i++)
    for (let j = 1; j <= b.length; j++) dp[i][j] = Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1))
  return dp[a.length][b.length]
}
const similarity = (a, b) => (a && b ? 1 - levenshtein(a, b) / Math.max(a.length, b.length) : 0)
const NOISE = new Set(['giai', 'xsmn', 'xsmt', 'xsmb', 'thu', 'thir', 'thur', 'kqxs', 'truc', 'tiep', 'ngay', 'mien', 'nam', 'trung', 'bac'])

// How well the header text of a column fits a station name (0..1): the best match over windows of 1-3 header words.
// The header is read by the English model, so accents are garbled ("Déng Thr Nai" for "Đồng Nai") - hence fuzzy.
function headerScore(headerText, id) {
  const words = fold(headerText).split(' ').filter((w) => w && !/^\d+$/.test(w) && !NOISE.has(w))
  const names = [fold(stationName(id)), ...(ALIASES[id] || [])]
  let best = 0
  for (let i = 0; i < words.length; i++)
    for (let n = 1; n <= 3 && i + n <= words.length; n++) {
      const win = words.slice(i, i + n).join(' ')
      for (const name of names) best = Math.max(best, similarity(win, name))
    }
  return best
}

// Gives every column a station among `candidates` (the stations drawing that day): the best header matches first, then
// the remaining columns take the remaining stations in the page order. `source` tells the user how sure it is.
export function assignStations(columns, candidates) {
  const pool = [...candidates]
  const pairs = []
  columns.forEach((c, ci) => pool.forEach((id) => pairs.push({ ci, id, score: c.station === id ? 1 : headerScore(c.headerText, id) })))
  pairs.sort((a, b) => b.score - a.score)
  const usedCol = new Set()
  const usedSt = new Set()
  for (const p of pairs) {
    if (p.score < 0.6 || usedCol.has(p.ci) || usedSt.has(p.id)) continue
    columns[p.ci].station = p.id
    columns[p.ci].source = 'tiêu đề'
    usedCol.add(p.ci)
    usedSt.add(p.id)
  }
  const left = pool.filter((id) => !usedSt.has(id))
  columns.forEach((c, ci) => {
    if (usedCol.has(ci)) return
    c.station = left.shift() || null
    c.source = c.station ? 'theo thứ tự' : ''
  })
  return columns
}

export function parseColumns(words) {
  const nums = words
    .map((w) => ({ ...w, text: String(w.text || '').trim() }))
    .filter((w) => /^\d+$/.test(w.text) && w.text.length >= 2 && w.text.length <= 6)
    .map((w) => ({ ...w, cx: centreX(w), cy: centreY(w) }))
  const specials = nums.filter((w) => w.text.length === 6).sort((a, b) => a.cx - b.cx)
  if (!specials.length) return { columns: [], date: null }

  // One 6-digit special prize per station: they fix the column centres.
  const centres = specials.map((w) => w.cx)
  const nearest = (cx) => centres.reduce((best, c, i) => (Math.abs(c - cx) < Math.abs(centres[best] - cx) ? i : best), 0)

  const firstRowY = Math.min(...nums.filter((w) => w.text.length === 2).map((w) => w.cy), Infinity)
  const columns = centres.map((x) => ({ x, tokens: [], header: [], values: {}, issues: [], station: null }))
  for (const w of nums) columns[nearest(w.cx)].tokens.push(w)

  // Header words (station names) sit above the first prize row.
  for (const w of words) {
    const text = String(w.text || '').trim()
    if (!text || /^\d+$/.test(text)) continue
    if (Number.isFinite(firstRowY) && centreY(w) < firstRowY - 6) columns[nearest(centreX(w))].header.push({ text, cx: centreX(w) })
  }

  for (const col of columns) {
    col.header.sort((a, b) => a.cx - b.cx)
    col.headerText = col.header.map((h) => h.text).join(' ')
    col.station = matchStation(col.headerText)
    for (const { len, take } of SPEC) {
      const list = col.tokens.filter((t) => t.text.length === len).sort((a, b) => a.cy - b.cy)
      const want = EXPECTED_BY_LEN[len]
      if (list.length !== want) col.issues.push(`${len} chữ số: đọc được ${list.length}/${want}`)
      let i = 0
      for (const [tier, count] of take) {
        const vals = []
        for (let k = 0; k < count; k++) vals.push(list[i++]?.text || '')
        col.values[tier] = tier === 'dacBiet' || tier === 'giaiNhat' ? vals[0] : vals
      }
    }
    col.complete = col.issues.length === 0
  }

  // dd/mm/yyyy anywhere in the text -> ISO
  const m = words.map((w) => w.text).join(' ').match(/(\d{1,2})[/.-](\d{1,2})[/.-](20\d{2})/)
  const date = m ? `${m[3]}-${m[2].padStart(2, '0')}-${m[1].padStart(2, '0')}` : null
  return { columns: columns.map(({ tokens, header, ...c }) => c), date }
}
