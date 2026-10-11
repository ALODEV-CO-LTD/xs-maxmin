<!--
  Khách hàng: this account's own customer roster (GET/POST/DELETE
  /me/customers - EntriesView's "Tên khách hàng" picker reads the same
  list, so a customer must be added here first rather than typed freely on
  every entry) merged with a per-customer summary aggregated from
  data_entries: entry count, last date, totals for "Điểm vào" (score)/
  "Điểm ra" (result), same parsing convention as EntriesView's Thống kê
  block. The form at the top adds a new roster entry (409 on a duplicate
  name, shown inline). A roster customer with no entries yet still shows
  up (with 0/0/0) and gets a "Xoá khỏi danh sách" button in the Thao tác
  column; a name that appears in old entries but was never added to the
  roster (e.g. typed before this existed) still shows too, just with a
  "-" in that column since there's no roster row to delete. Deleting only
  removes the roster row - matching data_entries rows are untouched and
  keep showing in history.

  API: GET/POST /me/customers, DELETE /me/customers/:id, GET /me/entries.
-->
<script setup>
import { showConfirm } from '../confirm'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api, ApiError } from '../api'
import { cachedGet, loadAllEntries } from '../offline'
import { fold } from '../messageParser'
import AppIcon from '../components/AppIcon.vue'
import MaskBar from '../components/MaskBar.vue'
import ModalDialog from '../components/ModalDialog.vue'
import ScoringConfigEditor from '../components/ScoringConfigEditor.vue'
import ScoringSettingsView from './ScoringSettingsView.vue'
import { DEFAULT_RATES } from '../scoringConfig'
import { allStationOptions, loadStations } from '../lotteryStations'
import AppSelect from '../components/AppSelect.vue'
import MaskedValue from '../components/MaskedValue.vue'

const route = useRoute()
const router = useRouter()
// Opened via "+ Thêm khách hàng mới" on Nhập số: after adding a customer, go back there.
const fromEntries = route.query.from === 'entries'
const addInput = ref(null)
// Two separate screens: the list of customers, or the form that creates a new one.
const view = ref(route.query.from === 'entries' ? 'new' : 'list')
watch(view, (v) => v === 'new' && nextTick(() => addInput.value?.focus()))

const entries = ref([])
const loading = ref(true)
const loadError = ref('')
const fromCache = ref(false) // showing the copy saved on this device (offline)
const OFFLINE_WRITE = 'Đang offline: thêm/xoá khách hàng cần có mạng, vui lòng thử lại khi kết nối lại.'
const search = ref('')
const expanded = ref(null)

const roster = ref([]) // [{id, name, createdAt}] from /me/customers
const newCustomerName = ref('')
const newCustomerPhone = ref('')
const addingCustomer = ref(false)
const addError = ref('')
const deletingId = ref(null)

async function loadRoster() {
  try {
    // cachedGet: last saved copy when offline
    const { customers: list } = await cachedGet('/me/customers')
    roster.value = list
  } catch (err) {
    // Non-fatal - the page still works from entries alone, just without
    // "add new customer" until this loads.
  }
}

// ---- Cấu hình tính điểm: riêng từng khách (nút Cấu hình tính điểm ở từng dòng) + mặc định chung (nút trên đầu) ----
const accountRates = ref({ ...DEFAULT_RATES })
async function loadAccountRates() {
  try {
    const { rates } = await cachedGet('/me/scoring-settings')
    if (rates && Object.keys(rates).length) accountRates.value = rates
  } catch (_) {
    /* keep the built-in fallback */
  }
}
const defaultConfigOpen = ref(route.query.config === 'default')
const rosterRow = computed(() => roster.value.find((r) => r.id === detail.value?.rosterId) || null)
// The lottery this customer plays by default: what Nhập số starts from for them.
const stationSaving = ref(false)
const stationMsg = ref('')
async function saveDefaultStation(code) {
  const row = rosterRow.value
  if (!row) return
  stationSaving.value = true
  stationMsg.value = ''
  try {
    const res = await api.patch(`/me/customers/${row.id}`, { defaultStation: code })
    row.defaultStation = res.defaultStation
    stationMsg.value = 'Đã lưu đài mặc định'
  } catch (err) {
    stationMsg.value = err instanceof ApiError ? err.message : 'Không lưu được đài'
  } finally {
    stationSaving.value = false
  }
}
onMounted(loadStations)
function onCustomerConfigSaved(map) {
  const row = rosterRow.value
  if (row) row.scoringRates = map
}

async function addCustomer() {
  const name = newCustomerName.value.trim()
  if (!name) return
  addError.value = ''
  addingCustomer.value = true
  try {
    const created = await api.post('/me/customers', { name, phone: newCustomerPhone.value.trim() })
    roster.value.push(created)
    roster.value.sort((a, b) => a.name.localeCompare(b.name, 'vi'))
    view.value = 'list'
    newCustomerName.value = ''
    newCustomerPhone.value = ''
    if (fromEntries) {
      router.push({ name: 'entries', query: { customer: created.name } })
      return
    }
  } catch (err) {
    addError.value = err instanceof ApiError ? (err.status === 0 ? OFFLINE_WRITE : err.message) : 'Không thêm được khách hàng'
  } finally {
    addingCustomer.value = false
  }
}

async function removeCustomer(id, name) {
  if (!(await showConfirm({
    title: 'Xoá khách hàng',
    message: `Xoá "${name}" khỏi danh sách khách hàng? Số liệu đã nhập của khách này vẫn được giữ nguyên.`,
    confirmText: 'Xoá',
    danger: true,
  }))) return
  deletingId.value = id
  try {
    await api.del(`/me/customers/${id}`)
    roster.value = roster.value.filter((c) => c.id !== id)
  } catch (err) {
    addError.value = err instanceof ApiError ? (err.status === 0 ? OFFLINE_WRITE : err.message) : 'Không xoá được'
  } finally {
    deletingId.value = null
  }
}

function toNumber(str) {
  if (!str) return 0
  const cleaned = String(str).replace(/[^\d.-]/g, '')
  const n = parseFloat(cleaned)
  return Number.isFinite(n) ? n : 0
}

function formatNumber(n) {
  return new Intl.NumberFormat('vi-VN').format(n)
}

function formatDate(iso) {
  if (!iso) return '-'
  return new Date(iso).toLocaleDateString('vi-VN')
}

async function load() {
  loading.value = true
  loadError.value = ''
  try {
    // every page of the history (counts/totals must not miss old records);
    // the saved copy when offline
    const list = await loadAllEntries()
    entries.value = list.entries
    fromCache.value = list.fromCache
  } catch (err) {
    loadError.value = err.message || 'Không tải được số liệu'
  } finally {
    loading.value = false
  }
}

onMounted(load)
function onKeydown(e) {
  if (e.key === 'Escape') expanded.value = null
}
onMounted(() => {
  window.addEventListener('keydown', onKeydown)
  window.addEventListener('popstate', onPopState)
})
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown)
  window.removeEventListener('popstate', onPopState)
})
onMounted(loadRoster)
onMounted(loadAccountRates)
onMounted(() => {
  if (fromEntries) nextTick(() => addInput.value?.focus())
})

const customers = computed(() => {
  const byName = new Map()
  // Seed with the roster first - a customer with zero entries yet still
  // shows up (0/0/0), and carries its roster id so "Xoá khỏi danh sách"
  // has something to delete.
  for (const c of roster.value) {
    byName.set(c.name, {
      name: c.name,
      rosterId: c.id,
      phone: c.phone || '',
      count: 0,
      vao: 0,
      ra: 0,
      lastDate: null,
      entries: [],
    })
  }
  for (const e of entries.value) {
    const name = e.customerName || '(Không tên)'
    if (!byName.has(name)) {
      byName.set(name, { name, rosterId: null, phone: '', count: 0, vao: 0, ra: 0, lastDate: null, entries: [] })
    }
    const c = byName.get(name)
    c.count += 1
    c.vao += toNumber(e.score)
    c.ra += toNumber(e.result)
    c.entries.push(e)
    if (!c.lastDate || e.entryDate > c.lastDate) c.lastDate = e.entryDate
  }
  const list = [...byName.values()].map((c) => ({ ...c, chenhLech: c.vao - c.ra }))
  list.sort((a, b) => {
    if (!a.lastDate && !b.lastDate) return a.name.localeCompare(b.name, 'vi')
    if (!a.lastDate) return -1
    if (!b.lastDate) return 1
    return a.lastDate < b.lastDate ? 1 : -1
  })
  return list
})

const filteredCustomers = computed(() => {
  const q = fold(search.value.trim()) // accent-insensitive: "do ngoc" finds "Đỗ Ngọc Mai"
  if (!q) return customers.value
  return customers.value.filter((c) => fold(c.name).includes(q))
})

const detailBox = ref(null)
const detail = computed(() => customers.value.find((c) => c.name === expanded.value) || null)
// The detail box owns one history entry while open, so the browser/phone Back
// button closes the box instead of leaving the page. Closing by button/Esc/overlay
// removes that entry again (history.back) so no ping-pong state is left behind.
let detailHistory = false
function onPopState() {
  if (detailHistory) {
    detailHistory = false // the entry was already popped by the browser
    expanded.value = null
  }
}
watch(
  () => !!detail.value,
  (open) => {
    if (open && !detailHistory) {
      history.pushState({ ...history.state, customerDetail: true }, '')
      detailHistory = true
    } else if (!open && detailHistory) {
      detailHistory = false
      history.back()
    }
  },
)
function toggle(name) {
  expanded.value = name
  nextTick(() => detailBox.value?.focus())
}
// "Sửa": edit a customer's phone number in a small dialog.
const editing = ref(null) // the table row being edited
const phoneDraft = ref('')
const phoneMsg = ref('')
const savingPhone = ref(false)
function openEdit(c) {
  editing.value = c
  phoneDraft.value = c.phone || ''
  phoneMsg.value = ''
}
async function savePhone() {
  const c = editing.value
  if (!c?.rosterId) return
  savingPhone.value = true
  phoneMsg.value = ''
  try {
    const res = await api.patch(`/me/customers/${c.rosterId}`, { phone: phoneDraft.value.trim() })
    const row = roster.value.find((x) => x.id === c.rosterId)
    if (row) row.phone = res.phone
    editing.value = null
  } catch (err) {
    phoneMsg.value = err instanceof ApiError ? (err.status === 0 ? OFFLINE_WRITE : err.message) : 'Không lưu được số điện thoại'
  } finally {
    savingPhone.value = false
  }
}
</script>

<template>
  <div class="page">
    <h1 class="page-title">Khách hàng</h1>
    <p class="page-subtitle">Danh sách khách hàng của bạn. Chọn Danh sách để xem và cấu hình khách, hoặc Tạo khách hàng mới để thêm khách; số liệu vào/ra được tổng hợp từ các lượt nhập.</p>

    <div class="view-tabs" role="tablist" aria-label="Khách hàng">
      <button type="button" role="tab" class="view-tab" :class="{ active: view === 'list' }" :aria-selected="view === 'list'" @click="view = 'list'">Danh sách khách hàng</button>
      <button type="button" role="tab" class="view-tab" :class="{ active: view === 'new' }" :aria-selected="view === 'new'" @click="view = 'new'">Tạo khách hàng mới</button>
    </div>

    <div v-show="view === 'new'" class="card add-customer-card">
      <form class="add-customer-form" @submit.prevent="addCustomer">
        <div class="field add-customer-field">
          <div class="input-wrap">
            <input ref="addInput" v-model="newCustomerName" type="text" placeholder="Tên khách hàng mới" :disabled="addingCustomer" />
          </div>
        </div>
        <div class="field add-customer-field">
          <div class="input-wrap">
            <input v-model="newCustomerPhone" type="tel" inputmode="tel" placeholder="Số điện thoại (không bắt buộc)" :disabled="addingCustomer" />
          </div>
        </div>
        <button type="submit" class="btn btn-primary" :disabled="addingCustomer || !newCustomerName.trim()">
          {{ addingCustomer ? 'Đang thêm...' : 'Thêm khách hàng' }}
        </button>
      </form>
      <div v-if="addError" class="alert alert-error add-customer-error">{{ addError }}</div>
    </div>

    <div v-if="fromCache && view === 'list'" class="alert alert-warning">
      Đang offline: hiển thị số liệu đã lưu trên máy. Thêm/xoá khách hàng cần có mạng.
    </div>
    <div v-if="view !== 'list'"></div>
    <div v-else-if="loading" class="card">Đang tải...</div>
    <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <template v-else>
      <MaskBar class="mask-row" />
      <div class="config-row">
        <button type="button" class="btn btn-secondary btn-sm" @click="defaultConfigOpen = true">Cấu hình tính điểm mặc định</button>
      </div>
      <div class="field search-field">
        <div class="input-wrap">
          <AppIcon name="search" class="search-icon" />
          <input v-model="search" type="text" placeholder="Tìm theo tên khách hàng..." />
        </div>
      </div>

      <div v-if="customers.length === 0" class="card">Chưa có khách hàng nào. Bấm "Tạo khách hàng mới" để bắt đầu.</div>
      <div v-else-if="filteredCustomers.length === 0" class="card">Không tìm thấy khách hàng phù hợp.</div>

      <div v-else class="table-wrap">
        <table class="table stack-table">
          <thead>
            <tr>
              <th>STT</th>
              <th>Tên</th>
              <th>SĐT</th>
              <th>Điểm đầu vào</th>
              <th>Điểm đầu ra</th>
              <th>Lợi nhuận</th>
              <th>Thao tác</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="(c, i) in filteredCustomers" :key="c.name">
              <tr class="row-clickable" @click="toggle(c.name)">
                <td data-label="STT">{{ i + 1 }}</td>
                <td data-label="Tên">{{ c.name }}</td>
                <td data-label="SĐT">{{ c.phone || '-' }}</td>
                <td data-label="Điểm đầu vào"><MaskedValue :text="formatNumber(c.vao)" /></td>
                <td data-label="Điểm đầu ra"><MaskedValue :text="formatNumber(c.ra)" /></td>
                <td data-label="Lợi nhuận" :class="c.chenhLech >= 0 ? 'calc-in' : 'calc-out'"><MaskedValue :text="formatNumber(c.chenhLech)" /></td>
                <td class="actions-cell">
                  <button v-if="c.rosterId" type="button" class="btn btn-secondary btn-sm" @click.stop="openEdit(c)">Sửa</button>
                  <button type="button" class="btn btn-secondary btn-sm btn-detail" @click.stop="toggle(c.name)">
                    Cấu hình tính điểm
                  </button>
                  <button
                    v-if="c.rosterId"
                    type="button"
                    class="btn btn-ghost btn-sm btn-remove"
                    :disabled="deletingId === c.rosterId"
                    @click.stop="removeCustomer(c.rosterId, c.name)"
                  >
                    {{ deletingId === c.rosterId ? 'Đang xoá...' : 'Xoá khỏi danh sách' }}
                  </button>
                  <span v-else class="muted-note" title="Khách này chỉ xuất hiện trong số liệu đã nhập, chưa được thêm vào danh sách"></span>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </template>

    <ModalDialog :open="defaultConfigOpen" title="Cấu hình tính điểm mặc định" xwide @close="defaultConfigOpen = false; loadAccountRates()">
      <ScoringSettingsView embedded @saved="loadAccountRates" />
    </ModalDialog>

    <ModalDialog :open="!!editing" :title="editing ? `Sửa ${editing.name}` : ''" @close="editing = null">
      <form class="cd-phone" @submit.prevent="savePhone">
        <label>
          Số điện thoại
          <input v-model="phoneDraft" type="tel" inputmode="tel" placeholder="Chưa có" :disabled="savingPhone" data-autofocus />
        </label>
        <button type="submit" class="btn btn-primary" :disabled="savingPhone || phoneDraft.trim() === (editing?.phone || '')">{{ savingPhone ? 'Đang lưu...' : 'Lưu' }}</button>
      </form>
      <p v-if="phoneMsg" class="alert alert-error" role="alert" style="margin-top: 10px">{{ phoneMsg }}</p>
    </ModalDialog>

    <Teleport to="body">
      <div v-if="detail" class="cd-overlay" @mousedown.self="expanded = null" @keydown.esc="expanded = null">
        <div class="cd-box" role="dialog" aria-modal="true" aria-labelledby="cd-title" tabindex="-1" ref="detailBox">
          <div class="cd-head">
            <button type="button" class="cd-close" aria-label="Đóng" title="Đóng" @click="expanded = null">
              <AppIcon name="arrow-left" />
            </button>
            <h2 id="cd-title" class="cd-name">{{ detail.name }}</h2>
          </div>
          <div class="cd-top">
          <section v-if="detail.rosterId && rosterRow" class="cd-station" aria-label="Đài mặc định">
            <label class="cd-station-label">Đài xổ số mặc định khi nhập số cho khách này</label>
            <div class="cd-station-row">
              <AppSelect :model-value="rosterRow.defaultStation || 'mb'" aria-label="Đài mặc định" @update:model-value="saveDefaultStation">
                <option v-for="o in allStationOptions()" :key="o.value" :value="o.value">{{ o.label }}</option>
              </AppSelect>
              <span v-if="stationMsg" class="muted-note" role="status">{{ stationMsg }}</span>
            </div>
          </section>
          </div>
          <section v-if="detail.rosterId && rosterRow" class="cd-config" aria-label="Cấu hình tính điểm của khách này">
            <h3 class="cd-config-title">Cấu hình tính điểm của khách này{{ rosterRow.scoringRates ? ' (có cấu hình riêng)' : '' }}</h3>
            <ScoringConfigEditor scope="customer" :customer="rosterRow" :account-rates="accountRates" @saved="onCustomerConfigSaved" />
          </section>
          <div class="cd-actions">
            <button type="button" class="btn btn-secondary" @click="expanded = null">Đóng</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.config-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 12px;
  margin-bottom: 12px;
}
.cd-top {
  display: flex;
  flex-wrap: wrap;
  align-items: flex-end;
  gap: 10px 32px;
  margin-bottom: 14px;
}
.cd-station {
  flex: 1 1 320px;
  margin: 0;
}
.cd-station-label {
  display: block;
  margin-bottom: 4px;
  font-size: 13px;
  color: var(--muted);
}
.cd-station-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 12px;
}
.cd-config {
  margin: 4px 0 14px;
  padding-top: 14px;
  border-top: 1px solid var(--border);
}
.cd-config-title {
  margin: 0 0 8px;
  font-size: 17px;
}

.add-customer-card {
  margin-bottom: 16px;
}
.add-customer-form {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  flex-wrap: wrap;
}
.add-customer-field {
  flex: 1;
  margin-bottom: 0;
}
.add-customer-error {
  margin-top: 12px;
  margin-bottom: 0;
}
.cd-phone {
  display: flex;
  align-items: flex-end;
  flex-wrap: wrap;
  gap: 8px 12px;
  margin: 0;
}
.cd-phone label {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 13px;
  color: var(--muted);
}
.cd-phone input {
  height: 40px;
  padding: 0 12px;
  font-size: 15px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.actions-cell {
  white-space: nowrap;
}
.muted-note {
  color: var(--muted);
}
.search-field {
  margin-bottom: 16px;
}
.table-wrap {
  overflow-x: auto;
}
.row-clickable {
  cursor: pointer;
}
.row-clickable:hover {
  background: var(--surface-2);
}
.calc-in {
  color: var(--success-text);
  font-weight: 700;
}
.calc-out {
  color: var(--danger-text);
  font-weight: 700;
}
.detail-row td {
  background: var(--surface-2);
}
.customer-meta {
  font-size: 14px;
  color: var(--muted);
  margin-bottom: 8px;
}
.customer-entries {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.mini-entry {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
  font-size: 14px;
}
.mini-value {
  font-weight: 700;
}
.mini-detail {
  color: var(--muted);
}
/* ---- Customer detail modal ---- */
.cd-overlay {
  position: fixed;
  inset: 0;
  z-index: 90;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  background: var(--overlay);
  overflow-y: auto;
}
.cd-box {
  width: 100%;
  max-width: 1080px;
  margin: auto;
  padding: 22px 26px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 16px;
  box-shadow: var(--shadow-lg);
  outline: none;
}
.cd-head {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: -8px 0 12px -10px;
}
.cd-close {
  flex: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  padding: 0;
  font-size: 24px;
  color: var(--text-primary);
  background: transparent;
  border: 0;
  border-radius: 10px;
  cursor: pointer;
}
.cd-close:hover {
  background: var(--surface);
}
.cd-name {
  margin: 0;
  min-width: 0;
  font-size: 20px;
  line-height: 1.3;
  overflow-wrap: anywhere;
}
.cd-stats {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
  margin: 0 0 14px;
}
.cd-stat {
  padding: 8px 14px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.cd-stat dt {
  margin: 0 0 4px;
  font-size: 14px;
  color: var(--text-secondary);
}
.cd-stat dd {
  margin: 0;
  font-size: 20px;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
}
.cd-stat dd.calc-in {
  color: var(--success-text);
}
.cd-stat dd.calc-out {
  color: var(--danger-text);
}
.cd-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
}
.cd-actions .btn {
  min-height: 44px;
  padding: 0 16px;
  border-radius: 10px;
}
@media (max-width: 480px) {
  .cd-actions {
    flex-direction: column-reverse;
  }
  .cd-actions .btn {
    width: 100%;
  }
}

/* ---- Add customer: compact inline form ---- */
.add-customer-card {
  padding: 16px 20px;
  border-radius: 14px;
}
.add-customer-form {
  align-items: center;
}
.add-customer-field {
  flex: 0 1 360px;
  min-width: 220px;
}
.add-customer-field input,
.search-field input {
  height: 44px;
  padding: 0 14px;
  font-size: 15px;
  border-radius: 10px;
  border: 1px solid var(--input-border);
}
.add-customer-form .btn {
  min-height: 44px;
  padding: 0 18px;
  font-size: 14px;
  border-radius: 10px;
}

/* ---- Search toolbar above the list ---- */
.search-field {
  max-width: 360px;
  margin-bottom: 12px;
}
.search-field .search-icon {
  position: absolute;
  left: 14px;
  width: 18px;
  height: 18px;
  color: var(--text-secondary);
  pointer-events: none;
}
.search-field input {
  padding-left: 42px;
}
.search-field .input-wrap:focus-within .search-icon {
  color: var(--primary);
}

/* ---- Table inside a clear card ---- */
.table-wrap {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: var(--shadow-sm);
}
.table-wrap .table {
  font-size: 15px;
}
.table-wrap th {
  padding: 12px 16px;
  font-size: 14px;
  font-weight: 700;
  background: var(--surface);
  white-space: nowrap;
}
.table-wrap td {
  padding: 14px 16px;
  vertical-align: middle;
}
.table-wrap .table {
  width: 100%;
}
/* Every column is the same size and centred, header and cells alike (STT narrow, Thao tác wider for its buttons). */
.table-wrap .table {
  table-layout: fixed;
  width: 100%;
  min-width: 1000px;
}
.table-wrap th,
.table-wrap td {
  text-align: center;
  font-variant-numeric: tabular-nums;
  overflow-wrap: anywhere;
}
.table-wrap th:nth-child(1),
.table-wrap td:nth-child(1) {
  width: 6%;
  color: var(--text-secondary);
}
.table-wrap th:nth-child(n + 2):nth-child(-n + 6),
.table-wrap td:nth-child(n + 2):nth-child(-n + 6) {
  width: 13%;
}
.table-wrap th:nth-child(7),
.table-wrap td:nth-child(7) {
  width: 29%;
}
.table-wrap td:nth-child(2) {
  font-size: 16px;
  font-weight: 700;
  color: var(--text-primary);
}
.table-wrap td:nth-child(4),
.table-wrap td:nth-child(5) {
  font-weight: 600;
}
.view-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin: 4px 0 16px;
}
.view-tab {
  min-height: 44px;
  padding: 0 22px;
  font: inherit;
  font-size: 15px;
  font-weight: 600;
  color: var(--text-secondary);
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 999px;
  cursor: pointer;
}
.view-tab:hover {
  border-color: var(--primary);
}
.view-tab.active {
  color: var(--on-primary);
  background: var(--primary);
  border-color: var(--primary);
}
.table-wrap .row-clickable:hover {
  background: color-mix(in srgb, var(--primary) 6%, transparent);
}
.calc-in,
.calc-out {
  font-weight: 700;
}

/* Delete: ghost destructive, quiet until hovered */
.actions-cell {
  text-align: center !important;
  white-space: nowrap;
}
.actions-cell .btn {
  min-height: 36px;
  margin-left: 6px;
}
.btn-remove {
  min-height: 36px;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
  color: var(--danger-text);
  background: var(--surface);
  border: 1px solid var(--input-border);
}
.btn-remove:hover:not(:disabled) {
  background: var(--danger-soft);
  border-color: var(--danger-text);
}

/* Expanded detail */
.customer-meta {
  font-size: 14px;
  color: var(--text-secondary);
}
.mini-entry {
  font-size: 14px;
}

@media (max-width: 640px) {
  .add-customer-card {
    padding: 16px;
  }
  .add-customer-field {
    flex: 1 1 100%;
  }
  .add-customer-form .btn {
    flex: 1 1 100%;
  }
  .search-field {
    max-width: none;
  }
}

/* tablets: drop the STT column and let the columns share the width so the table fits without sideways scroll */
@media (max-width: 900px) {
  .table-wrap th:nth-child(1),
  .table-wrap td:nth-child(1):not([colspan]) {
    display: none;
  }
  .table-wrap .table {
    table-layout: auto;
    min-width: 0;
  }
  .table-wrap th:nth-child(n + 2),
  .table-wrap td:nth-child(n + 2) {
    width: auto;
  }
  .table-wrap th,
  .table-wrap td {
    padding-left: 10px;
    padding-right: 10px;
  }
  .actions-cell {
    white-space: normal;
  }
}

/* ---- Actions: "Cấu hình tính điểm" + "Xoá khỏi danh sách" ---- */
.actions-cell {
  display: table-cell;
  white-space: nowrap;
}
.actions-cell .btn {
  margin-left: 6px;
}
.btn-detail {
  min-height: 36px;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
}
.detail-totals {
  display: none;
}

/* ---- Phones: one compact line per customer; numbers live in the detail ---- */
@media (max-width: 640px) {
  .table-wrap .stack-table td:nth-child(1):not([colspan]),
  .table-wrap .stack-table td:nth-child(3),
  .table-wrap .stack-table td:nth-child(4),
  .table-wrap .stack-table td:nth-child(5) {
    display: none;
  }
  .table-wrap .stack-table tr.row-clickable {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 6px 12px;
    padding: 10px 14px;
  }
  .table-wrap .stack-table tr.row-clickable td {
    padding: 0 !important;
  }
  .table-wrap .stack-table tr.row-clickable td:nth-child(2) {
    flex: 1 1 140px;
    min-width: 0 !important;
    justify-content: flex-start;
    text-align: left !important;
    font-size: 16px;
  }
  .table-wrap .stack-table tr.row-clickable td:nth-child(2)::before {
    display: none;
  }
  .table-wrap .stack-table .actions-cell {
    display: flex;
    flex: 1 1 100%;
    gap: 8px;
    justify-content: center;
  }
  .table-wrap .stack-table .actions-cell .btn {
    flex: 1 1 0;
    min-width: 0;
    max-width: 180px;
    padding: 0 6px;
    font-size: 14px;
    white-space: nowrap;
    justify-content: center;
  }
  .actions-cell .btn {
    margin-left: 0;
  }
  .detail-totals {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin-bottom: 8px;
    font-size: 14px;
    color: var(--text-secondary);
  }
  .detail-totals strong {
    color: var(--text-primary);
  }
  .detail-totals .calc-in {
    color: var(--success-text);
  }
  .detail-totals .calc-out {
    color: var(--danger-text);
  }
  .table-wrap .stack-table tr.detail-row {
    margin-top: -8px;
  }
}

/* tablets only: the two action buttons stack so the table needs no sideways scroll */
@media (min-width: 641px) and (max-width: 900px) {
  .actions-cell {
    width: 140px;
    white-space: normal;
  }
  .actions-cell .btn {
    display: flex;
    width: 100%;
    margin: 0 0 4px;
    justify-content: center;
  }
}
.mask-row {
  margin-bottom: 12px;
}
/* Wide dialog: the four figures on one row. */
@media (min-width: 720px) {
  .cd-stats {
    grid-template-columns: repeat(4, 1fr);
  }
}
</style>
