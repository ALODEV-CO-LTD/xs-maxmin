<!--
  Embedded in /admin/payment-requests (tab "Lịch sử gia hạn") - system-wide renewal/purchase history.
  API: GET /admin/renewals -> { renewals: [{ id, userName, avatar, type, packageType, amount, createdAt }] }
  Read-only (最新 200 rows, newest first - set server-side).
-->
<script setup>
import { ref, onMounted } from 'vue'
import { api, ApiError } from '../../api'
import { loadPackageLabels, packageLabel } from '../../packageLabels'

const loading = ref(true)
const error = ref('')
const renewals = ref([])

const typeLabels = {
  purchase: 'Mua mới',
  renew: 'Gia hạn',
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    const res = await api.get('/admin/renewals')
    renewals.value = res.renewals
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải danh sách gia hạn'
  } finally {
    loading.value = false
  }
}

function formatMoney(v) {
  return Number(v).toLocaleString('vi-VN') + ' đ'
}

onMounted(() => {
  loadPackageLabels(true)
  load()
})
</script>

<template>
  <div>
    <p class="page-subtitle">Lịch sử mua/gia hạn gói dịch vụ toàn hệ thống, gồm các yêu cầu đã được duyệt (tối đa 200 gần nhất)</p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>

    <div class="card" style="padding: 0; overflow-x: auto">
      <table class="table stack-table">
        <thead>
          <tr>
            <th>Khách hàng</th>
            <th>Loại</th>
            <th>Gói</th>
            <th>Số tiền</th>
            <th>Thời gian</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="loading">
            <td colspan="5">Đang tải...</td>
          </tr>
          <tr v-else-if="renewals.length === 0">
            <td colspan="5">Chưa có giao dịch nào</td>
          </tr>
          <tr v-for="r in renewals" :key="r.id">
            <td data-label="Khách hàng">{{ r.userName }}</td>
            <td data-label="Loại">
              <span class="chip" :class="r.type === 'renew' ? 'chip-brand' : ''">{{ typeLabels[r.type] || r.type }}</span>
            </td>
            <td data-label="Gói">{{ packageLabel(r.packageType) }}</td>
            <td data-label="Số tiền">{{ formatMoney(r.amount) }}</td>
            <td data-label="Thời gian">{{ new Date(r.createdAt).toLocaleString('vi-VN') }}</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
