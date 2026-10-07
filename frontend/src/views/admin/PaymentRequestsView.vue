<!--
  /admin/payment-requests - quản lý thanh toán gói dịch vụ (A18).
  API: GET /admin/payment-requests?status=pending|approved|rejected|cancelled|all&q=&from=&to=&limit=&offset=
         -> { requests, total, hasMore, summary:{ pending, approvedCount, revenueToday, revenue7d, revenue30d, revenueAll } }
       GET  /admin/payment-requests/export?<same filters>  -> CSV
       POST /admin/payment-requests/:id/approve            -> grants the package, marks 'approved'
       POST /admin/payment-requests/:id/reject {reason}    -> marks 'rejected' (reason is shown to the user)
  Approve/reject are irreversible (409 if already decided), so each goes through a confirm step; the
  user is told of the decision at once (push) and every decision is written to the security log.
-->
<script setup>
import { showConfirm } from '../../confirm'
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { api, ApiError } from '../../api'
import ModalDialog from '../../components/ModalDialog.vue'

const PAGE = 30
const loading = ref(true)
const loadingMore = ref(false)
const error = ref('')
const requests = ref([])
const total = ref(0)
const hasMore = ref(false)
const summary = ref(null)

const status = ref('pending')
const q = ref('')
const from = ref('')
const to = ref('')

const actionError = ref('')
const actionBusy = ref(false)

const rejectFor = ref(null) // request being rejected
const rejectReason = ref('')

const packageLabels = {
  none: 'Chưa đăng ký',
  trial: 'Dùng thử 30 ngày',
  '1m': '1 tháng',
  '3m': '3 tháng',
  '6m': '6 tháng',
  '12m': '12 tháng',
}
const statusLabels = { pending: 'Chờ duyệt', approved: 'Đã duyệt', rejected: 'Đã từ chối', cancelled: 'Người dùng huỷ' }
const STATUS_TABS = [
  { key: 'pending', label: 'Chờ duyệt' },
  { key: 'approved', label: 'Đã duyệt' },
  { key: 'rejected', label: 'Đã từ chối' },
  { key: 'cancelled', label: 'Đã huỷ' },
  { key: 'all', label: 'Tất cả' },
]
const REASONS = ['Chưa nhận được tiền', 'Số tiền không khớp', 'Sai nội dung chuyển khoản', 'Yêu cầu trùng']

function query(extra = {}) {
  const p = new URLSearchParams({ status: status.value })
  if (q.value.trim()) p.set('q', q.value.trim())
  if (from.value) p.set('from', from.value)
  if (to.value) p.set('to', to.value)
  for (const [k, v] of Object.entries(extra)) p.set(k, String(v))
  return p.toString()
}

async function load({ more = false } = {}) {
  if (more) loadingMore.value = true
  else loading.value = true
  error.value = ''
  try {
    const res = await api.get(`/admin/payment-requests?${query({ limit: PAGE, offset: more ? requests.value.length : 0 })}`)
    requests.value = more ? [...requests.value, ...res.requests] : res.requests
    total.value = res.total
    hasMore.value = res.hasMore
    summary.value = res.summary
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải danh sách yêu cầu'
  } finally {
    loading.value = false
    loadingMore.value = false
  }
}

let timer = null
watch([q, from, to], () => {
  clearTimeout(timer)
  timer = setTimeout(() => load(), 300)
})
watch(status, () => load())
onBeforeUnmount(() => clearTimeout(timer))

async function approve(r) {
  actionError.value = ''
  const ok = await showConfirm({
    title: 'Duyệt thanh toán',
    message: `Xác nhận đã nhận ${formatMoney(r.amount)} từ ${r.userName} (${r.referenceCode}) và cấp gói ${packageLabels[r.packageType] || r.packageType}?`,
    confirmText: 'Duyệt',
  })
  if (ok) await act(r.id, 'approve')
}

function askReject(r) {
  actionError.value = ''
  rejectFor.value = r
  rejectReason.value = ''
}

async function confirmReject() {
  const r = rejectFor.value
  if (!r) return
  await act(r.id, 'reject', { reason: rejectReason.value.trim() })
  rejectFor.value = null
}

async function act(id, action, body) {
  actionBusy.value = true
  try {
    await api.post(`/admin/payment-requests/${id}/${action}`, body)
    await load()
  } catch (err) {
    actionError.value = err instanceof ApiError ? err.message : 'Không thể xử lý yêu cầu'
    await load()
  } finally {
    actionBusy.value = false
  }
}

async function exportCsv() {
  error.value = ''
  try {
    const blob = await api.blob(`/admin/payment-requests/export?${query()}`)
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `thanh-toan-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không xuất được file'
  }
}

function formatMoney(v) {
  return Number(v).toLocaleString('vi-VN') + ' đ'
}
const hasFilter = computed(() => q.value || from.value || to.value)
function clearFilters() {
  q.value = from.value = to.value = ''
}

onMounted(load)
</script>

<template>
  <div class="page">
    <div class="head">
      <div>
        <h1 class="page-title">Quản lý thanh toán</h1>
        <p class="page-subtitle" style="margin-bottom: 0">Duyệt chuyển khoản, theo dõi doanh thu và lịch sử thanh toán gói dịch vụ.</p>
      </div>
      <button class="btn btn-secondary btn-sm" :disabled="loading" @click="exportCsv">Xuất CSV</button>
    </div>

    <div v-if="summary" class="sum-grid">
      <div class="card sum-card" :class="{ hot: summary.pending > 0 }">
        <div class="sum-label">Chờ duyệt</div>
        <div class="sum-value">{{ summary.pending }}</div>
      </div>
      <div class="card sum-card">
        <div class="sum-label">Doanh thu hôm nay</div>
        <div class="sum-value">{{ formatMoney(summary.revenueToday) }}</div>
      </div>
      <div class="card sum-card">
        <div class="sum-label">7 ngày</div>
        <div class="sum-value">{{ formatMoney(summary.revenue7d) }}</div>
      </div>
      <div class="card sum-card">
        <div class="sum-label">30 ngày</div>
        <div class="sum-value">{{ formatMoney(summary.revenue30d) }}</div>
      </div>
      <div class="card sum-card">
        <div class="sum-label">Tổng ({{ summary.approvedCount }} giao dịch)</div>
        <div class="sum-value">{{ formatMoney(summary.revenueAll) }}</div>
      </div>
    </div>

    <div class="tabs" role="tablist" aria-label="Trạng thái">
      <button
        v-for="t in STATUS_TABS"
        :key="t.key"
        type="button"
        role="tab"
        class="tab"
        :class="{ active: status === t.key }"
        :aria-selected="status === t.key"
        @click="status = t.key"
      >
        {{ t.label }}
      </button>
    </div>

    <div class="filters">
      <input v-model="q" type="search" class="f-input f-q" placeholder="Tìm tên, tài khoản hoặc mã tham chiếu..." aria-label="Tìm kiếm" />
      <label class="f-date">Từ <input v-model="from" type="date" class="f-input" /></label>
      <label class="f-date">Đến <input v-model="to" type="date" class="f-input" /></label>
      <button v-if="hasFilter" type="button" class="btn btn-ghost btn-sm" @click="clearFilters">Xoá lọc</button>
    </div>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="actionError" class="alert alert-error">{{ actionError }}</div>

    <div class="card" style="padding: 0; overflow-x: auto">
      <table class="table stack-table">
        <thead>
          <tr>
            <th>Mã</th>
            <th>Khách hàng</th>
            <th>Gói</th>
            <th>Số tiền</th>
            <th>Trạng thái</th>
            <th>Thời gian</th>
            <th>Thao tác</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading"><td colspan="7">Đang tải...</td></tr>
          <tr v-else-if="requests.length === 0"><td colspan="7">Không có yêu cầu nào</td></tr>
          <tr v-for="r in requests" :key="r.id">
            <td data-label="Mã"><code class="ref">{{ r.referenceCode }}</code></td>
            <td data-label="Khách hàng">{{ r.userName }} (@{{ r.username }})</td>
            <td data-label="Gói">{{ packageLabels[r.packageType] || r.packageType }}</td>
            <td data-label="Số tiền">{{ formatMoney(r.amount) }}</td>
            <td data-label="Trạng thái">
              <span
                class="chip"
                :class="{ 'chip-accent': r.status === 'approved', 'chip-danger': r.status === 'rejected', 'chip-warning': r.status === 'pending' }"
              >
                {{ statusLabels[r.status] || r.status }}
              </span>
              <div v-if="r.rejectReason && r.status === 'rejected'" class="reason">{{ r.rejectReason }}</div>
            </td>
            <td data-label="Thời gian">
              {{ new Date(r.createdAt).toLocaleString('vi-VN') }}
              <div v-if="r.decidedAt" class="reason">Xử lý: {{ new Date(r.decidedAt).toLocaleString('vi-VN') }}</div>
            </td>
            <td data-label="Thao tác">
              <div v-if="r.status === 'pending'" style="display: flex; gap: 6px">
                <button class="btn btn-primary btn-sm" :disabled="actionBusy" @click="approve(r)">Duyệt</button>
                <button class="btn btn-danger btn-sm" :disabled="actionBusy" @click="askReject(r)">Từ chối</button>
              </div>
              <span v-else>-</span>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="!loading && requests.length" class="more">
      <span>Hiển thị {{ requests.length }} / {{ total }}</span>
      <button v-if="hasMore" class="btn btn-secondary btn-sm" :disabled="loadingMore" @click="load({ more: true })">
        {{ loadingMore ? 'Đang tải...' : 'Xem thêm' }}
      </button>
    </div>

    <ModalDialog
      :open="!!rejectFor"
      title="Từ chối thanh toán"
      :description="rejectFor ? `${rejectFor.userName} - ${rejectFor.referenceCode} - ${formatMoney(rejectFor.amount)}` : ''"
      @close="rejectFor = null"
    >
      <label class="r-label" for="reject-reason">Lý do (người dùng sẽ nhìn thấy)</label>
      <div class="r-quick">
        <button v-for="x in REASONS" :key="x" type="button" class="r-chip" @click="rejectReason = x">{{ x }}</button>
      </div>
      <textarea id="reject-reason" v-model="rejectReason" class="f-input r-text" rows="3" maxlength="200" data-autofocus placeholder="Không bắt buộc"></textarea>
      <template #footer>
        <button type="button" class="btn btn-secondary" @click="rejectFor = null">Huỷ</button>
        <button type="button" class="btn btn-danger" :disabled="actionBusy" @click="confirmReject">Từ chối</button>
      </template>
    </ModalDialog>
  </div>
</template>

<style scoped>
.head {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 16px;
}
.sum-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 12px;
  margin-bottom: 16px;
}
.sum-card {
  padding: 14px 16px;
}
.sum-card.hot {
  border-color: var(--primary);
}
.sum-label {
  font-size: 13px;
  color: var(--text-secondary);
}
.sum-value {
  margin-top: 4px;
  font-size: 20px;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
}
.tabs {
  display: flex;
  gap: 4px;
  margin-bottom: 12px;
  padding: 4px;
  overflow-x: auto;
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 12px;
}
.tab {
  flex: 1 0 auto;
  min-height: 40px;
  padding: 0 16px;
  font: inherit;
  font-size: 14px;
  font-weight: 600;
  white-space: nowrap;
  color: var(--text-secondary);
  background: transparent;
  border: 0;
  border-radius: 9px;
  cursor: pointer;
}
.tab.active {
  color: var(--on-primary);
  background: var(--primary);
}
.filters {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
}
.f-input {
  min-height: 42px;
  padding: 0 12px;
  font: inherit;
  font-size: 14px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  box-sizing: border-box;
}
.f-q {
  flex: 1 1 240px;
}
.f-date {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 14px;
  color: var(--text-secondary);
}
.ref {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  letter-spacing: 0.05em;
}
.reason {
  margin-top: 2px;
  font-size: 13px;
  color: var(--text-secondary);
}
.more {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-top: 12px;
  font-size: 14px;
  color: var(--text-secondary);
}
.r-label {
  display: block;
  margin-bottom: 8px;
  font-size: 14px;
  font-weight: 700;
}
.r-quick {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 10px;
}
.r-chip {
  padding: 6px 10px;
  font: inherit;
  font-size: 13px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 999px;
  cursor: pointer;
}
.r-text {
  width: 100%;
  padding: 10px 12px;
  resize: vertical;
}
</style>
