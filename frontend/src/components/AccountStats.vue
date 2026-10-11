<!--
  Thống kê tab of the Tài khoản page: roster size, number of plays (entries),
  total points in/out and profit (vào − ra), same parsing convention as
  EntriesView / CustomersView. Figures hide while "Ẩn số liệu" is on.
  Below the cards: a bar chart by day (last 30), month (last 12) or year,
  for profit / points in / points out.
  API: GET /me/customers, GET /me/entries (all pages, cached offline).
-->
<script setup>
import { computed, onMounted, ref } from 'vue'
import { cachedGet, loadAllEntries } from '../offline'
import MaskBar from './MaskBar.vue'
import MaskedValue from './MaskedValue.vue'
import { mask } from '../stores/mask'

const loading = ref(true)
const error = ref('')
const roster = ref([])
const entries = ref([])

function toNumber(str) {
  if (!str) return 0
  const n = parseFloat(String(str).replace(/[^\d.-]/g, ''))
  return Number.isFinite(n) ? n : 0
}
const fmt = (n) => new Intl.NumberFormat('vi-VN').format(n)

onMounted(async () => {
  try {
    const [{ customers }, list] = await Promise.all([cachedGet('/me/customers'), loadAllEntries()])
    roster.value = customers
    entries.value = list.entries
  } catch (err) {
    error.value = err.message || 'Không tải được thống kê'
  } finally {
    loading.value = false
  }
})

// ---- chart ----
const UNITS = [
  { key: 'day', label: 'Ngày' },
  { key: 'month', label: 'Tháng' },
  { key: 'year', label: 'Năm' },
]
const METRICS = [
  { key: 'profit', label: 'Lợi nhuận' },
  { key: 'vao', label: 'Điểm vào' },
  { key: 'ra', label: 'Điểm ra' },
]
const unit = ref('day')
const metric = ref('profit')
const hover = ref(-1)

const pad = (n) => String(n).padStart(2, '0')
const SPAN = { day: 30, month: 12, year: 5 }

// Continuous list of period keys ending at the current period (empty periods = 0).
function periodKeys(u) {
  const now = new Date()
  const out = []
  for (let i = SPAN[u] - 1; i >= 0; i--) {
    if (u === 'day') {
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)
      out.push(`${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`)
    } else if (u === 'month') {
      const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
      out.push(`${d.getFullYear()}-${pad(d.getMonth() + 1)}`)
    } else {
      out.push(String(now.getFullYear() - i))
    }
  }
  return out
}
function keyOf(entryDate, u) {
  const d = String(entryDate || '').slice(0, 10)
  return u === 'day' ? d : u === 'month' ? d.slice(0, 7) : d.slice(0, 4)
}
function labelOf(k, u) {
  if (u === 'day') return `${k.slice(8, 10)}/${k.slice(5, 7)}`
  if (u === 'month') return `${k.slice(5, 7)}/${k.slice(0, 4)}`
  return k
}
function fullLabelOf(k, u) {
  if (u === 'day') return `${k.slice(8, 10)}/${k.slice(5, 7)}/${k.slice(0, 4)}`
  return labelOf(k, u)
}

const series = computed(() => {
  const keys = periodKeys(unit.value)
  const acc = new Map(keys.map((k) => [k, { vao: 0, ra: 0 }]))
  for (const e of entries.value) {
    const b = acc.get(keyOf(e.entryDate, unit.value))
    if (!b) continue
    b.vao += toNumber(e.score)
    b.ra += toNumber(e.result)
  }
  return keys.map((k) => {
    const b = acc.get(k)
    const value = metric.value === 'profit' ? b.vao - b.ra : b[metric.value]
    return { key: k, label: labelOf(k, unit.value), full: fullLabelOf(k, unit.value), value }
  })
})

const W = 720
const H = 170
const PAD = { l: 40, r: 6, t: 8, b: 22 }
const plot = computed(() => {
  const vals = series.value.map((p) => p.value)
  let max = Math.max(0, ...vals)
  let min = Math.min(0, ...vals)
  if (max === min) max = min + 1
  const innerH = H - PAD.t - PAD.b
  const innerW = W - PAD.l - PAD.r
  const y = (v) => PAD.t + ((max - v) / (max - min)) * innerH
  const step = innerW / series.value.length
  const bw = Math.min(12, Math.max(3, step * 0.45))
  const bars = series.value.map((p, i) => {
    const cx = PAD.l + step * i + step / 2
    const y0 = y(0)
    const y1 = y(p.value)
    return { ...p, x: cx - bw / 2, w: bw, cx, y: Math.min(y0, y1), h: Math.max(Math.abs(y0 - y1), p.value ? 1 : 0) }
  })
  const ticks = (min < 0 ? [max, 0, min] : [max, max / 2, 0]).map((v) => ({ v, y: y(v) }))
  // thin out x labels so they never overlap
  const every = Math.ceil(series.value.length / (unit.value === 'day' ? 8 : 12))
  return { bars, ticks, zeroY: y(0), every }
})
const shortNum = (n) => {
  const a = Math.abs(n)
  if (a >= 1e9) return `${+(n / 1e9).toFixed(1)}B`
  if (a >= 1e6) return `${+(n / 1e6).toFixed(1)}M`
  if (a >= 1e3) return `${+(n / 1e3).toFixed(1)}K`
  return String(Math.round(n))
}
const barClass = (v) => (metric.value === 'profit' ? (v >= 0 ? 'bar-in' : 'bar-out') : metric.value === 'vao' ? 'bar-in' : 'bar-out')
const hovered = computed(() => plot.value.bars[hover.value] || null)

const stats = computed(() => {
  const names = new Set(roster.value.map((c) => c.name))
  let vao = 0
  let ra = 0
  for (const e of entries.value) {
    names.add(e.customerName || '(Không tên)')
    vao += toNumber(e.score)
    ra += toNumber(e.result)
  }
  return { customers: names.size, plays: entries.value.length, vao, ra, profit: vao - ra }
})
</script>

<template>
  <div>
    <div v-if="loading" class="card">Đang tải...</div>
    <div v-else-if="error" class="alert alert-error">{{ error }}</div>
    <template v-else>
      <MaskBar class="stats-mask" />
      <p class="page-subtitle">Tổng hợp trên toàn bộ số liệu của bạn (điểm vào/ra để trống được tính là 0).</p>
      <div class="stats-grid">
        <div class="card stat-card">
          <div class="stat-label">Số lượng khách hàng</div>
          <div class="stat-value"><MaskedValue :text="fmt(stats.customers)" /></div>
        </div>
        <div class="card stat-card">
          <div class="stat-label">Số lượt chơi</div>
          <div class="stat-value"><MaskedValue :text="fmt(stats.plays)" /></div>
        </div>
        <div class="card stat-card">
          <div class="stat-label">Tổng điểm vào</div>
          <div class="stat-value calc-in"><MaskedValue :text="fmt(stats.vao)" /></div>
        </div>
        <div class="card stat-card">
          <div class="stat-label">Tổng điểm ra</div>
          <div class="stat-value calc-out"><MaskedValue :text="fmt(stats.ra)" /></div>
        </div>
        <div class="card stat-card stat-wide">
          <div class="stat-label">Lợi nhuận (vào − ra)</div>
          <div class="stat-value" :class="stats.profit >= 0 ? 'calc-in' : 'calc-out'"><MaskedValue :text="fmt(stats.profit)" /></div>
        </div>
      </div>

      <div class="card chart-card">
        <div class="chart-head">
          <div class="seg" role="tablist" aria-label="Xem theo">
            <button v-for="u in UNITS" :key="u.key" type="button" class="seg-btn" :class="{ on: unit === u.key }" @click="unit = u.key">{{ u.label }}</button>
          </div>
          <div class="seg" role="tablist" aria-label="Chỉ số">
            <button v-for="m in METRICS" :key="m.key" type="button" class="seg-btn" :class="{ on: metric === m.key }" @click="metric = m.key">{{ m.label }}</button>
          </div>
        </div>
        <p class="chart-sub">
          {{ unit === 'day' ? '30 ngày gần nhất' : unit === 'month' ? '12 tháng gần nhất' : '5 năm gần nhất' }}
          <template v-if="hovered && !mask.masked.value"> · <b>{{ hovered.full }}</b>: {{ fmt(hovered.value) }}</template>
        </p>
        <p v-if="mask.masked.value" class="chart-masked">Biểu đồ đang ẩn. Bấm Hiện số liệu để xem.</p>
        <svg v-else class="chart" :viewBox="`0 0 ${W} ${H}`" role="img" :aria-label="`Biểu đồ ${METRICS.find((m) => m.key === metric).label} theo ${UNITS.find((x) => x.key === unit).label}`">
          <g v-for="t in plot.ticks" :key="t.y">
            <line :x1="PAD.l" :x2="W - PAD.r" :y1="t.y" :y2="t.y" class="grid" />
            <text :x="PAD.l - 8" :y="t.y + 4" class="axis" text-anchor="end">{{ shortNum(t.v) }}</text>
          </g>
          <line :x1="PAD.l" :x2="W - PAD.r" :y1="plot.zeroY" :y2="plot.zeroY" class="zero" />
          <g v-for="(b, i) in plot.bars" :key="b.key" @mouseenter="hover = i" @mouseleave="hover = -1" @click="hover = i">
            <rect :x="PAD.l + (W - PAD.l - PAD.r) / plot.bars.length * i" :y="PAD.t" :width="(W - PAD.l - PAD.r) / plot.bars.length" :height="H - PAD.t - PAD.b" class="hit" />
            <rect :x="b.x" :y="b.y" :width="b.w" :height="b.h" rx="2" :class="[barClass(b.value), { dim: hover >= 0 && hover !== i }]" />
            <text v-if="(plot.bars.length - 1 - i) % plot.every === 0" :x="b.cx" :y="H - 7" class="axis" text-anchor="middle">{{ b.label }}</text>
          </g>
        </svg>
      </div>
    </template>
  </div>
</template>

<style scoped>
.chart-card {
  margin-top: 14px;
  padding: 12px 14px 10px;
  border-radius: 12px;
}
.chart-head {
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 8px 12px;
}
.seg {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 6px;
}
.seg-btn {
  min-height: 26px;
  padding: 0 11px;
  font: inherit;
  font-size: 12.5px;
  color: var(--muted);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  cursor: pointer;
}
.seg-btn.on {
  color: #fff;
  background: var(--primary);
  border-color: var(--primary);
}
.chart-sub {
  min-height: 18px;
  margin: 8px 0 2px;
  font-size: 12px;
  color: var(--muted);
}
.chart-masked {
  padding: 36px 0;
  text-align: center;
  color: var(--muted);
}
.chart {
  display: block;
  width: 100%;
  max-width: 640px;
  height: auto;
  margin: 0 auto;
}
.grid {
  stroke: var(--border);
  stroke-width: 1;
  stroke-dasharray: 2 4;
  opacity: 0.7;
}
.zero {
  stroke: var(--border);
  stroke-width: 1;
}
.axis {
  font-size: 9.5px;
  fill: var(--muted);
}
.hit {
  fill: transparent;
}
.bar-in {
  fill: var(--success-text);
  opacity: 0.85;
}
.bar-out {
  fill: var(--danger-text);
  opacity: 0.85;
}
.dim {
  opacity: 0.3;
}
.stats-mask {
  margin-bottom: 12px;
}
.stats-grid {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 10px;
}
@media (min-width: 640px) {
  .stats-grid {
    grid-template-columns: repeat(4, 1fr);
  }
}
.stat-card {
  text-align: center;
  padding: 12px;
  border-radius: 12px;
}
.stat-wide {
  grid-column: 1 / -1;
}
.stat-label {
  margin-bottom: 4px;
  font-size: 13px;
  color: var(--muted);
}
.stat-value {
  font-size: 20px;
  font-weight: 700;
}
.calc-in {
  color: var(--success-text);
}
.calc-out {
  color: var(--danger-text);
}
</style>
