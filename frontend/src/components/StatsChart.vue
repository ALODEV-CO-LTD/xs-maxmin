<!--
  One time-series chart (SVG, no library). `points` = [{ date, value }], `kind` = 'bar' | 'line'.
  The viewBox follows the container's pixel width so labels keep their true size.
-->
<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'

const props = defineProps({
  points: { type: Array, required: true },
  kind: { type: String, default: 'bar' },
  color: { type: String, default: 'var(--primary)' },
  label: { type: String, required: true },
  money: { type: Boolean, default: false },
})

const W = ref(720)
const H = computed(() => Math.round(Math.min(300, Math.max(200, W.value * 0.26))))
const PAD = { l: props.money ? 56 : 36, r: 12, t: 12, b: 28 }
const plotW = computed(() => W.value - PAD.l - PAD.r)
const plotH = computed(() => H.value - PAD.t - PAD.b)
const wrapEl = ref(null)
const hover = ref(-1)
let ro = null
onMounted(() => {
  if (typeof ResizeObserver === 'undefined') return
  ro = new ResizeObserver(([e]) => {
    W.value = Math.max(280, Math.round(e.contentRect.width))
  })
  watch(wrapEl, (el, old) => {
    if (old) ro.unobserve(old)
    if (el) ro.observe(el)
  }, { immediate: true })
})
onBeforeUnmount(() => ro?.disconnect())

// Round the axis maximum up to 1/2/5 x 10^n so ticks read cleanly.
function niceMax(v) {
  if (v <= 0) return 4
  const p = 10 ** Math.floor(Math.log10(v))
  const n = v / p
  return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10) * p
}
const max = computed(() => {
  const m = niceMax(Math.max(0, ...props.points.map((d) => d.value)))
  return props.money ? m : Math.max(4, m)
})
const step = computed(() => plotW.value / Math.max(1, props.points.length))
const xAt = (i) => PAD.l + step.value * (i + 0.5)
const yAt = (v) => PAD.t + plotH.value - (v / max.value) * plotH.value
const barW = computed(() => Math.max(2, Math.min(28, step.value * 0.6)))
const linePoints = computed(() => props.points.map((d, i) => `${xAt(i)},${yAt(d.value)}`).join(' '))
const total = computed(() => props.points.reduce((a, d) => a + d.value, 0))
const xLabels = computed(() => {
  const n = props.points.length
  const every = Math.ceil(n / Math.max(3, Math.floor(plotW.value / 70)))
  return props.points.map((d, i) => ({ i, text: shortDate(d.date) })).filter((l) => l.i % every === 0 || l.i === n - 1)
})

function shortDate(k) {
  return k.length === 7 ? `${k.slice(5)}/${k.slice(2, 4)}` : `${k.slice(8)}/${k.slice(5, 7)}`
}
function longDate(k) {
  return k.length === 7 ? `Tháng ${k.slice(5)}/${k.slice(0, 4)}` : `${k.slice(8)}/${k.slice(5, 7)}/${k.slice(0, 4)}`
}
function short(v) {
  if (!props.money) return String(+v.toFixed(1))
  if (v >= 1e6) return `${+(v / 1e6).toFixed(1)}tr`
  if (v >= 1e3) return `${+(v / 1e3).toFixed(0)}k`
  return String(v)
}
const full = (v) => (props.money ? Number(v).toLocaleString('vi-VN') + ' đ' : String(v))
const tipLeft = computed(() => (hover.value < 0 ? null : `${Math.min(Math.max((xAt(hover.value) / W.value) * 100, 14), 86)}%`))
</script>

<template>
  <div class="card sc">
    <div class="sc-head">
      <span class="sc-label"><i class="sw" :class="kind === 'bar' ? 'sw-bar' : 'sw-line'" :style="{ background: color }"></i>{{ label }}</span>
      <strong class="sc-total">{{ full(total) }}</strong>
    </div>
    <div ref="wrapEl" class="sc-wrap" @mouseleave="hover = -1">
      <svg :viewBox="`0 0 ${W} ${H}`" :width="W" :height="H" role="img" :aria-label="label">
        <g v-for="t in 5" :key="t">
          <line :x1="PAD.l" :x2="W - PAD.r" :y1="PAD.t + (plotH / 4) * (t - 1)" :y2="PAD.t + (plotH / 4) * (t - 1)" class="grid" />
          <text :x="PAD.l - 8" :y="PAD.t + (plotH / 4) * (t - 1) + 4" class="tick" text-anchor="end">{{ short((max / 4) * (5 - t)) }}</text>
        </g>
        <template v-if="kind === 'bar'">
          <rect
            v-for="(d, i) in points"
            :key="'b' + d.date"
            :x="xAt(i) - barW / 2"
            :y="yAt(d.value)"
            :width="barW"
            :height="Math.max(0, PAD.t + plotH - yAt(d.value))"
            rx="3"
            :fill="color"
            :opacity="hover >= 0 && hover !== i ? 0.4 : 0.85"
          />
        </template>
        <template v-else>
          <polyline :points="linePoints" fill="none" :stroke="color" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round" />
          <circle v-for="(d, i) in points" :key="'p' + d.date" :cx="xAt(i)" :cy="yAt(d.value)" :r="hover === i ? 5 : points.length > 40 ? 0 : 3" :fill="color" />
        </template>
        <text v-for="l in xLabels" :key="'x' + l.i" :x="xAt(l.i)" :y="H - 8" class="tick" text-anchor="middle">{{ l.text }}</text>
        <rect
          v-for="(d, i) in points"
          :key="'h' + d.date"
          :x="PAD.l + step * i"
          :y="PAD.t"
          :width="step"
          :height="plotH"
          fill="transparent"
          @mouseenter="hover = i"
          @touchstart.passive="hover = i"
        />
      </svg>
      <div v-if="tipLeft" class="tip" :style="{ left: tipLeft }">
        <strong>{{ longDate(points[hover].date) }}</strong>
        <div>{{ label }}: {{ full(points[hover].value) }}</div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.sc {
  padding: 16px 16px 8px;
  border-radius: 14px;
}
.sc-head {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  justify-content: space-between;
  gap: 4px 16px;
  margin-bottom: 8px;
}
.sc-label {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 14px;
  font-weight: 600;
  color: var(--muted);
}
.sc-total {
  font-size: 18px;
  font-variant-numeric: tabular-nums;
}
.sw-bar {
  display: inline-block;
  width: 12px;
  height: 12px;
  border-radius: 3px;
}
.sw-line {
  display: inline-block;
  width: 16px;
  height: 3px;
  border-radius: 2px;
}
.sc-wrap {
  position: relative;
}
svg {
  display: block;
  max-width: 100%;
}
.grid {
  stroke: var(--border);
  stroke-width: 1;
}
.tick {
  font-size: 11px;
  fill: var(--muted);
  font-variant-numeric: tabular-nums;
}
.tip {
  position: absolute;
  top: 4px;
  transform: translateX(-50%);
  padding: 8px 12px;
  font-size: 13px;
  line-height: 1.5;
  white-space: nowrap;
  pointer-events: none;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  box-shadow: var(--shadow-md);
}
</style>
