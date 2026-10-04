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
import { computed, nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api, ApiError } from '../api'
import AppIcon from '../components/AppIcon.vue'

const route = useRoute()
const router = useRouter()
// Opened via "+ Thêm khách hàng mới" on Nhập số: after adding a customer, go back there.
const fromEntries = route.query.from === 'entries'
const addInput = ref(null)

const entries = ref([])
const loading = ref(true)
const loadError = ref('')
const search = ref('')
const expanded = ref(null)

const roster = ref([]) // [{id, name, createdAt}] from /me/customers
const newCustomerName = ref('')
const addingCustomer = ref(false)
const addError = ref('')
const deletingId = ref(null)

async function loadRoster() {
  try {
    const { customers: list } = await api.get('/me/customers')
    roster.value = list
  } catch (err) {
    // Non-fatal - the page still works from entries alone, just without
    // "add new customer" until this loads.
  }
}

async function addCustomer() {
  const name = newCustomerName.value.trim()
  if (!name) return
  addError.value = ''
  addingCustomer.value = true
  try {
    const created = await api.post('/me/customers', { name })
    roster.value.push(created)
    roster.value.sort((a, b) => a.name.localeCompare(b.name, 'vi'))
    newCustomerName.value = ''
    if (fromEntries) {
      router.push({ name: 'entries', query: { customer: created.name } })
      return
    }
  } catch (err) {
    addError.value = err instanceof ApiError ? err.message : 'Không thêm được khách hàng'
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
    addError.value = err instanceof ApiError ? err.message : 'Không xoá được'
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
    const list = await api.get('/me/entries')
    entries.value = list.entries
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
onMounted(() => window.addEventListener('keydown', onKeydown))
onBeforeUnmount(() => window.removeEventListener('keydown', onKeydown))
onMounted(loadRoster)
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
      byName.set(name, { name, rosterId: null, count: 0, vao: 0, ra: 0, lastDate: null, entries: [] })
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
  const q = search.value.trim().toLowerCase()
  if (!q) return customers.value
  return customers.value.filter((c) => c.name.toLowerCase().includes(q))
})

const detailBox = ref(null)
const detail = computed(() => customers.value.find((c) => c.name === expanded.value) || null)
function toggle(name) {
  expanded.value = name
  nextTick(() => detailBox.value?.focus())
}
async function removeFromDetail(c) {
  await removeCustomer(c.rosterId, c.name)
  if (!roster.value.some((r) => r.id === c.rosterId)) expanded.value = null
}
</script>

<template>
  <div class="page">
    <h1 class="page-title">Khách hàng</h1>
    <p class="page-subtitle">Danh sách khách hàng của bạn. Thêm khách mới ở đây, số liệu vào/ra được tổng hợp từ các lượt nhập, tính như ở trang Nhập số liệu.</p>

    <div class="card add-customer-card">
      <form class="add-customer-form" @submit.prevent="addCustomer">
        <div class="field add-customer-field">
          <div class="input-wrap">
            <input ref="addInput" v-model="newCustomerName" type="text" placeholder="Tên khách hàng mới" :disabled="addingCustomer" />
          </div>
        </div>
        <button type="submit" class="btn btn-primary" :disabled="addingCustomer || !newCustomerName.trim()">
          {{ addingCustomer ? 'Đang thêm...' : 'Thêm khách hàng' }}
        </button>
      </form>
      <div v-if="addError" class="alert alert-error add-customer-error">{{ addError }}</div>
    </div>

    <div v-if="loading" class="card">Đang tải...</div>
    <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <template v-else>
      <div class="field search-field">
        <div class="input-wrap">
          <AppIcon name="search" class="search-icon" />
          <input v-model="search" type="text" placeholder="Tìm theo tên khách hàng..." />
        </div>
      </div>

      <div v-if="customers.length === 0" class="card">Chưa có khách hàng nào. Thêm khách ở trên để bắt đầu.</div>
      <div v-else-if="filteredCustomers.length === 0" class="card">Không tìm thấy khách hàng phù hợp.</div>

      <div v-else class="table-wrap">
        <table class="table stack-table">
          <thead>
            <tr>
              <th>STT</th>
              <th>Tên</th>
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
                <td data-label="Điểm đầu vào">{{ formatNumber(c.vao) }}</td>
                <td data-label="Điểm đầu ra">{{ formatNumber(c.ra) }}</td>
                <td data-label="Lợi nhuận" :class="c.chenhLech >= 0 ? 'calc-in' : 'calc-out'">{{ formatNumber(c.chenhLech) }}</td>
                <td class="actions-cell">
                  <button type="button" class="btn btn-secondary btn-sm btn-detail" @click.stop="toggle(c.name)">
                    Xem chi tiết
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

    <Teleport to="body">
      <div v-if="detail" class="cd-overlay" @mousedown.self="expanded = null" @keydown.esc="expanded = null">
        <div class="cd-box" role="dialog" aria-modal="true" aria-labelledby="cd-title" tabindex="-1" ref="detailBox">
          <h2 id="cd-title" class="cd-name">{{ detail.name }}</h2>
          <dl class="cd-stats">
            <div class="cd-stat">
              <dt>Số lượt chơi</dt>
              <dd>{{ formatNumber(detail.count) }}</dd>
            </div>
            <div class="cd-stat">
              <dt>Điểm đầu vào</dt>
              <dd>{{ formatNumber(detail.vao) }}</dd>
            </div>
            <div class="cd-stat">
              <dt>Điểm đầu ra</dt>
              <dd>{{ formatNumber(detail.ra) }}</dd>
            </div>
            <div class="cd-stat">
              <dt>Lợi nhuận</dt>
              <dd :class="detail.chenhLech >= 0 ? 'calc-in' : 'calc-out'">{{ formatNumber(detail.chenhLech) }}</dd>
            </div>
          </dl>
          <div class="cd-actions">
            <button
              v-if="detail.rosterId"
              type="button"
              class="btn btn-ghost btn-remove"
              :disabled="deletingId === detail.rosterId"
              @click="removeFromDetail(detail)"
            >
              {{ deletingId === detail.rosterId ? 'Đang xoá...' : 'Xoá khỏi danh sách' }}
            </button>
            <button type="button" class="btn btn-secondary" @click="expanded = null">Đóng</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
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
  font-size: 12px;
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
  font-size: 13px;
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
  max-width: 420px;
  margin: auto;
  padding: 24px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 16px;
  box-shadow: var(--shadow-lg);
  outline: none;
}
.cd-name {
  margin: 0 0 16px;
  font-size: 20px;
  line-height: 1.3;
  overflow-wrap: anywhere;
}
.cd-stats {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
  margin: 0 0 20px;
}
.cd-stat {
  padding: 12px 14px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.cd-stat dt {
  margin: 0 0 4px;
  font-size: 13px;
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
  min-height: 40px;
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
  min-width: 640px;
  font-size: 15px;
}
.table-wrap th {
  padding: 12px 16px;
  font-size: 13px;
  font-weight: 700;
  background: var(--surface);
  white-space: nowrap;
}
.table-wrap td {
  padding: 14px 16px;
  vertical-align: middle;
}
.table-wrap th:nth-child(1),
.table-wrap td:nth-child(1) {
  width: 64px;
  color: var(--text-secondary);
}
.table-wrap th:nth-child(6) {
  text-align: right;
}
/* numeric columns right-aligned for comparison */
.table-wrap th:nth-child(n + 3):nth-child(-n + 5),
.table-wrap td:nth-child(n + 3):nth-child(-n + 5) {
  width: 150px;
  text-align: right;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.table-wrap td:nth-child(2) {
  min-width: 160px;
  font-size: 16px;
  font-weight: 700;
  color: var(--text-primary);
}
.table-wrap td:nth-child(3),
.table-wrap td:nth-child(4) {
  font-weight: 600;
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
  text-align: right;
  width: 170px;
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
  font-size: 13px;
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

/* tablets: slimmer number columns so the table fits without sideways scroll */
@media (max-width: 900px) {
  .table-wrap th:nth-child(1),
  .table-wrap td:nth-child(1):not([colspan]) {
    display: none;
  }
  .table-wrap th:nth-child(n + 3):nth-child(-n + 5),
  .table-wrap td:nth-child(n + 3):nth-child(-n + 5) {
    width: 100px;
  }
  .table-wrap td:nth-child(2) {
    min-width: 120px;
  }
  .table-wrap th,
  .table-wrap td {
    padding-left: 12px;
    padding-right: 12px;
  }
}

/* ---- Actions: "Xem chi tiết" + "Xoá khỏi danh sách" ---- */
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
    font-size: 13px;
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
</style>
