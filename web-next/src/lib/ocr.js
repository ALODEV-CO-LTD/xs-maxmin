// Reading numbers from a photo (OCR), shared by Nhập số and Nhập kết quả.
//
// - Everything runs in the browser and every file the engine needs is served
//   by this app itself from /tesseract/ (copied from node_modules by
//   scripts/copy-ocr-assets.mjs). Nothing is downloaded from a public CDN, so
//   it works on networks that block or slow CDNs, and offline after first use.
// - The photo is resized first: too small and the digits blur into guesses, too
//   big and a phone runs out of memory.
// - For the lottery result table two reading modes are tried and the one that
//   looks most like the real table (right number of 5/4/3/2-digit prizes) wins.
//   (Measured on a real result table: the previous setup got 18 of 27 prizes
//   right, this one 24-26 of 27. Restricting the engine to digits only made it
//   worse, so it is deliberately not used.)
// - Failures are classified so the user is told what actually went wrong.
import { createWorker } from 'tesseract.js'
import { northNumbers } from './northTable'

const ASSET_BASE = `${window.location.origin}/tesseract`
const OCR_TIMEOUT_MS = 150000
// While the engine/model is loading, progress events keep arriving; if none
// arrive for this long it is stuck (a file the server cannot deliver makes the
// library hang without reporting an error).
const LOAD_STALL_MS = 30000

export class OcrError extends Error {
  constructor(kind, message, cause) {
    super(message)
    this.kind = kind
    this.cause = cause
  }
}

const MESSAGES = {
  network: 'Không tải được công cụ đọc ảnh từ máy chủ (mạng chậm hoặc bị chặn). Hãy thử lại sau hoặc nhập tay.',
  image: 'Không mở được ảnh này (định dạng không hỗ trợ hoặc ảnh bị hỏng). Hãy chọn ảnh JPG hoặc PNG khác.',
  memory: 'Ảnh quá lớn hoặc thiết bị không đủ bộ nhớ để đọc. Hãy chụp hoặc cắt ảnh nhỏ hơn rồi thử lại.',
  timeout: 'Đọc ảnh quá lâu nên đã dừng. Hãy thử ảnh nhỏ hơn hoặc nhập tay.',
}

function classify(err) {
  if (err instanceof OcrError) return err
  const text = `${err?.name || ''} ${err?.message || err || ''}`
  if (/memory|out of bounds|aborted|allocation|RangeError/i.test(text)) return new OcrError('memory', MESSAGES.memory, err)
  if (/network|fetch|importScripts|failed to load|load failed|traineddata|404|worker/i.test(text)) {
    return new OcrError('network', MESSAGES.network, err)
  }
  const detail = String(err?.message || err || '').slice(0, 120)
  return new OcrError('unknown', `Không đọc được ảnh. Bạn có thể nhập tay.${detail ? ` (${detail})` : ''}`, err)
}

/** The sentence to show the user for any error thrown by this module. */
export function describeOcrError(err) {
  const e = classify(err)
  console.error('[OCR]', e.kind, e.cause || e)
  return e.message
}

// ---- image preparation ------------------------------------------------------

async function decode(file) {
  try {
    return await createImageBitmap(file)
  } catch {
    // Safari / odd formats: fall back to an <img> element.
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file)
      const img = new Image()
      img.onload = () => {
        URL.revokeObjectURL(url)
        resolve(img)
      }
      img.onerror = () => {
        URL.revokeObjectURL(url)
        reject(new OcrError('image', MESSAGES.image))
      }
      img.src = url
    })
  }
}

// `table`: aim for ~1300 px wide (measured: a 432 px screenshot read 20/27 numbers at 2x and 27/27 at 3x), flattened onto
// white (a transparent PNG has no background otherwise) and in grey with the contrast stretched.
// `text`: only shrink huge photos, leave the rest alone.
async function prepareImage(file, mode) {
  let bitmap
  try {
    bitmap = await decode(file)
  } catch (err) {
    throw err instanceof OcrError ? err : new OcrError('image', MESSAGES.image, err)
  }
  const w = bitmap.width
  const h = bitmap.height
  let scale = 1
  if (mode === 'table') {
    if (w < 1300) scale = Math.min(1300 / w, 6)
    else if (w > 1800) scale = 1600 / w
  } else if (Math.max(w, h) > 2200) {
    scale = 2200 / Math.max(w, h)
  }
  if (scale === 1 && mode !== 'table') return file
  const canvas = document.createElement('canvas')
  canvas.width = Math.max(1, Math.round(w * scale))
  canvas.height = Math.max(1, Math.round(h * scale))
  const ctx = canvas.getContext('2d')
  ctx.fillStyle = '#fff'
  ctx.fillRect(0, 0, canvas.width, canvas.height)
  ctx.imageSmoothingQuality = 'high'
  ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
  bitmap.close?.()
  if (mode === 'table') stretchContrast(ctx, canvas.width, canvas.height)
  return new Promise((resolve, reject) => {
    canvas.toBlob((b) => (b ? resolve(b) : reject(new OcrError('memory', MESSAGES.memory))), 'image/png')
  })
}

// Grey + stretch the darkest / lightest 1% to black / white: bold digits on a tinted row read much better.
function stretchContrast(ctx, w, h) {
  try {
    const img = ctx.getImageData(0, 0, w, h)
    const d = img.data
    const hist = new Array(256).fill(0)
    for (let i = 0; i < d.length; i += 4) {
      const g = Math.round(d[i] * 0.299 + d[i + 1] * 0.587 + d[i + 2] * 0.114)
      d[i] = d[i + 1] = d[i + 2] = g
      hist[g]++
    }
    const cut = (w * h) / 100
    let lo = 0
    let hi = 255
    for (let acc = 0; lo < 255 && (acc += hist[lo]) < cut; lo++);
    for (let acc = 0; hi > 0 && (acc += hist[hi]) < cut; hi--);
    if (hi - lo < 30) return ctx.putImageData(img, 0, 0)
    for (let i = 0; i < d.length; i += 4) d[i] = d[i + 1] = d[i + 2] = Math.max(0, Math.min(255, ((d[i] - lo) * 255) / (hi - lo)))
    ctx.putImageData(img, 0, 0)
  } catch {
    /* a canvas the browser will not read back: keep the picture as drawn */
  }
}

// ---- engine -----------------------------------------------------------------

async function withWorker(lang, onProgress, fn) {
  let worker
  let timer
  let watchdog
  let ready = false
  let lastEvent = Date.now()
  const failures = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new OcrError('timeout', MESSAGES.timeout)), OCR_TIMEOUT_MS)
    watchdog = setInterval(() => {
      if (!ready && Date.now() - lastEvent > LOAD_STALL_MS) reject(new OcrError('network', MESSAGES.network))
    }, 2000)
  })
  try {
    return await Promise.race([
      (async () => {
        worker = await createWorker(lang, 1, {
          // Absolute URLs: the worker is started from a blob, where relative paths do not resolve.
          workerPath: `${ASSET_BASE}/worker.min.js`,
          corePath: `${ASSET_BASE}/tesseract-core-lstm.wasm.js`,
          langPath: `${ASSET_BASE}/lang`,
          logger: (m) => {
            lastEvent = Date.now()
            if (m.status === 'recognizing text') onProgress?.(Math.round((m.progress || 0) * 100))
          },
        })
        ready = true
        return fn(worker)
      })(),
      failures,
    ])
  } finally {
    clearTimeout(timer)
    clearInterval(watchdog)
    // Free the memory (the model is several MB); never let a failure here mask the real result.
    try {
      await worker?.terminate()
    } catch {
      /* ignore */
    }
  }
}

/** Plain text OCR (Nhập số): Vietnamese model, so names with accents still read. */
export async function recognizeText(file, { lang = 'vie', onProgress } = {}) {
  try {
    const image = await prepareImage(file, 'text')
    return await withWorker(lang, onProgress, async (worker) => {
      const { data } = await worker.recognize(image)
      return { text: data.text || '' }
    })
  } catch (err) {
    throw classify(err)
  }
}

// Expected number of tokens per digit-length in a Miền Bắc result table:
// 5 digits = ĐB + G1 + 2 G2 + 6 G3, 4 = 4 G4 + 6 G5, 3 = 3 G6, 2 = 4 G7.
const EXPECTED = { 5: 10, 4: 10, 3: 3, 2: 4 }

function digitBuckets(text) {
  const by = { 5: [], 4: [], 3: [], 2: [] }
  for (const t of (text.match(/\S+/g) || []).filter((w) => /^\d+$/.test(w))) if (by[t.length]) by[t.length].push(t)
  return by
}

// How table-like a reading is: each prize class scores for being (almost)
// complete and loses for surplus tokens (noise such as dates).
export function tablePlausibility(text) {
  const by = digitBuckets(text)
  let score = 0
  for (const len of [5, 4, 3, 2]) {
    const n = by[len].length
    const want = EXPECTED[len]
    score += Math.min(n, want) / want - Math.max(0, n - want) / want
  }
  return score
}

/**
 * Miền Bắc photo with the positions of the words: the prize numbers are picked by length and place (northTable.js), so a
 * label column, a đầu / đuôi table or a footer next to the table cannot take a prize box. Falls back to the plain text of
 * the best reading when no table is recognised. Returns { text } like recognizeLotteryTable.
 */
export async function recognizeNorthTable(file, { onProgress } = {}) {
  try {
    const image = await prepareImage(file, 'table')
    return await withWorker('eng', onProgress, async (worker) => {
      let best = null
      for (const psm of ['11', '6']) {
        await worker.setParameters({ tessedit_pageseg_mode: psm })
        const { data } = await worker.recognize(image, {}, { text: true, blocks: true })
        const text = data.text || ''
        const picked = northNumbers(collectWords(data))
        const score = (picked ? picked.found : 0) + tablePlausibility(picked ? picked.numbers.join(' ') : text) * 0.01
        if (!best || score > best.score + 1e-9) best = { text: picked && picked.found >= 20 ? picked.numbers.join(' ') : text, score, psm }
        if (picked && picked.found === 27) break
      }
      return best
    })
  } catch (err) {
    throw classify(err)
  }
}

/**
 * Lottery result table (Nhập kết quả): English model (digits read better than
 * with the Vietnamese one), two page-segmentation modes, best reading wins.
 */
export async function recognizeLotteryTable(file, { onProgress } = {}) {
  try {
    const image = await prepareImage(file, 'table')
    return await withWorker('eng', onProgress, async (worker) => {
      let best = null
      // 6 = one uniform block (clean tables), 11 = sparse text (loose layouts).
      for (const psm of ['6', '11']) {
        await worker.setParameters({ tessedit_pageseg_mode: psm })
        const { data } = await worker.recognize(image)
        const text = data.text || ''
        const plausibility = tablePlausibility(text)
        if (!best || plausibility > best.plausibility + 1e-9) best = { text, plausibility, psm }
      }
      return best
    })
  } catch (err) {
    throw classify(err)
  }
}

/**
 * Miền Nam / Miền Trung result table (2-4 stations side by side): every recognised word with its position, so the
 * columns (one per station) and the prize rows can be rebuilt (lotteryColumns.js). English model, as for Miền Bắc;
 * the station names in the header are read separately by the caller from the same words.
 */
export async function recognizeLotteryWords(file, { onProgress } = {}) {
  try {
    const image = await prepareImage(file, 'table')
    return await withWorker('eng', onProgress, async (worker) => {
      let best = null
      for (const psm of ['6', '11']) {
        await worker.setParameters({ tessedit_pageseg_mode: psm })
        const { data } = await worker.recognize(image, {}, { text: true, blocks: true })
        const words = collectWords(data)
        const digits = words.filter((w) => /^\d+$/.test(w.text)).length
        if (!best || digits > best.digits) best = { words, text: data.text || '', digits, psm }
      }
      return best
    })
  } catch (err) {
    throw classify(err)
  }
}

// Flattens tesseract's blocks -> paragraphs -> lines -> words into [{ text, x, y, w, h, conf }] (centre-based helpers
// are computed by the caller).
function collectWords(data) {
  if (Array.isArray(data.words) && data.words.length) {
    return data.words.map((w) => ({ text: w.text, x0: w.bbox.x0, y0: w.bbox.y0, x1: w.bbox.x1, y1: w.bbox.y1, conf: w.confidence }))
  }
  const out = []
  for (const b of data.blocks || [])
    for (const p of b.paragraphs || [])
      for (const l of p.lines || [])
        for (const w of l.words || []) out.push({ text: w.text, x0: w.bbox.x0, y0: w.bbox.y0, x1: w.bbox.x1, y1: w.bbox.y1, conf: w.confidence })
  return out
}
