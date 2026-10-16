// Gõ tiếng Việt kiểu Telex cho bàn phím ảo của khung chat (components/ChatKeyboard.vue).
// composeTelex(text, key): trả về `text` sau khi gõ thêm một phím. Chỉ đụng tới TỪ CUỐI của `text`.
//   aa→â  ee→ê  oo→ô  dd→đ  aw→ă  ow→ơ  uw→ư  w→ư (đứng một mình)
//   dấu: s sắc, f huyền, r hỏi, x ngã, j nặng, z xoá dấu. Gõ lại đúng phím dấu đang có thì bỏ dấu và giữ chữ cái.
const TONES = { s: '́', f: '̀', r: '̉', x: '̃', j: '̣' }
const TONE_RE = /[̣̀́̉̃]/g
const VOWELS = 'aăâeêioôơuưy'

const strip = (s) => s.normalize('NFD').replace(TONE_RE, '').normalize('NFC')
const isVowel = (c) => VOWELS.includes(strip(c).toLowerCase())
const matchCase = (ref, ch) => (ref === ref.toUpperCase() && ref !== ref.toLowerCase() ? ch.toUpperCase() : ch)

// Dấu thanh hiện có của một ký tự ('' nếu không có).
function toneOf(c) {
  const m = c.normalize('NFD').match(TONE_RE)
  return m ? m[0] : ''
}

// Vị trí nguyên âm mang dấu thanh trong từ (kiểu đặt dấu phổ biến).
function toneIndex(word) {
  const idx = []
  for (let i = 0; i < word.length; i++) if (isVowel(word[i])) idx.push(i)
  // "qu" và "gi" đi trước nguyên âm thì u/i là phụ âm
  const w = word.toLowerCase()
  if (idx.length > 1 && ((w.startsWith('qu') && idx[0] === 1) || (w.startsWith('gi') && idx[0] === 1))) idx.shift()
  if (!idx.length) return -1
  if (idx.length === 1) return idx[0]
  // nguyên âm có dấu mũ/móc (â ê ô ơ ư ă) được ưu tiên
  const marked = idx.filter((i) => /[̛̂̆]/.test(strip(word[i]).normalize('NFD')))
  if (marked.length) return marked[marked.length - 1]
  const closed = idx[idx.length - 1] < word.length - 1 // có phụ âm cuối
  if (idx.length >= 3) return idx[1]
  const pair = strip(word[idx[0]]).toLowerCase() + strip(word[idx[1]]).toLowerCase()
  if (closed) return idx[1]
  return ['oa', 'oe', 'uy'].includes(pair) ? idx[1] : idx[0]
}

function withTone(word, mark) {
  const i = toneIndex(word)
  if (i < 0) return null
  const base = word.split('').map((c) => strip(c))
  const out = base.slice()
  out[i] = (mark ? (base[i] + mark).normalize('NFC') : base[i])
  return out.join('')
}

// Nhận cả từ đã có dấu cũ: bỏ dấu thanh cũ rồi đặt lại vào đúng chỗ.
function retone(word, mark) {
  return withTone(strip(word), mark)
}

export function composeTelex(text, key) {
  const k = key.toLowerCase()
  const m = text.match(/([^\s]*)$/)
  const word = m ? m[1] : ''
  const head = text.slice(0, text.length - word.length)
  if (!word && k === 'w') return text + matchCase(key, 'ư')
  if (!word || !/^\p{L}+$/u.test(word)) return text + key
  const last = word[word.length - 1]

  // dd → đ
  if (k === 'd' && last === 'd') return head + word.slice(0, -1) + 'đ'
  if (k === 'd' && last === 'D') return head + word.slice(0, -1) + 'Đ'
  // aa/ee/oo → â/ê/ô (cả aw/ow/uw)
  const lastBase = strip(last).toLowerCase()
  if (k === 'a' && lastBase === 'a' && !/[̂̆]/.test(last.normalize('NFD'))) return head + replaceLast(word, last, 'â')
  if (k === 'e' && lastBase === 'e' && !/̂/.test(last.normalize('NFD'))) return head + replaceLast(word, last, 'ê')
  if (k === 'o' && lastBase === 'o' && !/[̛̂]/.test(last.normalize('NFD'))) return head + replaceLast(word, last, 'ô')
  if (k === 'w') {
    if (lastBase === 'a') return head + replaceLast(word, last, 'ă')
    if (lastBase === 'o') return head + replaceLast(word, last, 'ơ')
    if (lastBase === 'u') return head + replaceLast(word, last, 'ư')
    return text + matchCase(key, 'ư')
  }
  // dấu thanh
  if (k in TONES || k === 'z') {
    if (!/[aăâeêioôơuưy]/i.test(strip(word))) return text + key
    const mark = k === 'z' ? '' : TONES[k]
    const cur = [...word].map(toneOf).find(Boolean) || ''
    if (mark && cur === mark) return head + strip(word) + key // gõ lại: bỏ dấu, giữ chữ cái vừa gõ
    const out = retone(word, mark)
    return out == null ? text + key : head + out
  }
  return text + key
}

function replaceLast(word, last, composed) {
  const tone = toneOf(last)
  let ch = composed.normalize('NFC')
  if (last === last.toUpperCase() && last !== last.toLowerCase()) ch = ch.toUpperCase()
  if (tone) ch = (strip(ch) + (composed.normalize('NFD').slice(1).replace(TONE_RE, '')) + tone).normalize('NFC')
  return word.slice(0, -last.length) + ch
}
