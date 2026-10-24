// Miền Bắc result photo: picks the 27 prize numbers out of the recognised words (with their positions) when the photo
// holds more than the table itself - a label column ("ĐB", "G1", "6 ô · 5 số"), a đầu / đuôi table at the side, a "Mã ĐB"
// footer. Pure functions, port of lottery_columns.dart (repairDigitWords, _northByLength). The result is only ever a
// suggestion the user reviews before saving.

const LOOKALIKE = { O: '0', o: '0', D: '0', Q: '0', I: '1', l: '1', '|': '1', S: '5', s: '5', B: '8', Z: '2', z: '2' }

/** The digits of one OCR word, or null when it is not a number ("I9640" -> "19640": a letter of similar shape in a bold number). */
export function digitsOf(raw) {
  const t = String(raw || '').trim()
  if (!t) return null
  if (/^\d+$/.test(t)) return t
  if (!/^[0-9OoDQIl|SsBZz]+$/.test(t)) return null
  const real = (t.match(/\d/g) || []).length
  if (real * 2 < t.length) return null
  return [...t].map((ch) => LOOKALIKE[ch] ?? ch).join('')
}

const cx = (w) => (w.x0 + w.x1) / 2
const cy = (w) => (w.y0 + w.y1) / 2

/** Table order: top to bottom by row, left to right inside a row. */
function readingOrder(ws) {
  if (!ws.length) return []
  const hs = ws.map((w) => w.y1 - w.y0).sort((a, b) => a - b)
  const tol = Math.max(4, hs[hs.length >> 1] * 0.6)
  const sorted = [...ws].sort((a, b) => cy(a) - cy(b))
  const rows = []
  let rowCy = 0
  for (const w of sorted) {
    if (!rows.length || cy(w) - rowCy > tol) {
      rows.push([w])
      rowCy = cy(w)
    } else {
      rows[rows.length - 1].push(w)
      const r = rows[rows.length - 1]
      rowCy = r.reduce((s, x) => s + cy(x), 0) / r.length
    }
  }
  return rows.flatMap((r) => r.sort((a, b) => cx(a) - cx(b)))
}

/**
 * The prize numbers in the order guessFromText reads them: 10 five-digit, 10 four-digit, 3 three-digit, 4 two-digit.
 * Returns { numbers, found } (found = how many of the 27 were found) or null when the table is not recognisable.
 */
export function northNumbers(words) {
  const nums = []
  for (const w of words || []) {
    const d = digitsOf(w.text)
    if (d && d.length >= 2 && d.length <= 5) nums.push({ ...w, text: d })
  }
  const long = nums.filter((w) => w.text.length >= 4)
  if (long.filter((w) => w.text.length === 5).length < 5) return null
  // Prizes sit between the left edge of the widest rows and their right edge: a label column (centre left of every
  // 4 / 5-digit number) and a side table (centre right of all of them) are not prizes.
  const widths = long.map((w) => w.x1 - w.x0).sort((a, b) => a - b)
  const margin = widths[widths.length >> 1] * 0.4 // a short number at the end of a row may stick out a little
  const left = Math.min(...long.map((w) => w.x0)) - margin
  const right = Math.max(...long.map((w) => w.x1)) + margin
  const body = readingOrder(nums.filter((w) => cx(w) >= left && cx(w) <= right))
  const of = (n) => body.filter((w) => w.text.length === n)
  const five = of(5).slice(0, 10)
  if (!five.length) return null
  const four = of(4).filter((w) => cy(w) >= cy(five[0])).slice(0, 10)
  const two = of(2).slice(-4)
  const lastTop = Math.max(...five.map(cy))
  const above2 = two.length ? cy(two[0]) + 1 : Infinity
  const three = of(3).filter((w) => cy(w) > lastTop && cy(w) <= above2).slice(-3)
  const picked = [...five, ...four, ...three, ...two]
  return { numbers: picked.map((w) => w.text), found: picked.length }
}
