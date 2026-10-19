<!--
  Thống kê tab of the Tài khoản page: roster size, number of plays (entries),
  total points in/out and profit (vào − ra), same parsing convention as
  EntriesView / CustomersView. Figures hide while "Ẩn số liệu" is on.
  One unified card: metric (Điểm vào / Điểm ra / Lợi nhuận) + period (Ngày / Tuần / Tháng / Năm)
  controls, a summary strip for the visible range (vs the previous range), the bar chart and the
  fixed totals row. Aggregation lives in ../statsSeries.js (unit-tested).
  API: GET /me/customers, GET /me/entries (all pages, cached offline).
-->
<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { cachedGet, loadAllEntries } from '../offline'
import { api } from '../api'
import { DEFAULT_RATES } from '../scoringConfig'
import { loadStations } from '../lotteryStations'
import { moneyByDate, moneyTotals, neededResults, pseudoEntries } from '../statsMoney'
import MaskedValue from './MaskedValue.vue'
import { mask } from '../stores/mask'
import { buildSeries, compactNumber, rangeTotals, tickEvery, tickIndices } from '../statsSeries'

const loading = ref(true)
const error = ref('')
const money = ref({ byDate: {}, customers: 0, plays: 0 })

const fmt = (n) => new Intl.NumberFormat('vi-VN').format(n)

// Everything Tính điểm uses: entries, customers (own rates / region), the account's rates and the day's lottery results.
async function loadResult(cache, date, station) {
  try {
    const { result } = await api.get(`/lottery-results?date=${date}&station=${encodeURIComponent(station)}`)
    cache.set(`${date}|${station}`, result || null)
  } catch (_) {
    cache.set(`${date}|${station}`, null) // not known: counted as "chưa tính"
  }
}

onMounted(async () => {
  try {
    const [{ customers }, list, rates] = await Promise.all([
      cachedGet('/me/customers'),
      loadAllEntries(),
      api.get('/me/scoring-settings').then((r) => (r.rates && Object.keys(r.rates).length ? r.rates : DEFAULT_RATES)).catch(() => DEFAULT_RATES),
      loadStations().catch(() => null),
    ])
    const cache = new Map()
    const queue = neededResults(list.entries)
    await Promise.all(Array.from({ length: 4 }, async () => {
      while (queue.length) {
        const [date, st] = queue.pop()
        await loadResult(cache, date, st)
      }
    }))
    money.value = moneyByDate(list.entries, customers, rates, (date, st) => cache.get(`${date}|${st}`) || null)
  } catch (err) {
    error.value = err.message || 'Không tải được thống kê'
  } finally {
    loading.value = false
  }
})

// ---- chart ----
const UNITS = [
  { key: 'day', label: 'Ngày', range: '30 ngày gần nhất', prev: '30 ngày trước đó' },
  { key: 'week', label: 'Tuần', range: '12 tuần gần nhất', prev: '12 tuần trước đó' },
  { key: 'month', label: 'Tháng', range: '12 tháng gần nhất', prev: '12 tháng trước đó' },
  { key: 'year', label: 'Năm', range: '5 năm gần nhất', prev: '5 năm trước đó' },
]
const METRICS = [
  { key: 'vao', label: 'Tiền gửi' },
  { key: 'ra', label: 'Tiền trúng' },
  { key: 'profit', label: 'Lợi nhuận' },
]
const unit = ref('day')
const metric = ref('profit')
const hover = ref(-1)
const unitInfo = computed(() => UNITS.find((u) => u.key === unit.value))
const metricInfo = computed(() => METRICS.find((m) => m.key === metric.value))

const series = computed(() => buildSeries(pseudoEntries(money.value.byDate, metric.value), { unit: unit.value, metric: metric.value }))
const totals = computed(() => rangeTotals(pseudoEntries(money.value.byDate, metric.value), { unit: unit.value, metric: metric.value }))
const delta = computed(() => (totals.value.previous === null ? null : totals.value.current - totals.value.previous))
const deltaPct = computed(() => {
  const p = totals.value.previous
  return p ? Math.round((delta.value / Math.abs(p)) * 100) : null
})
const signed = (n) => (n > 0 ? '+' : '') + fmt(n)
const tone = (n) => (metric.value === 'profit' ? (n >= 0 ? 'pos' : 'neg') : '')

const DENSE_BARS = 30
// chart geometry follows the real pixel width so labels keep their size on a 360px phone
const wrapEl = ref(null)
const W = ref(640)
const H = 210
const PAD = { l: 46, r: 8, t: 10, b: 26 }
let ro = null
onMounted(() => {
  if (typeof ResizeObserver === 'undefined') return
  ro = new ResizeObserver(([e]) => {
    W.value = Math.max(240, Math.round(e.contentRect.width))
  })
  watch(wrapEl, (el, old) => {
    if (old) ro.unobserve(old)
    if (el) ro.observe(el)
  }, { immediate: true })
})
onBeforeUnmount(() => ro?.disconnect())

const barTone = (v) => (metric.value === 'profit' ? (v < 0 ? 'neg' : 'pos') : 'main')
const plot = computed(() => {
  const list = series.value
  const vals = list.map((p) => p.value)
  let max = Math.max(0, ...vals)
  let min = Math.min(0, ...vals)
  if (max === min) max = min + 1
  const innerH = H - PAD.t - PAD.b
  const innerW = W.value - PAD.l - PAD.r
  const y = (v) => PAD.t + ((max - v) / (max - min)) * innerH
  const step = innerW / list.length
  // one bar width for every period (day / week / month / year): sized for the densest one, so switching the period never resizes the bars
  const bw = Math.min(26, Math.max(3, (innerW / Math.max(DENSE_BARS, list.length)) * 0.62))
  const bars = list.map((p, i) => {
    const cx = PAD.l + step * i + step / 2
    const y0 = y(0)
    const y1 = y(p.value)
    return { ...p, x: cx - bw / 2, w: bw, cx, y: Math.min(y0, y1), h: Math.max(Math.abs(y0 - y1), p.value ? 1.5 : 0), hx: PAD.l + step * i, hw: step }
  })
  const tv = min < 0 ? [max, 0, min] : [max, max / 2, 0]
  // drop a tick label that would sit on top of one already placed (tiny negative min next to 0)
  const ticks = []
  for (const v of tv) {
    const ty = y(v)
    if (v === 0 || !ticks.some((t) => Math.abs(t.y - ty) < 12)) ticks.push({ v, y: ty })
  }
  const shown = new Set(tickIndices(list.length, tickEvery(list.length, innerW)))
  return { bars, ticks, zeroY: y(0), shown, step }
})
const hovered = computed(() => plot.value.bars[hover.value] || null)
const tipLeft = computed(() => (hovered.value ? `${Math.min(Math.max((hovered.value.cx / W.value) * 100, 16), 84)}%` : null))
const reduced = typeof window !== 'undefined' && window.matchMedia?.('(prefers-reduced-motion: reduce)').matches

const stats = computed(() => ({ customers: money.value.customers, plays: money.value.plays, ...moneyTotals(money.value.byDate) }))
</script>

<template>
  <div>
    <div v-if="loading" class="card">Đang tải...</div>
    <div v-else-if="error" class="alert alert-error">{{ error }}</div>
    <template v-else>
      <p class="page-subtitle">Tổng hợp trên toàn bộ số liệu của bạn (tiền quy đổi như tab Tính điểm; ngày chưa có kết quả xổ số chưa tính vào lợi nhuận).</p>

      <section class="card stats-card" aria-label="Thống kê">
        <div class="stats-controls">
          <div class="ctl">
            <span :id="'seg-m'" class="ctl-label">Chỉ số</span>
            <div class="seg" role="radiogroup" aria-labelledby="seg-m">
              <label v-for="m in METRICS" :key="m.key" class="seg-opt">
                <input v-model="metric" type="radio" name="stats-metric" :value="m.key" />
                <span>{{ m.label }}</span>
              </label>
            </div>
          </div>
          <div class="ctl">
            <span id="seg-u" class="ctl-label">Kỳ</span>
            <div class="seg" role="radiogroup" aria-labelledby="seg-u">
              <label v-for="u in UNITS" :key="u.key" class="seg-opt">
                <input v-model="unit" type="radio" name="stats-unit" :value="u.key" />
                <span>{{ u.label }}</span>
              </label>
            </div>
          </div>
        </div>

        <div class="summary" aria-live="polite">
          <div class="sum-main">
            <span class="sum-label">{{ metricInfo.label }} · {{ unitInfo.range }}</span>
            <strong class="sum-value" :class="tone(totals.current)"><MaskedValue :text="(metric === 'profit' ? signed(totals.current) : fmt(totals.current)) + ' đ'" /></strong>
          </div>
          <div v-if="delta !== null" class="sum-prev">
            So với {{ unitInfo.prev }}:
            <b :class="tone(delta)"><MaskedValue :text="signed(delta) + ' đ' + (deltaPct !== null ? ` (${deltaPct > 0 ? '+' : ''}${deltaPct}%)` : '')" /></b>
          </div>
        </div>

        <p v-if="mask.masked.value" class="chart-masked">Biểu đồ đang ẩn. Bấm Hiện số liệu để xem.</p>
        <div v-else ref="wrapEl" class="chart-wrap" @mouseleave="hover = -1">
          <svg
            class="chart"
            :viewBox="`0 0 ${W} ${H}`"
            :width="W"
            :height="H"
            role="img"
            :aria-label="`Biểu đồ cột ${metricInfo.label.toLowerCase()} theo ${unitInfo.label.toLowerCase()}, ${unitInfo.range}`"
          >
            <g v-for="t in plot.ticks" :key="t.v">
              <line :x1="PAD.l" :x2="W - PAD.r" :y1="t.y" :y2="t.y" class="grid" />
              <text :x="PAD.l - 6" :y="t.y + 4" class="axis" text-anchor="end">{{ compactNumber(t.v) }}</text>
            </g>
            <line :x1="PAD.l" :x2="W - PAD.r" :y1="plot.zeroY" :y2="plot.zeroY" class="zero" />
            <g v-for="(b, i) in plot.bars" :key="b.key">
              <rect :x="b.x" :y="b.y" :width="b.w" :height="b.h" rx="2" :class="['bar', 'bar-' + barTone(b.value), { dim: hover >= 0 && hover !== i, still: reduced }]" />
              <text v-if="plot.shown.has(i)" :x="Math.min(Math.max(b.cx, PAD.l + 14), W - PAD.r - 14)" :y="H - 8" class="axis" text-anchor="middle">{{ b.label }}</text>
            </g>
            <rect
              v-for="(b, i) in plot.bars"
              :key="'h' + b.key"
              :x="b.hx"
              :y="PAD.t"
              :width="b.hw"
              :height="H - PAD.t - PAD.b"
              class="hit"
              @pointerenter="hover = i"
              @pointerdown="hover = i"
            />
          </svg>
          <div v-if="hovered" class="tip" :style="{ left: tipLeft }" role="status">
            <strong>{{ hovered.full }}</strong>
            <div>{{ metricInfo.label }}: <b :class="tone(hovered.value)">{{ fmt(hovered.value) }}</b></div>
          </div>
          <table class="sr-only">
            <caption>{{ metricInfo.label }} theo {{ unitInfo.label.toLowerCase() }}, {{ unitInfo.range }}</caption>
            <tbody>
              <tr v-for="p in series" :key="p.key"><th scope="row">{{ p.full }}</th><td>{{ fmt(p.value) }}</td></tr>
            </tbody>
          </table>
        </div>

        <dl class="facts">
          <div class="fact"><dt>Số lượng khách hàng</dt><dd><MaskedValue :text="fmt(stats.customers)" /></dd></div>
          <div class="fact"><dt>Số lượt chơi</dt><dd><MaskedValue :text="fmt(stats.plays)" /></dd></div>
          <div class="fact"><dt>Tổng tiền khách gửi</dt><dd><MaskedValue :text="fmt(stats.sent) + ' đ'" /></dd></div>
          <div class="fact"><dt>Tổng tiền khách trúng</dt><dd><MaskedValue :text="fmt(stats.won) + ' đ'" /></dd></div>
          <div class="fact fact-wide"><dt>Lợi nhuận toàn bộ</dt><dd :class="stats.profit >= 0 ? 'pos' : 'neg'"><MaskedValue :text="signed(stats.profit) + ' đ'" /></dd></div>
          <div v-if="stats.pendingLots > 0" class="fact fact-wide"><dt>Chưa có kết quả xổ số (chưa tính lợi nhuận)</dt><dd><MaskedValue :text="fmt(stats.pendingLots) + ' lô · ' + fmt(stats.pending) + ' đ'" /></dd></div>
        </dl>
      </section>
    </template>
  </div>
</template>

<style scoped>
.stats-mask {
  margin-bottom: 12px;
}
.stats-card {
  padding: 14px;
  border-radius: 14px;
}
.stats-controls {
  display: flex;
  flex-wrap: wrap;
  gap: 10px 20px;
}
.ctl {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 0;
}
.ctl-label {
  font-size: 12px;
  color: var(--muted);
}
.seg {
  display: inline-flex;
  overflow: hidden;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--surface);
}
.seg-opt {
  position: relative;
  display: flex;
}
.seg-opt input {
  position: absolute;
  inset: 0;
  margin: 0;
  opacity: 0;
  cursor: pointer;
}
.seg-opt span {
  display: flex;
  align-items: center;
  justify-content: center;
  min-width: 44px;
  min-height: 44px;
  padding: 0 12px;
  font-size: 13.5px;
  color: var(--muted);
  white-space: nowrap;
  transition: background 0.15s, color 0.15s;
}
.seg-opt + .seg-opt span {
  border-left: 1px solid var(--border);
}
.seg-opt input:checked + span {
  color: var(--on-primary, #fff);
  background: var(--primary);
  font-weight: 600;
}
.seg-opt input:focus-visible + span {
  outline: 2px solid var(--primary);
  outline-offset: -3px;
}
@media (max-width: 420px) {
  .stats-controls,
  .ctl,
  .seg {
    width: 100%;
  }
  .seg-opt {
    flex: 1;
  }
  .seg-opt span {
    width: 100%;
    padding: 0 6px;
    font-size: 13px;
  }
}
.summary {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  justify-content: space-between;
  gap: 4px 16px;
  margin: 14px 0 6px;
}
.sum-main {
  display: flex;
  flex-direction: column;
}
.sum-label,
.sum-prev {
  font-size: 12.5px;
  color: var(--muted);
}
.sum-value {
  font-size: 24px;
  font-variant-numeric: tabular-nums;
}
.pos {
  color: var(--success-text);
}
.neg {
  color: var(--danger-text);
}
.chart-masked {
  padding: 36px 0;
  text-align: center;
  color: var(--muted);
}
.chart-wrap {
  position: relative;
  width: 100%;
  min-height: 210px;
}
.chart {
  display: block;
  max-width: 100%;
  touch-action: pan-y;
}
.grid {
  stroke: var(--border);
  stroke-width: 1;
  stroke-dasharray: 2 4;
}
.zero {
  stroke: var(--text-primary);
  stroke-width: 1.25;
  opacity: 0.55;
}
.axis {
  font-size: 10.5px;
  fill: var(--muted);
  font-variant-numeric: tabular-nums;
}
.hit {
  fill: transparent;
}
.bar {
  transition: opacity 0.15s;
}
.bar.still {
  transition: none;
}
.bar-main {
  fill: var(--primary);
}
.bar-pos {
  fill: var(--success-text);
}
.bar-neg {
  fill: var(--danger-text);
}
.dim {
  opacity: 0.35;
}
@media (prefers-reduced-motion: reduce) {
  .bar,
  .seg-opt span {
    transition: none;
  }
}
.tip {
  position: absolute;
  top: 0;
  transform: translateX(-50%);
  padding: 6px 10px;
  font-size: 12.5px;
  line-height: 1.45;
  white-space: nowrap;
  pointer-events: none;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  box-shadow: var(--shadow-md);
}
.sr-only {
  position: absolute;
  width: 1px;
  height: 1px;
  overflow: hidden;
  clip: rect(0 0 0 0);
  white-space: nowrap;
}
.facts {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 8px 12px;
  margin: 12px 0 0;
  padding-top: 12px;
  border-top: 1px solid var(--border);
}
@media (min-width: 640px) {
  .facts {
    grid-template-columns: repeat(5, 1fr);
  }
}
.fact {
  min-width: 0;
}
.fact-wide {
  grid-column: 1 / -1;
}
@media (min-width: 640px) {
  .fact-wide {
    grid-column: auto;
  }
}
.fact dt {
  font-size: 12px;
  color: var(--muted);
}
.fact dd {
  margin: 2px 0 0;
  font-size: 16px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
</style>
