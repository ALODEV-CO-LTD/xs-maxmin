<!--
  /admin/payment-requests - approve/reject pending payment requests.
  API: GET /admin/payment-requests            -> pending only, oldest first
       GET /admin/payment-requests?status=all -> full history, newest first
       POST /admin/payment-requests/:id/approve -> grants package, marks 'approved'
       POST /admin/payment-requests/:id/reject  -> marks 'rejected'
  Both approve/reject 409 if the request was already decided - irreversible
  once applied, so every action here goes through a confirm step.
-->
<script setup>
import { showConfirm } from '../../confirm'
import { ref, onMounted } from 'vue'
import { api, ApiError } from '../../api'

const loading = ref(true)
const error = ref('')
const requests = ref([])
const showAll = ref(false)

const confirming = ref(null) // { id, action }
const actionError = ref('')
const actionBusy = ref(false)

const packageLabels = {
  none: 'Chưa đăng ký',
  trial: 'Dùng thử 30 ngày',
  '1m': '1 tháng',
  '3m': '3 tháng',
  '6m': '6 tháng',
  '12m': '12 tháng',
}

const statusLabels = {
  pending: 'Chờ duyệt',
  approved: 'Đã duyệt',
  rejected: 'Đã từ chối',
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    const res = await api.get(`/admin/payment-requests${showAll.value ? '?status=all' : ''}`)
    requests.value = res.requests
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải danh sách yêu cầu'
  } finally {
    loading.value = false
  }
}

// Approve / reject always go through the centred confirm box first.
async function askConfirm(id, action) {
  actionError.value = ''
  const approve = action === 'approve'
  const ok = await showConfirm({
    title: approve ? 'Duyệt thanh toán' : 'Từ chối thanh toán',
    message: approve ? 'Xác nhận duyệt yêu cầu thanh toán này?' : 'Xác nhận từ chối yêu cầu thanh toán này?',
    confirmText: approve ? 'Duyệt' : 'Từ chối',
    danger: !approve,
  })
  if (!ok) return
  confirming.value = { id, action }
  await runAction()
}

async function runAction() {
  if (!confirming.value) return
  const { id, action } = confirming.value
  actionBusy.value = true
  actionError.value = ''
  try {
    await api.post(`/admin/payment-requests/${id}/${action}`)
    confirming.value = null
    await load()
  } catch (err) {
    actionError.value = err instanceof ApiError ? err.message : 'Không thể xử lý yêu cầu'
  } finally {
    actionBusy.value = false
  }
}

function formatMoney(v) {
  return Number(v).toLocaleString('vi-VN') + ' đ'
}

function toggleAll() {
  showAll.value = !showAll.value
  load()
}

onMounted(load)
</script>

<template>
  <div class="page">
    <div style="display: flex; justify-content: space-between; align-items: flex-end; flex-wrap: wrap; gap: 12px">
      <div>
        <h1 class="page-title">Yêu cầu thanh toán</h1>
        <p class="page-subtitle" style="margin-bottom: 0">
          {{ showAll ? 'Toàn bộ lịch sử' : 'Đang chờ duyệt' }}
        </p>
      </div>
      <button class="btn btn-secondary btn-sm" @click="toggleAll">
        {{ showAll ? 'Chỉ xem đang chờ' : 'Xem toàn bộ lịch sử' }}
      </button>
    </div>

    <div v-if="error" class="alert alert-error" style="margin-top: 16px">{{ error }}</div>
    <div v-if="actionError" class="alert alert-error">{{ actionError }}</div>

    <div class="card" style="padding: 0; overflow-x: auto; margin-top: 16px">
      <table class="table stack-table">
        <thead>
          <tr>
            <th>Khách hàng</th>
            <th>Gói</th>
            <th>Số tiền</th>
            <th>Trạng thái</th>
            <th>Thời gian</th>
            <th v-if="!showAll">Thao tác</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading">
            <td :colspan="showAll ? 5 : 6">Đang tải...</td>
          </tr>
          <tr v-else-if="requests.length === 0">
            <td :colspan="showAll ? 5 : 6">Không có yêu cầu nào</td>
          </tr>
          <tr v-for="r in requests" :key="r.id">
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
            </td>
            <td data-label="Thời gian">{{ new Date(r.createdAt).toLocaleString('vi-VN') }}</td>
            <td v-if="!showAll" data-label="Thao tác">
              <div style="display: flex; gap: 6px">
                <button class="btn btn-primary btn-sm" :disabled="actionBusy" @click="askConfirm(r.id, 'approve')">Duyệt</button>
                <button class="btn btn-danger btn-sm" :disabled="actionBusy" @click="askConfirm(r.id, 'reject')">Từ chối</button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
