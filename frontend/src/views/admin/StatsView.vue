<!--
  /admin/stats - aggregate subscriber counts.
  API: GET /admin/stats -> { totalSubscribers, activeSubscribers, expiredSubscribers, byPackage: { wireValue: count } }
-->
<script setup>
import { ref, computed, onMounted } from 'vue'
import { api, ApiError } from '../../api'
import StatsChart from '../../components/StatsChart.vue'
import { loadPackageLabels, packageLabel } from '../../packageLabels'

const loading = ref(true)
const error = ref('')
const stats = ref(null)

// Two charts over the same range: revenue (bars) and new accounts (line).
const RANGES = [
  { key: 'day', label: 'Ngày', span: '30 ngày gần nhất' },
  { key: 'week', label: 'Tuần', span: '12 tuần gần nhất' },
  { key: 'month', label: 'Tháng', span: '12 tháng gần nhất' },
  { key: 'year', label: 'Năm', span: '5 năm gần nhất' },
]
const range = ref('day')
const rangeSpan = computed(() => RANGES.find((r) => r.key === range.value)?.span || '')
const hasRevenue = computed(() => !!stats.value?.canRevenue)
const revenuePoints = computed(() => (stats.value?.series || []).map((d) => ({ date: d.date, value: d.revenue || 0 })))
const userPoints = computed(() => (stats.value?.series || []).map((d) => ({ date: d.date, value: d.newUsers })))

async function load(silent = false) {
  if (!silent) loading.value = true
  error.value = ''
  try {
    stats.value = await api.get(`/admin/stats?range=${range.value}`)
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải thống kê'
  } finally {
    loading.value = false
  }
}

function setRange(r) {
  range.value = r
  load(true)
}

onMounted(() => {
  loadPackageLabels(true)
  load()
})
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

      <div class="chart-head">
        <h2 class="section-title chart-title">Thu nhập và người dùng mới</h2>
        <div class="range-tabs" role="tablist" aria-label="Khoảng thời gian">
          <button
            v-for="r in RANGES"
            :key="r.key"
            type="button"
            role="tab"
            class="range-btn"
            :class="{ active: range === r.key }"
            :aria-selected="range === r.key"
            @click="setRange(r.key)"
          >
            {{ r.label }}
          </button>
        </div>
      </div>
      <p class="chart-span">{{ rangeSpan }}</p>
      <div class="chart-grid">
        <StatsChart v-if="hasRevenue" :points="revenuePoints" kind="bar" color="var(--primary)" label="Thu nhập" money :unit="range" />
        <StatsChart :points="userPoints" kind="line" color="var(--success)" label="Người dùng mới" :unit="range" />
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
              <td>{{ packageLabel(key) }}</td>
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

/* ---- Charts ---- */
.chart-head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 8px 16px;
  margin: 32px 0 16px;
}
.chart-title {
  margin: 0;
}
.chart-span {
  margin: 0 0 8px;
  font-size: 12px;
  color: var(--muted);
}
.range-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.range-btn {
  min-height: 34px;
  padding: 0 12px;
  font: inherit;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-secondary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  cursor: pointer;
}
.range-btn:hover {
  border-color: var(--primary);
}
.range-btn.active {
  color: var(--on-primary);
  background: var(--primary);
  border-color: var(--primary);
}
.chart-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(min(100%, 380px), 1fr));
  gap: 16px;
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
