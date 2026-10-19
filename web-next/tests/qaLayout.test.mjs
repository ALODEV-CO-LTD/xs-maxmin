// QA Next vs Vue: layout rules that only show up in a browser (mobile cards, prize table) must not be dropped.
import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'

const read = (p) => fs.readFileSync(new URL('../src/features/' + p, import.meta.url), 'utf8')

test('Nhập số: bảng số liệu thành thẻ trên điện thoại (stack-table, mọi ô có data-label)', () => {
  const tsx = read('entries/EntriesScreen.tsx')
  assert.match(tsx, /className="table en-table stack-table"/)
  const row = tsx.slice(tsx.indexOf('function EntryRow'), tsx.indexOf('function EditDialog'))
  const cells = row.match(/<td [^>]*>/g) || []
  const labelled = cells.filter((c) => c.includes('data-label='))
  assert.equal(labelled.length, 6, 'Ngày, Hạng mục, Số, Điểm vào, Điểm ra, Ghi chú đều có nhãn')
  assert.match(read('entries/entries.css'), /@media \(max-width: 640px\)[^}]*\.en-table\.stack-table/)
})

test('Nhập kết quả: bảng giải dạng sọc, Đặc biệt và Giải bảy màu đỏ như bản Vue', () => {
  const css = read('results/results.css')
  assert.match(css, /\.rs-tier:nth-child\(odd\)/)
  assert.match(css, /\.rs-tier:first-child input, \.rs-page \.rs-grid \.rs-tier:last-child input \{ color: var\(--danger-text\)/)
  assert.match(css, /\.rs-date \{ width: 180px/)
})

test('service worker: đăng ký ngay khi trang đã tải xong, lưu từng trang đã mở để mở lại được khi offline', () => {
  const prov = fs.readFileSync(new URL('../src/components/Providers.tsx', import.meta.url), 'utf8')
  assert.match(prov, /document\.readyState === 'complete'/)
  const sw = fs.readFileSync(new URL('../public/sw.js', import.meta.url), 'utf8')
  assert.match(sw, /c\.put\(req, copy\.clone\(\)\)/)
  assert.match(sw, /caches\.match\(req\)\.then\(\(hit\) => hit \|\| caches\.match\('\/'\)\)/)
})
