// Rebuilds a Miền Nam / Miền Trung result table from OCR words with positions (ocr.js recognizeLotteryWords):
// one column per station, prizes in table order. Pure functions (no DOM / network), see the checks at the bottom
// of the Nhập kết quả flow (ResultsView) - the result is only ever a SUGGESTION the user reviews before saving.
//
// Table layout (top to bottom): G.8 (2 digits x1), G.7 (3 x1), G.6 (4 x3), G.5 (4 x1), G.4 (5 x7), G.3 (5 x2), G.2 (5 x1),
// G.1 (5 x1), G.ĐB (6 x1). So per column: the 2-digit number is G8, the 3-digit G7, the four 4-digit numbers are G6 x3 then
// G5, the eleven 5-digit numbers are G4 x7, G3 x2, G2, G1 (reading order), the 6-digit number is the special prize.
import { regionList, stationName, stationsOn } from './lotteryStations'

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

// The short codes printed under a station name ("PY", "TTH"...), as xskt sites write them. A header word equal to one of them
// names the station even when the long name was not read. Same table as the app (lottery_columns.dart `_codes`).
const CODES = {
  'mt-hue': ['tth', 'hue'], 'mt-phuyen': ['py'], 'mt-daklak': ['dlk', 'dl'], 'mt-quangnam': ['qnm', 'qna'], 'mt-danang': ['dng', 'dna'],
  'mt-khanhhoa': ['kh'], 'mt-binhdinh': ['bdi', 'bd'], 'mt-quangtri': ['qt'], 'mt-quangbinh': ['qb'], 'mt-gialai': ['gl'],
  'mt-ninhthuan': ['nt'], 'mt-quangngai': ['qng', 'qgi'], 'mt-daknong': ['dno', 'dnn'], 'mt-kontum': ['kt'],
  'mn-tphcm': ['hcm', 'tp'], 'mn-dongthap': ['dt'], 'mn-camau': ['cm'], 'mn-bentre': ['bt'], 'mn-vungtau': ['vt'], 'mn-baclieu': ['bl'],
  'mn-dongnai': ['dn'], 'mn-cantho': ['ct'], 'mn-soctrang': ['st'], 'mn-tayninh': ['tn'], 'mn-angiang': ['ag'], 'mn-binhthuan': ['bth'],
  'mn-vinhlong': ['vl'], 'mn-binhduong': ['bd'], 'mn-travinh': ['tv'], 'mn-longan': ['la'], 'mn-binhphuoc': ['bp'], 'mn-haugiang': ['hg'],
  'mn-tiengiang': ['tg'], 'mn-kiengiang': ['kg'], 'mn-dalat': ['dl'],
}
const headerCodes = (headerText) => fold(headerText).split(' ').filter((w) => w.length >= 2 && w.length <= 4)

/** The station a header names by its short code alone, when the code belongs to exactly one station ("PY" yes; "DL" and "BD" belong to two). */
export function stationFromCode(headerText) {
  for (const w of headerCodes(headerText)) {
    const owners = Object.keys(CODES).filter((id) => CODES[id].includes(w))
    if (owners.length === 1) return owners[0]
  }
  return null
}

const SPEC = [
  { len: 2, take: [['giaiTam', 1]] },
  { len: 3, take: [['giaiBay', 1]] },
  { len: 4, take: [['giaiSau', 3], ['giaiNam', 1]] },
  { len: 5, take: [['giaiTu', 7], ['giaiBa', 2], ['giaiNhi', 1], ['giaiNhat', 1]] },
  { len: 6, take: [['dacBiet', 1]] },
]
// The same 18 numbers in table order, top to bottom: tier, how many, digits each.
const POSITIONS = [
  ['giaiTam', 1, 2],
  ['giaiBay', 1, 3],
  ['giaiSau', 3, 4],
  ['giaiNam', 1, 4],
  ['giaiTu', 7, 5],
  ['giaiBa', 2, 5],
  ['giaiNhi', 1, 5],
  ['giaiNhat', 1, 5],
  ['dacBiet', 1, 6],
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
  // a short code on its own ("PY", "TTH") is a strong hint too
  const codes = CODES[id] || []
  if (headerCodes(headerText).some((w) => codes.includes(w))) best = 0.95
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

// The row of 6-digit special prizes (đặc biệt), left to right. A 6-digit word elsewhere (a draw code in the header, a code in a
// footer) must not be taken for it: the row with the MOST 6-digit numbers wins (one per station); on a tie the one that has about
// 17 other numbers above it per column, the way a real table does.
export function specialRow(nums) {
  const six = nums.filter((w) => w.text.length === 6).sort((a, b) => a.cy - b.cy)
  if (!six.length) return []
  const tol = Math.max(6, (six[0].y1 - six[0].y0) * 0.6)
  const groups = []
  for (const w of six) {
    const g = groups[groups.length - 1]
    if (g && Math.abs(w.cy - g[g.length - 1].cy) <= tol) g.push(w)
    else groups.push([w])
  }
  let best = null
  let bestKey = [-1, 0]
  for (const g of groups) {
    const above = nums.filter((w) => w.text.length < 6 && w.cy < g[0].cy - tol).length
    const key = [g.length, -Math.abs(above - 17 * g.length)]
    if (key[0] > bestKey[0] || (key[0] === bestKey[0] && key[1] > bestKey[1])) {
      best = g
      bestKey = key
    }
  }
  return best.sort((a, b) => a.cx - b.cx)
}

export function parseColumns(words) {
  // The title line of the page ("XSMN Thứ 4 » XSMN 07/10/2026") holds a date whose digits must not count as prizes:
  // everything down to the date word is ignored. Only the FIRST real date in the top third of the picture counts: a stray
  // "/" read from a table line further down must never raise the cut (that used to swallow the first prize rows).
  const allY = words.map(centreY)
  const top = allY.length ? Math.min(...allY) : 0
  const span = allY.length ? Math.max(...allY) - top : 0
  // A bare year ("2026" after "19/10") is part of the date only when a day/month word stands on its row: a prize such as "2052" or
  // "2024" must never be taken for it (that cut away every row above it: the 2-, 3- and first 4-digit prizes).
  const isFullDate = (t) => /^\d{1,2}\s*[/.-]\s*\d{1,2}\s*[/.-]\s*(20)?\d{2}$/.test(t)
  const isDayMonth = (t) => /^\d{1,2}\s*[/.-]\s*\d{1,2}$/.test(t)
  const isDate = (w) => {
    const t = String(w.text || '').trim()
    if (isFullDate(t)) return true
    return /^20\d\d$/.test(t) && words.some((o) => o !== w && Math.abs(centreY(o) - centreY(w)) <= (w.y1 - w.y0) * 0.6 && isDayMonth(String(o.text || '').trim()))
  }
  const dateWords = words.filter((w) => isDate(w) && centreY(w) <= top + span * 0.35)
  const dateTop = dateWords.length ? dateWords.reduce((m, w) => (centreY(w) < centreY(m) ? w : m)) : null
  const cut = dateTop ? centreY(dateTop) + (dateTop.y1 - dateTop.y0) * 0.9 : -Infinity
  const allNums = words
    .map((w) => ({ ...w, text: String(w.text || '').trim() }))
    .filter((w) => /^\d+$/.test(w.text) && w.text.length >= 2 && w.text.length <= 6)
    .map((w) => ({ ...w, cx: centreX(w), cy: centreY(w) }))
    .filter((w) => w.cy > cut)
  const specials = specialRow(allNums)
  if (!specials.length) return { columns: [], date: null }
  // Everything printed BELOW the special-prize row is not a prize: a footer, a lô tô table, a phone number, the next ad.
  const tableBottom = Math.max(...specials.map((w) => w.cy)) + (specials[0].y1 - specials[0].y0) * 0.9
  const nums = allNums.filter((w) => w.cy <= tableBottom)

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
    col.station = matchStation(col.headerText) || stationFromCode(col.headerText)
    // Exactly the 18 numbers of a column were seen: take them by their place in the table, top to bottom, even when one
    // of them has a wrong length (a digit lost or added by the reader). The wrong-length cell is reported and shown red
    // for the user to fix, instead of every row after it shifting out of place.
    if (col.tokens.length === 18) {
      const sorted = [...col.tokens].sort((a, b) => a.cy - b.cy)
      let i = 0
      for (const [tier, count, digits] of POSITIONS) {
        const vals = []
        for (let k = 0; k < count; k++) {
          const t = sorted[i++].text
          vals.push(t)
          if (t.length !== digits) col.issues.push(`${tier}: số "${t}" có ${t.length} chữ số, cần ${digits}`)
        }
        col.values[tier] = tier === 'dacBiet' || tier === 'giaiNhat' ? vals[0] : vals
      }
      col.complete = col.issues.length === 0
      continue
    }
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

/** The day of the week printed in the photo ("Thứ hai", "Thứ 2", "Chủ nhật" in the top-left cell or the title): 1 = Monday .. 7 = Sunday,
 *  or null. Only the upper part of the picture is looked at, so a word further down never counts. */
export function weekdayFromWords(words) {
  if (!words || !words.length) return null
  const top = Math.min(...words.map((w) => w.y0))
  const bottom = Math.max(...words.map((w) => w.y1))
  const limit = top + (bottom - top) * 0.3
  const head = words
    .filter((w) => centreY(w) <= limit)
    .sort((a, b) => (Math.abs(centreY(a) - centreY(b)) > (a.y1 - a.y0) / 2 ? centreY(a) - centreY(b) : centreX(a) - centreX(b)))
  const t = ` ${fold(head.map((w) => w.text).join(' '))} `
  const names = { 1: ['thu hai', 'thu 2'], 2: ['thu ba', 'thu 3'], 3: ['thu tu', 'thu 4'], 4: ['thu nam', 'thu 5'], 5: ['thu sau', 'thu 6'], 6: ['thu bay', 'thu 7'], 7: ['chu nhat'] }
  for (const [day, list] of Object.entries(names)) if (list.some((n) => t.includes(` ${n} `))) return Number(day)
  return null
}

const isoOf = (d) => `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-${String(d.getUTCDate()).padStart(2, '0')}`
function utcDay(iso) {
  const [y, m, d] = String(iso).split('-').map(Number)
  return new Date(Date.UTC(y, m - 1, d))
}

/** The latest date that is `weekday` (1 Monday .. 7 Sunday): the day `fromIso` itself or up to 6 days before it. */
export function dateOfWeekdayOnOrBefore(weekday, fromIso) {
  const d = utcDay(fromIso)
  while ((d.getUTCDay() || 7) !== weekday) d.setUTCDate(d.getUTCDate() - 1)
  return isoOf(d)
}

/** The photo has no readable date: the latest day, `fromIso` or up to 6 days before, on which every station in `ids` draws. With
 *  `columnCount` (the columns of the photo) a day that has exactly that many stations is a better fit than one with more (Thừa Thiên
 *  Huế draws on Monday with Phú Yên and on Sunday with two others). One station that draws on two weekdays says nothing about which:
 *  only a single fit (or two or more stations) decides. Null when there is none. */
export function inferDateFromStations(regionId, ids, fromIso, columnCount) {
  const want = new Set(ids)
  if (want.size === 0 || !fromIso) return null
  const days = []
  for (let back = 0; back <= 6; back++) {
    const d = utcDay(fromIso)
    d.setUTCDate(d.getUTCDate() - back)
    const iso = isoOf(d)
    const on = stationsOn(regionId, iso)
    if ([...want].every((id) => on.includes(id))) days.push({ iso, n: on.length })
  }
  let fit = days
  if (columnCount != null) {
    const exact = days.filter((d) => d.n === columnCount)
    if (exact.length) fit = exact
  }
  if (!fit.length) return null
  return want.size >= 2 || fit.length === 1 ? fit[0].iso : null
}
