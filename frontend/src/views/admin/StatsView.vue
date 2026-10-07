<!--
  /admin/stats - aggregate subscriber counts.
  API: GET /admin/stats -> { totalSubscribers, activeSubscribers, expiredSubscribers, byPackage: { wireValue: count } }
-->
<script setup>
import { ref, onMounted } from 'vue'
import { api, ApiError } from '../../api'

const loading = ref(true)
const error = ref('')
const stats = ref(null)

const packageLabels = {
  none: 'Chưa đăng ký',
  trial: 'Dùng thử 30 ngày',
  '1m': '1 tháng',
  '3m': '3 tháng',
  '6m': '6 tháng',
  '12m': '12 tháng',
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    stats.value = await api.get('/admin/stats')
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải thống kê'
  } finally {
    loading.value = false
  }
}

onMounted(load)
</script>

<template>
  <div class="page">
    <h1 class="page-title">Thống kê</h1>
    <p class="page-subtitle">Tổng quan số lượng khách hàng theo trạng thái và gói dịch vụ</p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="loading">Đang tải...</div>

    <template v-else-if="stats">
      <div class="tile-grid">
        <div class="card tile">
          <div class="tile-value">{{ stats.totalSubscribers }}</div>
          <div class="tile-label">Tổng khách hàng</div>
        </div>
        <div class="card tile tile-active">
          <div class="tile-value">{{ stats.activeSubscribers }}</div>
          <div class="tile-label">Đang hoạt động</div>
        </div>
        <div class="card tile tile-expired">
          <div class="tile-value">{{ stats.expiredSubscribers }}</div>
          <div class="tile-label">Đã hết hạn</div>
        </div>
      </div>

      <h2 class="section-title">Theo gói dịch vụ</h2>
      <div class="card table-card">
        <table class="table stats-table">
          <thead>
            <tr>
              <th>Gói</th>
              <th class="col-num">Số lượng</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(count, key) in stats.byPackage" :key="key">
              <td>{{ packageLabels[key] || key }}</td>
              <td class="col-num">{{ count }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>

<style scoped>
/* Spacing rhythm (8px grid): header 24 -> cards 32 -> section title 16 -> table */
.page {
  max-width: var(--page-max);
  padding: 32px 24px 96px;
}

.page-title {
  font-size: 28px;
  line-height: 1.2;
  margin-bottom: 8px;
}

.page-subtitle {
  font-size: 15px;
  line-height: 1.5;
  margin-bottom: 24px;
}

.page > .alert {
  font-size: 15px;
  border-radius: 12px;
  margin-bottom: 16px;
}

/* ---- Summary cards ---- */
.tile-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
}

.tile {
  display: flex;
  flex-direction: column;
  justify-content: center;
  gap: 8px;
  min-height: 112px;
  padding: 20px 24px;
  border-radius: 14px;
  text-align: left;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}

.tile:hover {
  border-color: var(--input-border);
  box-shadow: var(--shadow-md);
}

.tile-value {
  order: 1;
  font-family: var(--font-display);
  font-size: 36px;
  line-height: 1.1;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
}

.tile-label {
  order: 2;
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: var(--muted);
}

/* Small status dot + coloured number only; the card itself stays neutral */
.tile-active .tile-value {
  color: var(--success-text);
}
.tile-expired .tile-value {
  color: var(--warning-text);
}
.tile-active .tile-label::before,
.tile-expired .tile-label::before {
  content: '';
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex: none;
}
.tile-active .tile-label::before {
  background: var(--success);
}
.tile-expired .tile-label::before {
  background: var(--warning);
}

/* ---- Section + table ---- */
.section-title {
  margin: 32px 0 16px;
  font-size: 18px;
  line-height: 1.3;
  font-weight: 700;
}

.table-card {
  padding: 0;
  overflow-x: auto;
  border-radius: 14px;
}

.stats-table {
  font-size: 15px;
  min-width: 280px;
}

.stats-table th {
  padding: 12px 20px;
  font-size: 14px;
  font-weight: 700;
  letter-spacing: 0.05em;
  background: var(--surface);
  white-space: nowrap;
}

.stats-table td {
  padding: 14px 20px;
  vertical-align: middle;
}

.stats-table td:first-child {
  font-weight: 600;
}

.stats-table .col-num {
  text-align: right;
  width: 160px;
  font-variant-numeric: tabular-nums;
}

.stats-table td.col-num {
  font-weight: 700;
}

.stats-table tbody tr {
  transition: background 0.12s ease;
}

.stats-table tbody tr:hover {
  background: color-mix(in srgb, var(--primary) 8%, transparent);
}

/* ---- Responsive ---- */
@media (max-width: 960px) {
  .tile-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 640px) {
  .page {
    padding: 24px 16px 96px;
  }
  .page-title {
    font-size: 24px;
  }
  .tile-grid {
    grid-template-columns: 1fr;
  }
  .tile {
    min-height: 96px;
    padding: 16px 20px;
  }
  .tile-value {
    font-size: 32px;
  }
  .stats-table th,
  .stats-table td {
    padding-left: 16px;
    padding-right: 16px;
  }
}
</style>
