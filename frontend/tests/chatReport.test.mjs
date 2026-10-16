import test from 'node:test'
import assert from 'node:assert/strict'
import { buildReport, reportText, reportId } from '../src/chatReport.js'
import { DEFAULT_RATES } from '../src/scoringConfig.js'

const MN = { giaiTam: ['20'], giaiBay: ['120'], giaiSau: ['1234', '5678', '0020'], giaiNam: ['9020'], giaiTu: ['11111', '22222', '33333', '44444', '55555', '66666', '77720'], giaiBa: ['12345', '23456'], giaiNhi: ['34567'], giaiNhat: ['45678'], dacBiet: ['123456'] }
const base = { station: 'mn-tphcm', stationName: 'TP.HCM', date: '2026-10-15', accountRates: DEFAULT_RATES }

test('không có kết quả: không tính tiền trúng, lợi nhuận "chưa đủ dữ liệu"', () => {
  const r = buildReport({ ...base, result: null, rows: [{ type: 'lo', value: '20', score: 10 }] })
  assert.equal(r.missingResult, true)
  assert.equal(r.totals.profit, null)
  assert.equal(r.totals.won, 0)
  assert.match(reportText(r), /Tổng lợi nhuận: Chưa đủ dữ liệu/)
})

test('có kết quả: lô 20 về 5 lần; lợi nhuận = đánh - trúng; dòng cần kiểm tra không được tính', () => {
  const r = buildReport({ ...base, result: MN, rows: [{ type: 'lo', value: '20', score: 10 }, { type: 'lo', value: '99', score: 7, uncertain: true }] })
  const lo = r.groups[0]
  assert.equal(lo.stake, 10)
  assert.equal(lo.winPoints, 50)
  assert.equal(r.skipped.length, 1)
  assert.equal(r.totals.profit, r.totals.stake - r.totals.won)
  const t = reportText(r)
  assert.match(t, /^BÁO CÁO KẾT QUẢ\nĐài: TP\.HCM\nNgày: 15\/10\/2026/)
  assert.match(t, /Tổng tiền khách đánh:/)
})

test('id báo cáo ổn định theo nội dung', () => {
  const r = buildReport({ ...base, result: MN, rows: [] })
  assert.equal(reportId(r, ['20lo10']), reportId(r, ['20lo10']))
  assert.notEqual(reportId(r, ['20lo10']), reportId(r, ['20lo11']))
})

test('cấu hình cũ (rate/tiers, không có giá tiền) vẫn ra số, không NaN', () => {
  const legacy = { lo: { rate: 20, tiers: ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay'], digits: 2 } }
  const r = buildReport({ ...base, accountRates: legacy, result: MN, rows: [{ type: 'lo', value: '20', score: 10 }] })
  assert.ok(Number.isFinite(r.totals.won) && Number.isFinite(r.totals.profit))
  assert.equal(r.groups[0].winPoints, 50)
})
