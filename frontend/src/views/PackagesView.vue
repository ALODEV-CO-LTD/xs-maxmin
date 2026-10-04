<!--
  Combined Gói dịch vụ + Thanh toán: current package status, purchasable
  plan catalog, bank transfer info, and the user's own payment-request
  history all in one page - merged from the former separate
  PackagesView/PaymentsView since both centered on the same purchase flow
  (POST /me/packages/purchase) and users had to bounce between two pages
  to buy a plan and then find out where to pay for it.

  Purchasing only creates a *pending* payment request - an admin must
  approve it via bank transfer confirmation before the package/quota is
  actually granted.

  API: GET /me (current package), GET /me/packages (catalog),
       GET /me/payment-info (bank transfer details),
       GET /me/payment-requests (history + pending check),
       POST /me/packages/purchase
-->
<script setup>
import { showConfirm } from '../confirm'
import { computed, onMounted, ref } from 'vue'
import { api } from '../api'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()

const plans = ref([])
const bankInfo = ref(null)
const requests = ref([])
const loading = ref(true)
const loadError = ref('')

const purchasing = ref(null)
const purchaseError = ref('')
const purchaseSuccess = ref('')

const pkg = computed(() => auth.user?.package)
const pendingRequest = computed(() => requests.value.find((r) => r.status === 'pending') || null)

// VietQR quick-pay code: encodes bank + account + amount + a transfer note
// so the customer's banking app can scan it and auto-fill the transfer
// instead of typing everything by hand. Only shown once we know an amount
// (i.e. there's a pending purchase to pay for).
const qrUrl = computed(() => {
  const info = bankInfo.value
  const req = pendingRequest.value
  if (!info?.bankBin || !info?.bankAccountNumber || !req) return null
  const params = new URLSearchParams({
    amount: String(req.amount),
    addInfo: `${auth.user?.username || ''} ${req.packageType}`.trim(),
    accountName: info.bankAccountHolder || '',
  })
  return `https://img.vietqr.io/image/${info.bankBin}-${info.bankAccountNumber}-compact2.png?${params}`
})

function formatVnd(n) {
  return new Intl.NumberFormat('vi-VN').format(n) + 'đ'
}

function formatDate(iso) {
  if (!iso) return '-'
  return new Date(iso).toLocaleDateString('vi-VN')
}

function formatDateTime(iso) {
  if (!iso) return '-'
  return new Date(iso).toLocaleString('vi-VN')
}

function statusLabel(status) {
  return { pending: 'Đang chờ duyệt', approved: 'Đã duyệt', rejected: 'Bị từ chối' }[status] || status
}

function statusChipClass(status) {
  return { pending: 'chip-warning', approved: 'chip-accent', rejected: 'chip-danger' }[status] || ''
}

async function loadAll() {
  loading.value = true
  loadError.value = ''
  try {
    const [me, catalog, info, reqs] = await Promise.all([
      auth.fetchMe(),
      api.get('/me/packages'),
      api.get('/me/payment-info'),
      api.get('/me/payment-requests'),
    ])
    plans.value = catalog.packages
    bankInfo.value = info
    requests.value = reqs.requests
  } catch (err) {
    loadError.value = err.message || 'Không tải được thông tin gói'
  } finally {
    loading.value = false
  }
}

onMounted(loadAll)

async function purchase(plan) {
  purchaseError.value = ''
  purchaseSuccess.value = ''
  if (pendingRequest.value) return
  if (!(await showConfirm({
    title: 'Đăng ký gói',
    message: `Xác nhận đăng ký gói "${plan.label}" (${formatVnd(plan.priceVnd)})? Bạn sẽ cần chuyển khoản và chờ admin duyệt.`,
    confirmText: 'Đăng ký',
  }))) {
    return
  }
  purchasing.value = plan.type
  try {
    await api.post('/me/packages/purchase', { packageType: plan.type })
    purchaseSuccess.value = 'Đã tạo yêu cầu. Vui lòng chuyển khoản theo thông tin bên dưới và chờ admin xác nhận.'
    await loadAll()
  } catch (err) {
    purchaseError.value = err.message || 'Không tạo được yêu cầu mua gói'
  } finally {
    purchasing.value = null
  }
}
</script>

<template>
  <div class="page">
    <h1 class="page-title">Gói dịch vụ & Thanh toán</h1>
    <p class="page-subtitle">Xem gói hiện tại, đăng ký gói mới và theo dõi thanh toán, tất cả ở một nơi.</p>

    <div v-if="loading" class="card">Đang tải...</div>
    <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <template v-else>
      <div class="card current-card">
        <h3 style="margin-top: 0">Gói hiện tại</h3>
        <div class="current-row">
          <span class="chip" :class="pkg?.isActive ? 'chip-accent' : 'chip-danger'">{{ pkg?.label }}</span>
          <span class="current-detail">Hết hạn: {{ formatDate(pkg?.expiresAt) }}</span>
        </div>
        <div v-if="!pkg?.isActive" class="alert alert-warning" style="margin-top: 12px; margin-bottom: 0">
          Gói đã hết hạn. Đăng ký gói mới bên dưới để tiếp tục sử dụng.
        </div>
      </div>

      <div v-if="pendingRequest" class="alert alert-warning">
        Bạn có một yêu cầu mua gói "{{ pendingRequest.packageType }}" đang chờ admin xác nhận. Chuyển khoản theo
        thông tin bên dưới nếu chưa thực hiện.
      </div>
      <div v-if="purchaseError" class="alert alert-error">{{ purchaseError }}</div>
      <div v-if="purchaseSuccess" class="alert alert-success">{{ purchaseSuccess }}</div>

      <h3>Các gói có sẵn</h3>
      <div class="plans-grid">
        <div v-for="plan in plans" :key="plan.type" class="card plan-card">
          <div class="plan-label">{{ plan.label }}</div>
          <div class="plan-price">{{ formatVnd(plan.priceVnd) }}</div>
          <div class="plan-detail">{{ plan.durationDays }} ngày</div>
          <button
            class="btn btn-primary btn-block"
            style="margin-top: 12px"
            :disabled="!!pendingRequest || purchasing === plan.type"
            @click="purchase(plan)"
          >
            {{ purchasing === plan.type ? 'Đang xử lý...' : 'Đăng ký' }}
          </button>
        </div>
      </div>

      <div class="card bank-card">
        <h3 style="margin-top: 0">Thông tin chuyển khoản</h3>
        <template v-if="bankInfo?.bankName">
          <div class="bank-row"><span>Ngân hàng</span><strong>{{ bankInfo.bankName }}</strong></div>
          <div class="bank-row"><span>Số tài khoản</span><strong>{{ bankInfo.bankAccountNumber }}</strong></div>
          <div class="bank-row"><span>Chủ tài khoản</span><strong>{{ bankInfo.bankAccountHolder }}</strong></div>
          <div v-if="qrUrl" class="qr-wrap">
            <img :src="qrUrl" alt="Mã QR chuyển khoản" class="qr-img" />
            <p class="page-subtitle" style="text-align: center; margin: 8px 0 0">
              Quét mã bằng app ngân hàng để tự động điền số tiền và nội dung chuyển khoản.
            </p>
          </div>
        </template>
        <p v-else class="page-subtitle" style="margin: 0">Chưa cấu hình thông tin thanh toán.</p>
      </div>

      <h3>Lịch sử thanh toán</h3>
      <div v-if="requests.length === 0" class="card">Chưa có yêu cầu nào.</div>
      <div v-else class="req-list">
        <div v-for="r in requests" :key="r.id" class="card req-item">
          <div class="req-top">
            <strong>{{ r.packageType }}</strong>
            <span class="chip" :class="statusChipClass(r.status)">{{ statusLabel(r.status) }}</span>
          </div>
          <div class="req-detail">{{ formatVnd(r.amount) }} · {{ formatDateTime(r.createdAt) }}</div>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.current-card {
  margin-bottom: 20px;
}
.current-row {
  display: flex;
  align-items: center;
  gap: 12px;
}
.current-detail {
  color: var(--muted);
  font-size: 13px;
}
.plans-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 12px;
  margin-bottom: 20px;
}
.plan-card {
  text-align: center;
}
.plan-label {
  font-weight: 700;
  margin-bottom: 6px;
}
.plan-price {
  font-size: 20px;
  font-weight: 800;
  color: var(--accent-strong);
}
.plan-detail {
  color: var(--muted);
  font-size: 13px;
  margin-top: 2px;
}
.bank-card {
  margin-bottom: 20px;
}
.bank-row {
  display: flex;
  justify-content: space-between;
  padding: 8px 0;
  border-bottom: 1px solid var(--border);
  font-size: 14px;
}
.bank-row:last-child {
  border-bottom: none;
}
.qr-wrap {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin-top: 14px;
  padding-top: 14px;
  border-top: 1px solid var(--border);
}
.qr-img {
  width: 220px;
  height: 220px;
  border-radius: var(--radius-sm);
  background: #fff;
  padding: 8px;
}
.req-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.req-item {
  padding: 14px 16px;
}
.req-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 4px;
}
.req-detail {
  color: var(--muted);
  font-size: 13px;
}
/* ---- Layout: readable column, compact spacing ---- */
.current-card,
.page > .alert,
.plans-grid,
.bank-card,
.req-list,
.page > .card {
  max-width: 1100px;
}
.page > h3 {
  margin: 24px 0 12px;
  font-size: 18px;
}

/* Current plan: prominent but compact, status shown on the left edge */
.current-card {
  margin-bottom: 16px;
  padding: 16px 20px;
  border-radius: 14px;
  border-left: 4px solid var(--border);
}
.current-card:has(.chip-accent) {
  border-left-color: var(--success);
}
.current-card:has(.chip-danger) {
  border-left-color: var(--danger);
}
.current-card h3 {
  margin-bottom: 8px !important;
  font-size: 13px;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--text-secondary);
}
.current-row {
  gap: 16px;
  flex-wrap: wrap;
}
.current-row .chip {
  font-size: 15px;
  padding: 6px 16px;
}
.current-detail {
  font-size: 15px;
  color: var(--text-primary);
  font-weight: 600;
}
.current-card .alert {
  font-size: 14px;
  border-radius: 10px;
}

/* Pending / feedback alerts: clear, not loud */
.page > .alert {
  padding: 12px 16px;
  margin-bottom: 16px;
  font-size: 14px;
  line-height: 1.5;
  border-radius: 12px;
  border: 1px solid color-mix(in srgb, currentColor 30%, transparent);
}

/* Plan cards: price first, duration secondary, aligned buttons */
.plans-grid {
  grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
  gap: 16px;
  margin-bottom: 16px;
}
.plan-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 20px 16px;
  border-radius: 14px;
}
.plan-label {
  margin-bottom: 8px;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-secondary);
}
.plan-price {
  font-size: 28px;
  line-height: 1.1;
  color: var(--text-primary);
  font-variant-numeric: tabular-nums;
}
.plan-detail {
  margin: 6px 0 16px;
  font-size: 14px;
}
.plan-card .btn {
  margin-top: auto !important;
  min-height: 44px;
  font-size: 14px;
  border-radius: 10px;
}

/* Payment area: bank details left, QR + hint right */
.bank-card {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 260px;
  /* trailing 1fr row absorbs the QR's extra height so bank rows stay compact */
  grid-template-rows: auto auto auto auto 1fr;
  column-gap: 32px;
  align-items: start;
  padding: 20px 24px;
  border-radius: 14px;
}
.bank-card > h3 {
  grid-column: 1 / -1;
  margin-bottom: 12px !important;
  font-size: 18px;
}
.bank-card > .bank-row {
  grid-column: 1;
  gap: 16px;
  padding: 12px 0;
  font-size: 15px;
}
.bank-row span {
  color: var(--text-secondary);
}
.bank-row strong {
  text-align: right;
  overflow-wrap: anywhere;
}
.qr-wrap {
  grid-column: 2;
  grid-row: 2 / span 4;
  margin: 0;
  padding: 16px;
  background: var(--surface);
  border: 0;
  border-radius: 12px;
}
.qr-img {
  width: 228px;
  height: 228px;
  max-width: 100%;
  height: auto;
  aspect-ratio: 1;
  border: 1px solid var(--border);
}
.qr-wrap .page-subtitle {
  margin: 12px 0 0 !important;
  font-size: 14px;
  line-height: 1.5;
  color: var(--text-secondary);
}
.bank-card > p {
  grid-column: 1 / -1;
}

/* History: one compact line per payment */
.req-item {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 4px 16px;
  padding: 12px 16px;
  border-radius: 12px;
}
.req-top {
  display: flex;
  align-items: center;
  gap: 12px;
  margin: 0;
}
.req-item .chip {
  font-size: 13px;
  padding: 3px 12px;
}
.req-detail {
  margin-left: auto;
  font-size: 14px;
  color: var(--text-secondary);
  font-variant-numeric: tabular-nums;
}
.page > .card:not(.current-card):not(.plan-card):not(.bank-card):not(.req-item) {
  padding: 24px;
  background: var(--surface);
  border: 1px dashed var(--input-border);
  color: var(--text-secondary);
  text-align: center;
}

@media (max-width: 720px) {
  .bank-card {
    grid-template-columns: 1fr;
    padding: 16px;
  }
  .qr-wrap {
    grid-column: 1;
    grid-row: auto;
    margin-top: 16px;
  }
  .req-detail {
    margin-left: 0;
    width: 100%;
  }
}
</style>
