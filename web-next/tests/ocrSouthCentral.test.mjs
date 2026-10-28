// Chạy: cd web-next && npm test
// Đọc ảnh Miền Nam/Trung: mã đài PY/TTH, chữ Thứ/CN, suy ngày theo số cột, số giải 2052 không bị coi là năm
// (cùng việc với app: app/test/results_station_detect_test.dart, results_columns_test.dart).
import test from 'node:test'
import assert from 'node:assert/strict'
import { state } from '../src/lib/lotteryStations'
import { assignStations, dateOfWeekdayOnOrBefore, inferDateFromStations, parseColumns, stationFromCode, weekdayFromWords } from '../src/lib/lotteryColumns.js'

// Miền Trung rút gọn: thứ hai Huế + Phú Yên, chủ nhật Kon Tum + Khánh Hòa + Huế (đúng ví dụ của tài liệu).
state.regions = [
  { id: 'mb', name: 'Miền Bắc', stations: { mb: 'Miền Bắc' }, schedule: {}, structure: [] },
  {
    id: 'mt', name: 'Miền Trung',
    stations: { 'mt-hue': 'Thừa T. Huế', 'mt-phuyen': 'Phú Yên', 'mt-kontum': 'Kon Tum', 'mt-khanhhoa': 'Khánh Hòa' },
    schedule: { 1: ['mt-hue', 'mt-phuyen'], 7: ['mt-kontum', 'mt-khanhhoa', 'mt-hue'] },
    structure: [],
  },
]
state.loaded = true

const W = (text, cx, cy) => ({ text, x0: cx - 30, x1: cx + 30, y0: cy - 10, y1: cy + 10 })

test('mã đài in dưới tên: chỉ nhận khi mã thuộc đúng một đài', () => {
  assert.equal(stationFromCode('PY'), 'mt-phuyen')
  assert.equal(stationFromCode('Phú Yên (PY)'), 'mt-phuyen')
  assert.equal(stationFromCode('TTH'), 'mt-hue')
  assert.equal(stationFromCode('DL'), null) // Đắk Lắk và Đà Lạt cùng mã
  assert.equal(stationFromCode('BD'), null) // Bình Định và Bình Dương cùng mã
  assert.equal(stationFromCode('xyz'), null)
})

test('cột chỉ có mã "PY" được gán đúng Phú Yên trong các đài của ngày', () => {
  const cols = [{ headerText: 'TTH', station: null }, { headerText: 'PY', station: null }]
  assignStations(cols, ['mt-hue', 'mt-phuyen'])
  assert.deepEqual(cols.map((c) => c.station), ['mt-hue', 'mt-phuyen'])
  assert.equal(cols[1].source, 'tiêu đề')
})

test('chữ Thứ/CN ở phần trên ảnh quyết định thứ; chữ ở phần dưới không tính', () => {
  assert.equal(weekdayFromWords([W('Thứ', 60, 20), W('hai', 120, 20), W('99999', 300, 400)]), 1)
  assert.equal(weekdayFromWords([W('Thứ', 60, 20), W('7', 120, 20), W('1', 300, 600)]), 6)
  assert.equal(weekdayFromWords([W('Chủ', 60, 20), W('nhật', 120, 20), W('5', 300, 600)]), 7)
  assert.equal(weekdayFromWords([W('Đồng', 60, 20), W('Nai', 120, 20), W('Thứ', 60, 580), W('hai', 120, 580)]), null)
  assert.equal(weekdayFromWords([]), null)
})

test('ngày gần nhất không sau ngày đang chọn có đúng thứ đó', () => {
  assert.equal(dateOfWeekdayOnOrBefore(1, '2026-10-25'), '2026-10-19') // chủ nhật 25/10 -> thứ hai 19/10
  assert.equal(dateOfWeekdayOnOrBefore(7, '2026-10-25'), '2026-10-25') // chính ngày đó
  assert.equal(dateOfWeekdayOnOrBefore(3, '2026-10-19'), '2026-10-14')
})

test('suy ngày từ các đài: Phú Yên chỉ có thứ hai; Huế cần số cột để chọn thứ hai (2 đài) thay vì chủ nhật (3 đài)', () => {
  assert.equal(inferDateFromStations('mt', ['mt-phuyen'], '2026-10-25'), '2026-10-19')
  assert.equal(inferDateFromStations('mt', ['mt-hue'], '2026-10-25', 2), '2026-10-19')
  assert.equal(inferDateFromStations('mt', ['mt-hue'], '2026-10-25', 3), '2026-10-25')
  assert.equal(inferDateFromStations('mt', ['mt-hue'], '2026-10-25'), null) // Huế bán hai thứ, không phân biệt được
  assert.equal(inferDateFromStations('mt', ['mt-hue', 'mt-phuyen'], '2026-10-25'), '2026-10-19')
  assert.equal(inferDateFromStations('mt', ['mt-kontum', 'mt-phuyen'], '2026-10-25'), null) // không ngày nào đủ cả hai
  assert.equal(inferDateFromStations('mt', [], '2026-10-25'), null)
})

// Một cột đủ 18 số của một đài: giải 6 có số "2052" (giống năm).
function column(x, withYearLikePrize) {
  const out = []
  const add = (text, y) => out.push(W(text, x, y))
  add('12', 100) // giải 8
  add('345', 130) // giải 7
  add(withYearLikePrize ? '2052' : '4052', 160) // giải 6 (dòng đầu)
  add('4111', 190); add('4222', 220) // giải 6
  add('4333', 250) // giải 5
  for (let i = 0; i < 7; i++) add(`5${i}000`.slice(0, 5), 280 + i * 30) // giải 4
  add('51111', 490); add('52222', 520) // giải 3
  add('53333', 550) // giải 2
  add('54444', 580) // giải 1
  add('654321', 610) // đặc biệt
  return out
}

test('số giải như 2052 không bị coi là năm của dòng ngày: không mất giải 8, giải 7 và dòng đầu giải 6', () => {
  const words = [W('Phú', 150, 60), W('Yên', 200, 60), ...column(200, true)]
  const col = parseColumns(words).columns[0]
  assert.deepEqual(col.values.giaiTam, ['12'])
  assert.deepEqual(col.values.giaiBay, ['345'])
  assert.deepEqual(col.values.giaiSau, ['2052', '4111', '4222'])
  assert.equal(col.complete, true)
})

test('năm đứng cạnh ngày/tháng trên cùng một dòng vẫn là phần của dòng ngày (không thành giải)', () => {
  const header = [W('19/10', 100, 30), W('2026', 170, 30), W('Phú', 150, 60), W('Yên', 200, 60)]
  const col = parseColumns([...header, ...column(200, false)]).columns[0]
  assert.deepEqual(col.values.giaiTam, ['12'])
  assert.equal(col.complete, true)
})
