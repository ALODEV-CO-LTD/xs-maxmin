// Copies the OCR engine (tesseract.js worker + wasm core + language data) from
// node_modules into public/tesseract/, so the app serves them itself instead of
// downloading them from a public CDN at run time (CDNs are slow or blocked on
// some networks, and the files then also work offline).
// Runs automatically before `npm run dev` / `npm run build`; the output folder
// is git-ignored.
import { copyFileSync, mkdirSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const nm = join(root, 'node_modules')
const out = join(root, 'public', 'tesseract')

const files = [
  ['tesseract.js/dist/worker.min.js', 'worker.min.js'],
  // lstm-only build without SIMD: the one every browser can run.
  ['tesseract.js-core/tesseract-core-lstm.wasm.js', 'tesseract-core-lstm.wasm.js'],
  ['@tesseract.js-data/eng/4.0.0_best_int/eng.traineddata.gz', 'lang/eng.traineddata.gz'],
  ['@tesseract.js-data/vie/4.0.0_best_int/vie.traineddata.gz', 'lang/vie.traineddata.gz'],
]

for (const [from, to] of files) {
  const src = join(nm, from)
  if (!existsSync(src)) {
    console.error(`copy-ocr-assets: missing ${from} - run "npm install" first`)
    process.exit(1)
  }
  const dest = join(out, to)
  mkdirSync(dirname(dest), { recursive: true })
  copyFileSync(src, dest)
}
console.log(`copy-ocr-assets: ${files.length} files -> public/tesseract`)
