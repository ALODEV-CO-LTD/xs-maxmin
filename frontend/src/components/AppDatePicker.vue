<!--
  Themed date picker replacing <input type="date">. Same contract as the
  native input: v-model is an ISO "YYYY-MM-DD" string ('' when empty), and a
  `change` event fires after the user picks/clears a date (after v-model has
  been updated). The field shows dd/mm/yyyy, like the native one did.
  `class` lands on the wrapper (set width/height there); other attrs
  (id, aria-*) go to the trigger button.
-->
<script setup>
import { computed, nextTick, onBeforeUnmount, ref } from 'vue'
import AppIcon from './AppIcon.vue'

defineOptions({ inheritAttrs: false })
const props = defineProps({
  modelValue: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
})
const emit = defineEmits(['update:modelValue', 'change'])

const WEEKDAYS = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
const MONTHS = Array.from({ length: 12 }, (_, i) => `Tháng ${i + 1}`)

const pad = (n) => String(n).padStart(2, '0')
const iso = (y, m, d) => `${y}-${pad(m + 1)}-${pad(d)}`
function parse(v) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v || '')
  return m ? { y: +m[1], m: +m[2] - 1, d: +m[3] } : null
}
const today = () => {
  const t = new Date()
  return { y: t.getFullYear(), m: t.getMonth(), d: t.getDate() }
}

const display = computed(() => {
  const p = parse(props.modelValue)
  return p ? `${pad(p.d)}/${pad(p.m + 1)}/${p.y}` : ''
})

const open = ref(false)
const view = ref('days') // 'days' | 'months' | 'years'
const viewY = ref(0)
const viewM = ref(0)
const yearStart = ref(0)
const cursor = ref(iso(2000, 0, 1)) // keyboard-focused day
const popStyle = ref({})
const root = ref(null)
const pop = ref(null)

const cells = computed(() => {
  const first = new Date(viewY.value, viewM.value, 1)
  const offset = (first.getDay() + 6) % 7
  const out = []
  for (let i = 0; i < 42; i++) {
    const d = new Date(viewY.value, viewM.value, 1 - offset + i)
    out.push({
      key: iso(d.getFullYear(), d.getMonth(), d.getDate()),
      day: d.getDate(),
      outside: d.getMonth() !== viewM.value,
    })
  }
  return out
})
const years = computed(() => Array.from({ length: 12 }, (_, i) => yearStart.value + i))
const selectedKey = computed(() => props.modelValue)
const todayKey = computed(() => {
  const t = today()
  return iso(t.y, t.m, t.d)
})
const title = computed(() => {
  if (view.value === 'days') return `${MONTHS[viewM.value]} ${viewY.value}`
  if (view.value === 'months') return String(viewY.value)
  return `${years.value[0]} - ${years.value[11]}`
})

function openPicker() {
  if (props.disabled) return
  const p = parse(props.modelValue) || today()
  viewY.value = p.y
  viewM.value = p.m
  yearStart.value = p.y - (p.y % 12)
  cursor.value = iso(p.y, p.m, p.d)
  view.value = 'days'
  // fixed positioning: never clipped by overflow parents, never off-screen
  const r = root.value.getBoundingClientRect()
  const w = Math.min(304, window.innerWidth - 16)
  const left = Math.max(8, Math.min(r.left, window.innerWidth - w - 8))
  const flip = window.innerHeight - r.bottom < 380 && r.top > 380
  popStyle.value = flip
    ? { left: left + 'px', width: w + 'px', bottom: window.innerHeight - r.top + 4 + 'px' }
    : { left: left + 'px', width: w + 'px', top: r.bottom + 4 + 'px' }
  open.value = true
  document.addEventListener('mousedown', onOutside)
  window.addEventListener('scroll', onScrollAway, true)
  window.addEventListener('resize', closePicker)
  nextTick(focusCursor)
}
function closePicker() {
  open.value = false
  document.removeEventListener('mousedown', onOutside)
  window.removeEventListener('scroll', onScrollAway, true)
  window.removeEventListener('resize', closePicker)
}
function onOutside(e) {
  if (root.value && !root.value.contains(e.target) && !(pop.value && pop.value.contains(e.target))) closePicker()
}
function onScrollAway(e) {
  if (pop.value && pop.value.contains(e.target)) return
  closePicker()
}
function focusCursor() {
  pop.value?.querySelector('[data-cursor="true"]')?.focus()
}

function commit(value) {
  emit('update:modelValue', value)
  emit('change', value)
  closePicker()
  root.value?.querySelector('.dp-trigger')?.focus()
}
const pick = (key) => commit(key)
const pickToday = () => commit(todayKey.value)
const clear = () => commit('')

function shiftMonth(delta) {
  let m = viewM.value + delta
  let y = viewY.value
  while (m < 0) { m += 12; y-- }
  while (m > 11) { m -= 12; y++ }
  viewM.value = m
  viewY.value = y
}
function prev() {
  if (view.value === 'days') shiftMonth(-1)
  else if (view.value === 'months') viewY.value--
  else yearStart.value -= 12
}
function next() {
  if (view.value === 'days') shiftMonth(1)
  else if (view.value === 'months') viewY.value++
  else yearStart.value += 12
}
function toggleView() {
  if (view.value === 'days') view.value = 'months'
  else if (view.value === 'months') {
    yearStart.value = viewY.value - (viewY.value % 12)
    view.value = 'years'
  } else view.value = 'days'
}
function pickMonth(i) {
  viewM.value = i
  view.value = 'days'
}
function pickYear(y) {
  viewY.value = y
  view.value = 'months'
}

function moveCursor(days, months = 0) {
  const p = parse(cursor.value)
  const d = new Date(p.y, p.m + months, p.d + days)
  cursor.value = iso(d.getFullYear(), d.getMonth(), d.getDate())
  viewY.value = d.getFullYear()
  viewM.value = d.getMonth()
  nextTick(focusCursor)
}
function onPopKey(e) {
  if (e.key === 'Escape') {
    e.preventDefault()
    closePicker()
    root.value?.querySelector('.dp-trigger')?.focus()
    return
  }
  if (view.value !== 'days' || !e.target.closest('.dp-day')) return
  const k = e.key
  if (k === 'ArrowLeft') { e.preventDefault(); moveCursor(-1) }
  else if (k === 'ArrowRight') { e.preventDefault(); moveCursor(1) }
  else if (k === 'ArrowUp') { e.preventDefault(); moveCursor(-7) }
  else if (k === 'ArrowDown') { e.preventDefault(); moveCursor(7) }
  else if (k === 'PageUp') { e.preventDefault(); moveCursor(0, -1) }
  else if (k === 'PageDown') { e.preventDefault(); moveCursor(0, 1) }
}
function onTriggerKey(e) {
  if (e.key === 'ArrowDown' && !open.value) {
    e.preventDefault()
    openPicker()
  }
}
onBeforeUnmount(closePicker)
</script>

<template>
  <div ref="root" class="app-date" :class="[$attrs.class, { 'is-open': open, 'is-disabled': disabled }]">
    <button
      v-bind="{ ...$attrs, class: undefined, style: undefined }"
      type="button"
      class="dp-trigger"
      aria-haspopup="dialog"
      :aria-expanded="open"
      :disabled="disabled"
      @click="open ? closePicker() : openPicker()"
      @keydown="onTriggerKey"
    >
      <span class="dp-value" :class="{ placeholder: !display }">{{ display || 'dd/mm/yyyy' }}</span>
      <AppIcon name="calendar" class="dp-icon" />
    </button>

    <div v-if="open" ref="pop" class="dp-pop" :style="popStyle" role="dialog" aria-label="Chọn ngày" @keydown="onPopKey">
      <div class="dp-head">
        <button type="button" class="dp-nav" aria-label="Trước" @click="prev"><AppIcon name="chevron-left" /></button>
        <button type="button" class="dp-title" @click="toggleView">{{ title }}</button>
        <button type="button" class="dp-nav" aria-label="Sau" @click="next"><AppIcon name="chevron-right" /></button>
      </div>

      <div v-if="view === 'days'">
        <div class="dp-weekdays">
          <span v-for="w in WEEKDAYS" :key="w">{{ w }}</span>
        </div>
        <div class="dp-days">
          <button
            v-for="c in cells"
            :key="c.key"
            type="button"
            class="dp-day"
            :class="{ outside: c.outside, selected: c.key === selectedKey, today: c.key === todayKey }"
            :data-cursor="c.key === cursor"
            :tabindex="c.key === cursor ? 0 : -1"
            :aria-label="c.key"
            :aria-pressed="c.key === selectedKey"
            @click="pick(c.key)"
          >
            {{ c.day }}
          </button>
        </div>
      </div>

      <div v-else-if="view === 'months'" class="dp-grid">
        <button
          v-for="(name, i) in MONTHS"
          :key="name"
          type="button"
          class="dp-cell"
          :class="{
            selected: parse(modelValue)?.y === viewY && parse(modelValue)?.m === i,
            today: today().y === viewY && today().m === i,
          }"
          @click="pickMonth(i)"
        >
          {{ name }}
        </button>
      </div>

      <div v-else class="dp-grid">
        <button
          v-for="y in years"
          :key="y"
          type="button"
          class="dp-cell"
          :class="{ selected: parse(modelValue)?.y === y, today: today().y === y }"
          @click="pickYear(y)"
        >
          {{ y }}
        </button>
      </div>

      <div class="dp-foot">
        <button type="button" class="dp-action" @click="pickToday">Hôm nay</button>
        <button type="button" class="dp-action" @click="clear">Xoá</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.app-date {
  position: relative;
  width: 100%;
  height: var(--ctl-h, 44px);
}
.dp-trigger {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 0 12px 0 14px;
  font-family: var(--font-body);
  font-size: 15px;
  font-weight: inherit;
  font-variant-numeric: tabular-nums;
  text-align: left;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  cursor: pointer;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.dp-trigger:hover:not(:disabled) {
  border-color: var(--input-border-hover);
}
.dp-trigger:focus-visible,
.app-date.is-open .dp-trigger {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.dp-trigger:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}
.dp-value.placeholder {
  color: var(--text-secondary);
}
.dp-icon {
  flex: none;
  width: 18px;
  height: 18px;
  color: var(--text-secondary);
}
.app-date.is-open .dp-icon {
  color: var(--primary);
}

.dp-pop {
  position: fixed;
  z-index: 60;
  padding: 12px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 14px;
  box-shadow: var(--shadow-lg);
  color: var(--text-primary);
}
.dp-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 4px;
  margin-bottom: 8px;
}
.dp-nav,
.dp-title,
.dp-day,
.dp-cell,
.dp-action {
  font-family: var(--font-body);
  color: inherit;
  background: transparent;
  border: 0;
  cursor: pointer;
}
.dp-nav {
  width: 36px;
  height: 36px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  color: var(--text-secondary);
  border-radius: 10px;
}
.dp-title {
  flex: 1;
  height: 36px;
  font-size: 15px;
  font-weight: 700;
  border-radius: 10px;
}
.dp-nav:hover,
.dp-title:hover {
  background: var(--surface);
  color: var(--text-primary);
}

.dp-weekdays,
.dp-days {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
}
.dp-weekdays {
  margin-bottom: 4px;
}
.dp-weekdays span {
  height: 28px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 700;
  color: var(--text-secondary);
}
.dp-days {
  gap: 2px;
}
.dp-day {
  height: 36px;
  font-size: 14px;
  font-variant-numeric: tabular-nums;
  border-radius: 10px;
}
.dp-day.outside {
  color: var(--text-secondary);
  opacity: 0.55;
}
.dp-day:hover {
  background: var(--surface);
}
.dp-day.today {
  box-shadow: inset 0 0 0 1px var(--input-border);
  font-weight: 700;
}
.dp-day.selected,
.dp-cell.selected {
  background: var(--primary);
  color: var(--on-primary);
  font-weight: 700;
  opacity: 1;
  box-shadow: none;
}
.dp-day.selected:hover,
.dp-cell.selected:hover {
  background: var(--primary-hover);
  color: var(--on-primary-hover);
}
.dp-day:focus-visible,
.dp-cell:focus-visible,
.dp-nav:focus-visible,
.dp-title:focus-visible,
.dp-action:focus-visible {
  outline: 2px solid var(--primary);
  outline-offset: 1px;
}

.dp-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 6px;
  padding: 4px 0;
}
.dp-cell {
  height: 48px;
  font-size: 14px;
  border-radius: 10px;
}
.dp-cell:hover {
  background: var(--surface);
}
.dp-cell.today:not(.selected) {
  box-shadow: inset 0 0 0 1px var(--input-border);
  font-weight: 700;
}

.dp-foot {
  display: flex;
  justify-content: space-between;
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid var(--border);
}
.dp-action {
  height: 32px;
  padding: 0 12px;
  font-size: 14px;
  font-weight: 600;
  color: var(--link);
  border-radius: 8px;
}
.dp-action:hover {
  background: var(--surface);
}
</style>
