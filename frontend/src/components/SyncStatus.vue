<!--
  Connection / sync indicator for the top bar (Offline, Đang đồng bộ, n chờ
  đồng bộ) + the dialog that asks the user what to do when the same record
  was edited elsewhere while this device was offline (see src/offline.js).
-->
<script setup>
import { computed, ref } from 'vue'
import { betTypeLabel } from '../betTypes'
import { dismissFailure, flushQueue, resolveConflict, syncState } from '../offline'

const label = computed(() => {
  if (syncState.syncing) return 'Đang đồng bộ...'
  if (!syncState.online) return syncState.pending ? `Offline · ${syncState.pending} chờ đồng bộ` : 'Offline'
  if (syncState.pending) return `${syncState.pending} chờ đồng bộ`
  return ''
})
const kind = computed(() => (syncState.syncing ? 'syncing' : syncState.online ? 'pending' : 'offline'))

const conflict = computed(() => syncState.conflicts[0] || null)
const resolving = ref(false)
const resolveError = ref('')
const fields = [
  { key: 'customerName', label: 'Khách hàng' },
  { key: 'entryDate', label: 'Ngày' },
  { key: 'betType', label: 'Hạng mục' },
  { key: 'value', label: 'Số' },
  { key: 'score', label: 'Điểm vào' },
  { key: 'note', label: 'Ghi chú' },
]
function show(src, key) {
  const v = src?.[key]
  if (key === 'betType') return betTypeLabel(v || 'de')
  return v || '-'
}
// only the fields the user actually changed
const changedFields = computed(() => {
  if (!conflict.value) return fields
  const rows = fields.filter((f) => f.key in conflict.value.mine)
  return rows.length ? rows : fields
})

async function choose(choice) {
  resolving.value = true
  resolveError.value = ''
  try {
    await resolveConflict(conflict.value, choice)
  } catch (err) {
    resolveError.value = err.message || 'Không xử lý được xung đột'
  } finally {
    resolving.value = false
  }
}
</script>

<template>
  <button
    v-if="label"
    type="button"
    class="sync-chip"
    :class="`sync-${kind}`"
    :disabled="!syncState.online || syncState.syncing"
    :title="syncState.online ? 'Bấm để đồng bộ ngay' : 'Mất kết nối. Số liệu nhập sẽ được lưu trên máy và gửi lên khi có mạng'"
    role="status"
    @click="flushQueue"
  >
    <span class="sync-dot" aria-hidden="true"></span>{{ label }}
  </button>

  <Teleport to="body">
    <div v-if="syncState.failures.length" class="sync-failures" role="alert">
      <div v-for="f in syncState.failures" :key="f.id" class="sync-failure">
        <span>{{ f.message }}</span>
        <button type="button" class="btn btn-ghost btn-sm" @click="dismissFailure(f.id)">Đóng</button>
      </div>
    </div>

    <div v-if="conflict" class="sync-overlay">
      <div class="sync-box" role="dialog" aria-modal="true" aria-labelledby="sync-title">
        <h2 id="sync-title" class="sync-title">Số liệu đã được sửa ở nơi khác</h2>
        <p class="sync-text">
          Bản ghi này vừa được sửa ở thiết bị khác trong lúc bạn chỉnh sửa. Chọn bản bạn muốn giữ.
        </p>
        <div v-if="resolveError" class="alert alert-error">{{ resolveError }}</div>
        <table class="table sync-table">
          <thead>
            <tr><th></th><th>Bản của bạn</th><th>Bản trên máy chủ</th></tr>
          </thead>
          <tbody>
            <tr v-for="f in changedFields" :key="f.key">
              <td>{{ f.label }}</td>
              <td>{{ show(conflict.mine, f.key) }}</td>
              <td>{{ show(conflict.server, f.key) }}</td>
            </tr>
          </tbody>
        </table>
        <div class="sync-actions">
          <button type="button" class="btn btn-secondary" :disabled="resolving" @click="choose('server')">Dùng bản trên máy chủ</button>
          <button type="button" class="btn btn-primary" :disabled="resolving" @click="choose('mine')">Giữ bản của tôi</button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.sync-chip {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  min-height: 32px;
  padding: 0 12px;
  font-size: 13px;
  font-weight: 700;
  white-space: nowrap;
  border-radius: 999px;
  border: 1px solid var(--input-border);
  background: var(--surface);
  color: var(--text-primary);
  cursor: pointer;
}
.sync-chip:disabled {
  cursor: default;
}
.sync-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--muted);
}
.sync-offline .sync-dot {
  background: var(--danger);
}
.sync-syncing .sync-dot,
.sync-pending .sync-dot {
  background: var(--accent);
}
.sync-syncing .sync-dot {
  animation: sync-pulse 1s ease-in-out infinite;
}
@keyframes sync-pulse {
  50% {
    opacity: 0.25;
  }
}

.sync-failures {
  position: fixed;
  left: 12px;
  right: 12px;
  bottom: 76px;
  z-index: 60;
  display: flex;
  flex-direction: column;
  gap: 8px;
  max-width: 520px;
}
.sync-failure {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 14px;
  font-size: 14px;
  color: var(--text);
  background: var(--card);
  border: 1px solid var(--danger);
  border-radius: 12px;
  box-shadow: var(--shadow-lg);
}

.sync-overlay {
  position: fixed;
  inset: 0;
  z-index: 70;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  background: var(--overlay);
}
.sync-box {
  width: min(520px, 100%);
  max-height: 100%;
  overflow-y: auto;
  padding: 20px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 14px;
  box-shadow: var(--shadow-lg);
}
.sync-title {
  margin: 0 0 8px;
  font-size: 18px;
}
.sync-text {
  margin: 0 0 12px;
  color: var(--text-secondary);
  font-size: 14px;
}
.sync-table {
  width: 100%;
  margin-bottom: 16px;
  font-size: 14px;
}
.sync-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 8px;
}
</style>
