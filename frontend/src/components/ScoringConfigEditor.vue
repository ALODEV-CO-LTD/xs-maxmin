<!--
  Cấu hình tính điểm = "bảng cấu hình" của khách: mỗi dòng một kiểu đánh, ở từng miền:
      Kiểu đánh | Ký hiệu | Giá tiền / 1 điểm | Giá trúng / 1 điểm
  Tiền xác = điểm × giá tiền; tiền trúng = số lần trúng × điểm × giá trúng; lợi nhuận = xác - trúng.
  Cách xác định trúng của từng kiểu (bao lô, đầu, đuôi, 3 càng, 4 càng, xiên 2/3/4) đã cố định trong code
  (scoringSummary.js), không phải chọn giải hay số chữ số; chỉ "Kiểu đánh khác" (người dùng tự đặt tên + ký hiệu) chọn
  được so với giải nào.

  One editor for both places:
    scope="default"   the account-wide settings (menu Cấu hình tính điểm)         GET/PUT /me/scoring-settings
    scope="customer"  one customer's own settings (Khách hàng > Cấu hình tính điểm); props: customer, accountRates
                      PATCH /me/customers/:id { scoringRates }
  Stored in one map: `type` = every region, `type@mb|mt|mn` = that region only (wins over `type`). A row you do not
  change keeps following the general value. Customer scope: a row can be switched off for that customer in that region.
  Emits: saved(map)
-->
<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { api, ApiError } from '../api'
import { showConfirm } from '../confirm'
import { betTypeLabel } from '../betTypes'
import { baseKey, defaultRow, defaultSource, defaultSymbols, DEFAULT_RATES, describeSource, effectiveSource, kindSource, normalizeSource, prizeInfo, sameSource, sourceFields, makeRow, parseSymbols, regionKey, sameConfig, symbolsText, TABLE_GROUPS, TABLE_KINDS, TABLE_KIND_KEYS, toTableRow, typesIn } from '../scoringConfig'
import { REGION_IDS } from '../lotteryStations'

const props = defineProps({
  scope: { type: String, default: 'default' }, // 'default' | 'customer'
  customer: { type: Object, default: null }, // { id, name, scoringRates } (customer scope)
  accountRates: { type: Object, default: () => ({}) }, // the account-wide map (customer scope: the fallback)
})
const emit = defineEmits(['saved'])

const isCustomer = computed(() => props.scope === 'customer')
const REGION_NAMES = { mb: 'Miền Bắc', mt: 'Miền Trung', mn: 'Miền Nam' }
const region = ref('mb')
// Values and ký hiệu are shown as text; only after "Sửa" can they be changed.
const editing = ref(false)
const nf = new Intl.NumberFormat('vi-VN')
const fmt = (v) => nf.format(Number(v) || 0)
const loading = ref(true)
const saving = ref(false)
const error = ref('')
const notice = ref('')

// The map being edited: the account-wide one (default scope) or this customer's overrides (customer scope).
const work = reactive({})
let initial = ''
const base = computed(() => (isCustomer.value ? props.accountRates : {}))

const byKey = (o) => Object.fromEntries(Object.entries(o).sort(([a], [b]) => a.localeCompare(b)))
const sorted = (o) => byKey(Object.fromEntries(Object.entries(o).map(([k, v]) => [k, v.disabled ? v : byKey({ ...v, tiers: [...(v.tiers || [])].sort() })])))
function load(map, setInitial = true) {
  for (const k of Object.keys(work)) delete work[k]
  for (const [k, v] of Object.entries(map || {})) work[k] = v.disabled ? { disabled: true } : JSON.parse(JSON.stringify(v))
  if (setInitial) initial = JSON.stringify(sorted(work))
}

async function init() {
  loading.value = true
  error.value = ''
  try {
    if (isCustomer.value) {
      load(props.customer?.scoringRates || {})
    } else {
      const { rates } = await api.get('/me/scoring-settings')
      load(rates && Object.keys(rates).length ? rates : DEFAULT_RATES)
    }
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tải được cấu hình'
  } finally {
    loading.value = false
    buildRows()
  }
}
onMounted(init)
watch(() => props.customer?.id, init)
watch(() => props.accountRates, () => !loading.value && buildRows())

// ---- rows of the active region ---------------------------------------------------------------------------------------
const rows = reactive([]) // { type, kind, label, symbols, price, payout, tiers, digits, name, off, extra }

// What a row follows when it has no region-only value of its own.
function inheritedRow(type) {
  const r = region.value
  if (!isCustomer.value) {
    const v = work[type]
    return v && !v.disabled ? toTableRow(type, v) : null
  }
  const own = work[type]
  if (own && !own.disabled) return toTableRow(type, own)
  const b = base.value[regionKey(type, r)] ?? base.value[type]
  return b ? toTableRow(type, b) : null
}
// The row as shown: the region's own value, else what it inherits, else the built-in default of a standard kind.
function shownRow(type) {
  const regional = work[regionKey(type, region.value)]
  if (regional && !regional.disabled) return toTableRow(type, regional)
  return inheritedRow(type) ?? (TABLE_KIND_KEYS.includes(type) ? defaultRow(type, region.value) : null)
}

const extraTypes = computed(() => {
  const keys = new Set(typesIn(work, region.value))
  if (isCustomer.value) for (const k of typesIn(base.value, region.value)) keys.add(k)
  return [...keys].filter((k) => !TABLE_KIND_KEYS.includes(k))
})

// A standard row removed from the table: by the account (default scope), or by the account for every customer.
const removed = (kind) => !!(work[regionKey(kind, region.value)]?.disabled && !isCustomer.value) || !!base.value[regionKey(kind, region.value)]?.disabled
// The "lấy số" of a row as edited: prizes, end of the number (đầu / cuối), digits, and the lô of each prize as text ("1,2").
const srcState = (src) => ({ srcTiers: [...src.tiers], srcPos: src.position, srcDigits: src.digits, srcPick: (src.pick || []).join(',') })
const srcOf = (r) => normalizeSource({ tiers: r.srcTiers, position: r.srcPos, digits: r.srcDigits, pick: String(r.srcPick || '').split(/[,;\s]+/).filter(Boolean) })
const kindOf = (r) => (r.extra ? 'custom' : r.type)
// Different from what the kind reads by default (so only then it is stored).
const srcChanged = (r) => !r.extra && !sameSource(srcOf(r), defaultSource(r.type, region.value))
const srcCaption = (r) => (!r.extra && !srcChanged(r) ? kindSource(r.type, region.value) : describeSource(srcOf(r), region.value))
const fields = (r) => sourceFields(kindOf(r))
function toggleTier(r, t) {
  const i = r.srcTiers.indexOf(t)
  if (i === -1) r.srcTiers.push(t)
  else r.srcTiers.splice(i, 1)
}
function resetSrc(r) {
  Object.assign(r, srcState(r.extra ? { tiers: ['dacBiet'], position: 'last', digits: 2 } : defaultSource(r.type, region.value)))
}
function buildRows() {
  rows.splice(0)
  const std = TABLE_KINDS.filter((k) => !removed(k.kind)).map((k) => ({ type: k.kind, group: k.group, label: k.label, symbols: k.symbols, editable: !!k.editable, extra: false }))
  const extra = extraTypes.value.map((t) => {
    const cfg = toTableRow(t, work[regionKey(t, region.value)] ?? work[t] ?? base.value[regionKey(t, region.value)] ?? base.value[t])
    return { type: t, label: cfg?.name || betTypeLabel(t), symbols: t, group: GROUP_IDS.includes(cfg?.group) ? cfg.group : 'other', extra: true }
  })
  for (const meta of [...std, ...extra]) {
    const cfg = shownRow(meta.type) || defaultRow('lo', region.value)
    const offHere = isCustomer.value && (work[meta.type]?.disabled || work[regionKey(meta.type, region.value)]?.disabled)
    rows.push({
      ...meta,
      kind: cfg.kind,
      price: String(cfg.price),
      payout: String(cfg.payout),
      tiers: [...(cfg.tiers || ['dacBiet'])],
      digits: cfg.digits || 2,
      name: cfg.name || meta.label,
      ...srcState(effectiveSource(cfg, cfg.kind, region.value)),
      srcOpen: false,
      symbolsInput: meta.editable ? symbolsText(cfg.symbols?.length ? cfg.symbols : defaultSymbols(meta.type)) : '',
      off: !!offHere,
    })
  }
}

// The ký hiệu a row stores: only when the customer changed them from the built-in spellings.
function ownSymbols(r) {
  if (!r.editable) return undefined
  const list = parseSymbols(r.symbolsInput)
  return list.join(',') === defaultSymbols(r.type).join(',') ? undefined : list
}
const symbolText = (r) => (r.editable ? symbolsText(parseSymbols(r.symbolsInput).length ? parseSymbols(r.symbolsInput) : defaultSymbols(r.type)) : r.symbols)

// The table is shown by group: each group is one kiểu đánh, its rows are the cách đánh inside it.
const GROUPS = [...TABLE_GROUPS, { id: 'other', label: 'Kiểu đánh khác' }]
const GROUP_IDS = GROUPS.map((g) => g.id)
// While editing, every group is shown (even an empty one) so a cách đánh can be added to it.
const groups = computed(() => GROUPS.map((g) => ({ ...g, rows: rows.filter((r) => r.group === g.id) })).filter((g) => g.rows.length || editing.value))
const colCount = computed(() => (isCustomer.value ? 6 : 5))

const ALL_PRIZES = ['dacBiet', 'giaiNhat', 'giaiNhi', 'giaiBa', 'giaiTu', 'giaiNam', 'giaiSau', 'giaiBay']
const tiersOfScope = (scope) => (scope === 'all' ? [...ALL_PRIZES] : ['dacBiet'])

const cfgOf = (r) =>
  makeRow({
    kind: r.extra ? 'custom' : r.type,
    price: Number(r.price),
    payout: Number(r.payout),
    source: r.extra || srcChanged(r) ? srcOf(r) : undefined,
    name: r.extra && r.name && r.name !== betTypeLabel(r.type) ? r.name : undefined,
    group: r.extra && r.group !== 'other' ? r.group : undefined,
    symbols: ownSymbols(r),
  })
// Where a row's value is written when it has nothing to inherit from: standard kinds and types that exist in every
// region go to the shared key; a type made for this region only keeps its region key.
const writeKey = (r) => regionKey(r.type, region.value)

// Writes the rows of the active region back into `work`: a row that differs from what it follows becomes a region-only
// value, one that equals it drops its region-only value.
function commitInto(target) {
  for (const r of rows) {
    if (r.off) continue
    const key = regionKey(r.type, region.value)
    const cfg = cfgOf(r)
    const baseCfg = inheritedRow(r.type)
    if (!baseCfg) target[writeKey(r)] = cfg
    else if (sameConfig(cfg, baseCfg, r.type)) delete target[key]
    else target[key] = cfg
  }
}
const commitRows = () => commitInto(work)

function switchRegion(id) {
  const problem = validate()
  if (problem) {
    error.value = problem
    return
  }
  error.value = ''
  commitRows()
  region.value = id
  buildRows()
}

const differs = (r) => {
  const baseCfg = inheritedRow(r.type)
  return !!baseCfg && !sameConfig(cfgOf(r), baseCfg, r.type)
}
const hasOwn = (r) => !r.off && (!!work[regionKey(r.type, region.value)] || differs(r))
const tag = (r) => {
  if (r.off) return 'Không dùng'
  if (isCustomer.value) return hasOwn(r) ? 'Riêng' : 'Mặc định'
  return ''
}
// A row whose giá trúng is still 0 was not given by the doc (xiên, trượt, bao lô 3-4 số, tài/xỉu...): shown in red until filled.
const notSet = (r) => !r.off && !r.extra && !(Number(r.payout) > 0)

function resetRow(r) {
  delete work[regionKey(r.type, region.value)]
  buildRows()
}
function toggleOff(r) {
  commitRows()
  if (r.off) {
    if (work[r.type]?.disabled) delete work[r.type]
    delete work[regionKey(r.type, region.value)]
  } else {
    work[regionKey(r.type, region.value)] = { disabled: true }
  }
  buildRows()
}
async function removeRow(r) {
  const ok = await showConfirm({
    title: 'Xoá cách đánh',
    message: `Xoá "${r.label}" khỏi bảng ${REGION_NAMES[region.value]}${isCustomer.value ? ` của ${props.customer.name}` : ''}? Số liệu đã nhập với cách này vẫn được giữ và tính theo cấu hình mặc định. Bạn có thể thêm lại bằng "+ Thêm". Bấm Lưu để áp dụng.`,
    confirmText: 'Xoá',
    danger: true,
  })
  if (!ok) return
  commitRows()
  if (!r.extra) {
    // A standard row is not deleted but marked removed ({ disabled: true }) so it does not come back as a default.
    work[regionKey(r.type, region.value)] = { disabled: true }
  } else {
    for (const k of Object.keys(work)) if (baseKey(k) === r.type && (k === r.type || k === regionKey(r.type, region.value))) delete work[k]
  }
  buildRows()
}

// ---- "Kiểu đánh khác": a name, a symbol, what it is compared with ----------------------------------------------------
const addForm = reactive({ open: false, group: 'other', pick: 'new', name: '', symbol: '', tiers: 'special', digits: 2, price: '12600', payout: '70000', error: '' })
// Standard rows of a group that were removed and can be put back.
const restorable = (group) => TABLE_KINDS.filter((k) => k.group === group && removed(k.kind) && !(isCustomer.value && base.value[regionKey(k.kind, region.value)]?.disabled))
function openAdd(group) {
  const back = restorable(group)
  Object.assign(addForm, { open: true, group, pick: back.length ? back[0].kind : 'new', name: '', symbol: '', tiers: 'special', digits: 2, price: '12600', payout: '70000', error: '' })
}
function addRow() {
  addForm.error = ''
  commitRows()
  if (addForm.pick !== 'new') {
    delete work[regionKey(addForm.pick, region.value)] // back to what it follows / the built-in default
    addForm.open = false
    buildRows()
    return
  }
  const symbol = addForm.symbol.trim().toLowerCase()
  if (!/^[a-z0-9]{1,12}$/.test(symbol)) return void (addForm.error = 'Ký hiệu chỉ gồm chữ không dấu hoặc số (tối đa 12 ký tự)')
  if (TABLE_KIND_KEYS.includes(symbol) || rows.some((r) => r.type === symbol)) return void (addForm.error = 'Ký hiệu này đã có')
  if (!(Number(addForm.price) > 0) || !(Number(addForm.payout) >= 0)) return void (addForm.error = 'Giá tiền phải lớn hơn 0, giá trúng không âm')
  work[regionKey(symbol, region.value)] = makeRow({
    kind: 'custom',
    price: Number(addForm.price),
    payout: Number(addForm.payout),
    source: { tiers: tiersOfScope(addForm.tiers), position: 'last', digits: Number(addForm.digits) || 2 },
    name: addForm.name.trim() || undefined,
    group: addForm.group,
  })
  addForm.open = false
  buildRows()
}

// ---- save --------------------------------------------------------------------------------------------------------------
function validate() {
  for (const r of rows) {
    if (r.off) continue
    const price = Number(r.price)
    const payout = Number(r.payout)
    if (!Number.isFinite(price) || price <= 0) return `Giá tiền/1 điểm của "${r.label}" không hợp lệ`
    if (!Number.isFinite(payout) || payout < 0) return `Giá trúng/1 điểm của "${r.label}" không hợp lệ`
  }
  for (const r of rows) {
    if (r.off) continue
    if (r.extra || srcChanged(r)) {
      if (!r.srcTiers.length) return `"${r.label}": chọn ít nhất một giải để lấy số`
      if (!(Number(r.srcDigits) >= 1 && Number(r.srcDigits) <= 6)) return `"${r.label}": số chữ số từ 1 đến 6`
    }
  }
  const seen = new Map()
  for (const r of rows) {
    if (!r.editable || r.off) continue
    const list = parseSymbols(r.symbolsInput)
    for (const sym of list) {
      if (!/^[\p{L}×]{1,12}$/u.test(sym)) return `Ký hiệu "${sym}" của "${r.label}" chỉ được gồm chữ cái (tối đa 12 ký tự)`
      const k = sym.normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/đ/gi, 'd').toLowerCase()
      if (seen.has(k) && seen.get(k) !== r.type) return `Ký hiệu "${sym}" đang dùng cho cả "${rows.find((x) => x.type === seen.get(k))?.label}" và "${r.label}"`
      seen.set(k, r.type)
    }
  }
  return ''
}

// Default scope: every standard kind of every region gets a value (a legacy account only had Đề / Lô), so an entry of
// any kind is always scored with a real row.
function fillMissing(target) {
  for (const r of REGION_IDS) for (const kind of TABLE_KIND_KEYS) if (!target[regionKey(kind, r)] && !target[kind]) target[regionKey(kind, r)] = defaultRow(kind, r)
}

const dirty = computed(() => {
  const copy = JSON.parse(JSON.stringify(work))
  commitInto(copy)
  return JSON.stringify(sorted(copy)) !== initial
})

async function save() {
  error.value = ''
  notice.value = ''
  const problem = validate()
  if (problem) {
    error.value = problem
    return
  }
  commitRows()
  if (!isCustomer.value) fillMissing(work)
  const map = JSON.parse(JSON.stringify(work))
  if (!isCustomer.value && !Object.keys(map).length) {
    error.value = 'Cần ít nhất một kiểu đánh'
    return
  }
  saving.value = true
  try {
    if (isCustomer.value) {
      const res = await api.patch(`/me/customers/${props.customer.id}`, { scoringRates: Object.keys(map).length ? map : null })
      load(res.scoringRates || {})
      notice.value = res.scoringRates ? `Đã lưu cấu hình riêng cho ${props.customer.name}` : `${props.customer.name} đang dùng cấu hình mặc định`
      emit('saved', res.scoringRates || null)
    } else {
      const res = await api.put('/me/scoring-settings', { rates: map })
      load(res.rates)
      notice.value = 'Đã lưu cấu hình mặc định'
      emit('saved', res.rates)
    }
    buildRows()
    editing.value = false
  } catch (err) {
    error.value = err instanceof ApiError ? (err.status === 0 ? 'Mất kết nối tới máy chủ, chưa lưu được.' : err.message) : 'Không lưu được cấu hình'
  } finally {
    saving.value = false
  }
}

function cancelEdit() {
  editing.value = false
  error.value = ''
  notice.value = ''
  init()
}

function resetAll() {
  if (isCustomer.value) load({}, false)
  else load(DEFAULT_RATES, false)
  buildRows()
}

const overrideCount = computed(() => Object.keys(work).filter((k) => work[k]?.disabled || k.includes('@')).length)
const regionHasOverride = (id) => isCustomer.value && Object.keys(work).some((k) => k.endsWith(`@${id}`))
const regions = REGION_IDS
</script>

<template>
  <div class="sce">
    <div v-if="loading" class="sce-note">Đang tải...</div>
    <template v-else>
      <p class="sce-hint">
        <template v-if="isCustomer">Tính điểm cho <strong>{{ customer.name }}</strong>: đánh kiểu gì, ở đài nào, giá tiền và giá trúng bao nhiêu. Dòng nào không đổi sẽ theo cấu hình mặc định.</template>
        <template v-else>Cấu hình mặc định dùng cho mọi khách chưa có cấu hình riêng: mỗi miền một bảng giá.</template>
        Tiền xác = điểm × giá tiền; tiền trúng = số lần trúng × điểm × giá trúng.
      </p>

      <div v-if="error" class="alert alert-error">{{ error }}</div>
      <div v-if="notice" class="alert alert-success">{{ notice }}</div>

      <div class="sce-bar">
        <div class="sce-tabs" role="tablist" aria-label="Miền">
          <button
            v-for="id in regions"
            :key="id"
            type="button"
            role="tab"
            class="sce-tab"
            :class="{ on: region === id }"
            :aria-selected="region === id"
            @click="switchRegion(id)"
          >
            {{ REGION_NAMES[id] }}<span v-if="regionHasOverride(id)" class="sce-dot" title="Có cấu hình riêng cho miền này"></span>
          </button>
        </div>
        <button v-if="!editing" type="button" class="btn btn-secondary btn-sm" @click="editing = true; notice = ''">Sửa</button>
        <span v-else class="sce-muted">Đang sửa: thêm, sửa giá, xoá từng cách đánh rồi bấm Lưu</span>
      </div>

      <div class="sce-table-wrap">
        <table class="sce-table">
          <thead>
            <tr>
              <th v-if="isCustomer" class="c-use">Dùng</th>
              <th class="c-kind">Cách đánh</th>
              <th class="c-sym">Ký hiệu</th>
              <th class="c-num">Giá tiền / 1 điểm</th>
              <th class="c-num">Giá trúng / 1 điểm</th>
              <th class="c-act"></th>
            </tr>
          </thead>
          <tbody v-for="g in groups" :key="g.id">
            <tr class="grp">
              <th :colspan="colCount" scope="colgroup">
                <span class="grp-name">{{ g.label }}<span class="sce-muted"> · {{ g.rows.length }} cách đánh</span></span>
                <button v-if="editing" type="button" class="btn btn-ghost btn-sm grp-add" @click="openAdd(g.id)">+ Thêm cách đánh</button>
              </th>
            </tr>
            <tr v-if="editing && addForm.open && addForm.group === g.id" class="grp-form">
              <td :colspan="colCount">
                <form class="sce-add" @submit.prevent="addRow">
                  <strong>Thêm vào "{{ g.label }}" ({{ REGION_NAMES[region] }})</strong>
                  <label v-if="restorable(g.id).length" class="sce-pick">Chọn
                    <select v-model="addForm.pick">
                      <option v-for="k in restorable(g.id)" :key="k.kind" :value="k.kind">Khôi phục: {{ k.label }}</option>
                      <option value="new">Cách đánh mới (tự đặt tên, ký hiệu)</option>
                    </select>
                  </label>
                  <div v-if="addForm.pick === 'new'" class="sce-add-grid">
                    <label>Tên<input v-model="addForm.name" type="text" maxlength="30" placeholder="Ví dụ: Đề 3 số" /></label>
                    <label>Ký hiệu<input v-model="addForm.symbol" type="text" maxlength="12" placeholder="Ví dụ: d3" /></label>
                    <label>So với
                      <select v-model="addForm.tiers">
                        <option value="special">Giải đặc biệt</option>
                        <option value="all">Tất cả các giải</option>
                      </select>
                    </label>
                    <label>Số cuối
                      <select v-model.number="addForm.digits">
                        <option :value="2">2 số</option>
                        <option :value="3">3 số</option>
                        <option :value="4">4 số</option>
                      </select>
                    </label>
                    <label>Giá tiền / 1 điểm<input v-model="addForm.price" type="number" min="0" step="any" /></label>
                    <label>Giá trúng / 1 điểm<input v-model="addForm.payout" type="number" min="0" step="any" /></label>
                  </div>
                  <p v-if="addForm.error" class="alert alert-error">{{ addForm.error }}</p>
                  <div class="sce-add-actions">
                    <button type="button" class="btn btn-ghost btn-sm" @click="addForm.open = false">Huỷ</button>
                    <button type="submit" class="btn btn-primary btn-sm">{{ addForm.pick === 'new' ? 'Thêm' : 'Khôi phục' }}</button>
                  </div>
                </form>
              </td>
            </tr>
            <template v-for="r in g.rows" :key="r.type">
            <tr :class="{ off: r.off, own: isCustomer && hasOwn(r) }">
              <td v-if="isCustomer" class="c-use" data-label="Dùng">
                <input v-if="editing" type="checkbox" :checked="!r.off" :aria-label="`Khách này đánh ${r.label}`" @change="toggleOff(r)" />
                <span v-else>{{ r.off ? '–' : '✓' }}</span>
              </td>
              <td class="c-kind" data-label="Kiểu đánh">
                <input v-if="editing && r.extra" v-model="r.name" type="text" class="name-input" maxlength="30" :aria-label="`Tên cách đánh ${r.type}`" />
                <strong v-else>{{ r.label }}</strong>
                <span v-if="tag(r)" class="sce-tag" :class="{ own: hasOwn(r) }">{{ tag(r) }}</span>
                <small class="sce-src">Lấy số: {{ srcCaption(r) }}<button v-if="editing && !r.off" type="button" class="link-btn" @click="r.srcOpen = !r.srcOpen">{{ r.srcOpen ? 'Đóng' : 'Chỉnh lấy số' }}</button></small>
              </td>
              <td class="c-sym" data-label="Ký hiệu">
                <input v-if="editing && r.editable" v-model="r.symbolsInput" type="text" class="sym-input" :aria-label="`Ký hiệu ${r.label}`" placeholder="Cách nhau bằng dấu phẩy" />
                <span v-else class="sce-muted">{{ symbolText(r) }}</span>
              </td>
              <td class="c-num" data-label="Giá tiền / 1 điểm">
                <input v-if="editing && !r.off" v-model="r.price" type="number" min="0" step="any" inputmode="decimal" :aria-label="`Giá tiền 1 điểm ${r.label}`" />
                <span v-else-if="!r.off" class="val">{{ fmt(r.price) }}</span>
                <span v-else class="sce-muted">-</span>
              </td>
              <td class="c-num" data-label="Giá trúng / 1 điểm">
                <input v-if="editing && !r.off" v-model="r.payout" type="number" min="0" step="any" inputmode="decimal" :class="{ warn: notSet(r) }" :aria-label="`Giá trúng 1 điểm ${r.label}`" />
                <span v-else-if="!r.off" class="val" :class="{ warn: notSet(r) }">{{ fmt(r.payout) }}</span>
                <span v-else class="sce-muted">-</span>
                <small v-if="notSet(r)" class="sce-warn">Chưa nhập</small>
              </td>
              <td class="c-act">
                <template v-if="editing">
                  <button v-if="hasOwn(r) && isCustomer" type="button" class="btn btn-ghost btn-sm" @click="resetRow(r)">Theo chung</button>
                  <button v-if="r.extra || !isCustomer" type="button" class="btn btn-ghost btn-sm sce-del" @click="removeRow(r)">Xoá</button>
                </template>
              </td>
            </tr>
            <tr v-if="editing && r.srcOpen && !r.off" class="src-row">
              <td :colspan="colCount">
                <div class="src-panel">
                  <div v-if="fields(r).tiers" class="src-field">
                    <strong>Giải (dãy giải lấy số)</strong>
                    <div class="src-tiers">
                      <label v-for="p in prizeInfo(region)" :key="p.tier" class="src-tier">
                        <input type="checkbox" :checked="r.srcTiers.includes(p.tier)" @change="toggleTier(r, p.tier)" />
                        {{ p.label }} <span class="sce-muted">({{ p.count }} lô × {{ p.digits }} số)</span>
                      </label>
                    </div>
                  </div>
                  <div class="src-line">
                    <label v-if="fields(r).position">Vị trí
                      <select v-model="r.srcPos"><option value="last">Cuối (đuôi)</option><option value="first">Đầu</option></select>
                    </label>
                    <label v-if="fields(r).digits">Bao nhiêu số
                      <select v-model.number="r.srcDigits"><option v-for="n in 6" :key="n" :value="n">{{ n }} số</option></select>
                    </label>
                    <label v-if="fields(r).pick">Lô thứ (để trống = mọi lô của giải)
                      <input v-model="r.srcPick" type="text" placeholder="Ví dụ: 1, 2" />
                    </label>
                    <button type="button" class="btn btn-ghost btn-sm" @click="resetSrc(r)">Về mặc định</button>
                  </div>
                  <small class="sce-muted">Đang lấy: {{ describeSource(srcOf(r), region) }}</small>
                </div>
              </td>
            </tr>
            </template>
          </tbody>
        </table>
      </div>

      <div class="sce-foot">
        <span class="sce-muted">{{ !isCustomer ? '' : overrideCount ? `${overrideCount} mục riêng` : 'Đang dùng cấu hình mặc định' }}</span>
        <template v-if="editing">
          <button type="button" class="btn btn-ghost btn-sm" :disabled="saving" @click="resetAll">{{ isCustomer ? 'Bỏ cấu hình riêng' : 'Đặt lại mặc định' }}</button>
          <button type="button" class="btn btn-ghost" :disabled="saving" @click="cancelEdit">Huỷ</button>
          <button type="button" class="btn btn-primary" :disabled="saving || !dirty" @click="save">{{ saving ? 'Đang lưu...' : isCustomer ? 'Lưu cấu hình khách này' : 'Lưu cấu hình' }}</button>
        </template>
      </div>
    </template>
  </div>
</template>

<style scoped>
.sce {
  font-size: 14.5px;
}
.sce-hint {
  margin: 0 0 12px;
  font-size: 14px;
  color: var(--muted);
}
.sce-note {
  color: var(--muted);
}
.sce-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 12px;
}
.sce-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.sce-tab {
  min-height: 38px;
  min-width: 110px;
  padding: 0 16px;
  font: inherit;
  font-size: 14.5px;
  font-weight: 600;
  color: var(--muted);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 999px;
  cursor: pointer;
}
.sce-tab.on {
  color: #fff;
  background: var(--primary);
  border-color: var(--primary);
}
.sce-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  margin-left: 7px;
  vertical-align: middle;
  background: currentColor;
  border-radius: 50%;
  opacity: 0.8;
}
.sce-table-wrap {
  /* No fixed height: the table is as long as its rows and the page (or the dialog) scrolls. */
  overflow-x: auto;
  border: 1px solid var(--border);
  border-radius: 12px;
}
.sce-table {
  width: 100%;
  border-collapse: collapse;
}
.sce-table th {
  padding: 8px 10px;
  font-size: 13px;
  font-weight: 600;
  text-align: left;
  color: var(--muted);
  background: var(--surface);
  border-bottom: 1px solid var(--border);
}
.sce-table td {
  padding: 7px 10px;
  vertical-align: middle;
  border-bottom: 1px solid var(--border);
}
.sce-table tbody:last-child tr:last-child td {
  border-bottom: 0;
}
.sce-table tr.grp th {
  position: static;
  padding: 7px 10px;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-primary);
  background: color-mix(in srgb, var(--primary) 8%, var(--surface));
  border-bottom: 1px solid var(--border);
}
.c-kind strong {
  font-weight: 600;
  padding-left: 10px;
}
.sce-table tr.own td {
  background: color-mix(in srgb, var(--primary) 5%, transparent);
}
.sce-table tr.off {
  opacity: 0.6;
}
.c-use {
  width: 52px;
  text-align: center;
}
.c-kind {
  min-width: 130px;
}
.c-sym {
  min-width: 150px;
  font-size: 13px;
}
.c-num {
  width: 170px;
}
.c-act {
  width: 150px;
  text-align: right;
  white-space: nowrap;
}
.c-num input {
  width: 100%;
  height: 38px;
  padding: 0 10px;
  font: inherit;
  font-size: 15px;
  text-align: right;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.sym-input {
  width: 100%;
  height: 38px;
  padding: 0 10px;
  font: inherit;
  font-size: 14px;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.val {
  display: block;
  font-size: 15px;
  font-weight: 600;
  text-align: right;
}
.val.warn {
  color: var(--danger-text);
}
.c-num input.warn {
  border-color: var(--danger-text);
}
.sce-warn {
  display: block;
  font-size: 12px;
  color: var(--danger-text);
}
.c-use input {
  width: 18px;
  height: 18px;
}
.sce-muted {
  color: var(--muted);
}
.sce-tag {
  margin-left: 8px;
  padding: 1px 8px;
  font-size: 12px;
  color: var(--muted);
  border: 1px solid var(--border);
  border-radius: 999px;
}
.sce-tag.own {
  color: var(--primary);
  border-color: var(--primary);
}
.sce-src {
  display: block;
  margin: 2px 0 0 10px;
  font-size: 12px;
  line-height: 1.35;
  color: var(--muted);
}
.link-btn {
  margin-left: 8px;
  padding: 0;
  font: inherit;
  font-size: 12px;
  color: var(--primary);
  background: none;
  border: 0;
  text-decoration: underline;
  cursor: pointer;
}
.src-row td {
  padding: 0 10px 10px;
  background: color-mix(in srgb, var(--primary) 4%, var(--card));
}
.src-panel {
  display: grid;
  gap: 10px;
  padding: 10px 12px;
  border: 1px dashed var(--primary);
  border-radius: 12px;
}
.src-field strong {
  font-size: 13px;
}
.src-tiers {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(210px, 1fr));
  gap: 4px 12px;
  margin-top: 4px;
}
.src-tier {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13.5px;
}
.src-line {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: 8px 14px;
}
.src-line label {
  display: grid;
  gap: 4px;
  font-size: 13px;
  color: var(--muted);
}
.src-line select,
.src-line input {
  height: 34px;
  padding: 0 8px;
  font: inherit;
  font-size: 14px;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 8px;
}
.grp-add {
  float: right;
  min-height: 30px;
  padding: 0 10px;
  font-size: 13px;
}
.sce-table tr.grp th .grp-name {
  line-height: 30px;
}
.grp-form td {
  padding: 8px 10px;
  background: var(--card);
}
.sce-pick {
  display: grid;
  gap: 4px;
  font-size: 13px;
  color: var(--muted);
}
.sce-pick select,
.custom-opts select {
  height: 34px;
  font: inherit;
  font-size: 13.5px;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 8px;
}
.name-input {
  width: 100%;
  height: 36px;
  padding: 0 10px;
  font: inherit;
  font-size: 14.5px;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.sce-del {
  color: var(--danger-text);
}
.sce-add {
  display: grid;
  gap: 10px;
  margin-top: 12px;
  padding: 12px 14px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
}
.sce-add-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 8px 12px;
}
.sce-add-grid label {
  display: grid;
  gap: 4px;
  font-size: 13px;
  color: var(--muted);
}
.sce-add-grid input,
.sce-add-grid select {
  height: 38px;
  padding: 0 8px;
  font: inherit;
  font-size: 14.5px;
  color: var(--text-primary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.sce-add-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
.sce-foot {
  position: sticky; /* the table is long: Lưu / Huỷ stay in reach at the bottom of the screen */
  bottom: 0;
  z-index: 2;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: 8px 12px;
  margin-top: 12px;
  padding: 10px 0;
  background: var(--card);
}
.sce-foot .sce-muted {
  margin-right: auto;
}

@media (max-width: 720px) {
  .sce-table thead {
    display: none;
  }
  .sce-table tr.grp {
    padding: 0;
  }
  .sce-table tr.grp th {
    display: block;
  }
  .sce-table,
  .sce-table tbody,
  .sce-table tr,
  .sce-table td {
    display: block;
  }
  .sce-table tr {
    padding: 8px 10px;
    border-bottom: 1px solid var(--border);
  }
  .sce-table td {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 4px 0;
    border: 0;
    text-align: left;
  }
  .sce-table td::before {
    content: attr(data-label);
    font-size: 12.5px;
    color: var(--muted);
  }
  .c-kind::before,
  .c-act::before {
    content: none !important;
  }
  .c-num,
  .c-use,
  .c-sym,
  .c-act {
    width: auto;
  }
  .c-num input {
    width: 150px;
  }
  .sce-add-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}
</style>
