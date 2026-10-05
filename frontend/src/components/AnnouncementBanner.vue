<!--
  Banner for admin notices (A12/A16): maintenance mode (not dismissable while
  it is on) and announcements (maintenance / policy change / info) that the
  user can close for the current session. GET /announcements, refreshed every
  5 minutes; silently ignored while offline.
-->
<script setup>
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { api } from '../api'

const maintenance = ref({ enabled: false, message: '' })
const announcements = ref([])
const dismissed = ref(new Set())
let timer = null

try {
  dismissed.value = new Set(JSON.parse(sessionStorage.getItem('xoso_dismissed_notices') || '[]'))
} catch {
  /* ignore */
}

async function load() {
  try {
    const data = await api.get('/announcements')
    maintenance.value = data.maintenance || { enabled: false, message: '' }
    announcements.value = data.announcements || []
  } catch {
    /* offline or not allowed - keep what we have */
  }
}

const visible = computed(() => announcements.value.filter((a) => !dismissed.value.has(a.id)))

function dismiss(id) {
  dismissed.value = new Set([...dismissed.value, id])
  try {
    sessionStorage.setItem('xoso_dismissed_notices', JSON.stringify([...dismissed.value]))
  } catch {
    /* ignore */
  }
}

const KIND_LABEL = { maintenance: 'Bảo trì', policy: 'Chính sách', info: 'Thông báo' }

onMounted(() => {
  load()
  timer = setInterval(load, 5 * 60 * 1000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <div v-if="maintenance.enabled || visible.length" class="notices">
    <div v-if="maintenance.enabled" class="alert alert-warning notice" role="status">
      <div class="notice-text">
        <strong>Hệ thống đang bảo trì.</strong>
        {{ maintenance.message || 'Một số chức năng có thể tạm thời không hoạt động.' }}
      </div>
    </div>
    <div v-for="a in visible" :key="a.id" class="alert notice" :class="a.kind === 'maintenance' ? 'alert-warning' : 'alert-success'" role="status">
      <div class="notice-text">
        <strong>{{ KIND_LABEL[a.kind] || 'Thông báo' }}: {{ a.title }}</strong>
        <div v-if="a.body" class="notice-body">{{ a.body }}</div>
      </div>
      <button type="button" class="notice-close" aria-label="Ẩn thông báo" @click="dismiss(a.id)">×</button>
    </div>
  </div>
</template>

<style scoped>
.notices {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 12px 16px 0;
}
.notice {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin: 0;
}
.notice-body {
  margin-top: 2px;
  white-space: pre-line;
}
.notice-close {
  flex: none;
  width: 44px;
  height: 44px;
  margin: -12px -12px -12px 0;
  font-size: 24px;
  line-height: 1;
  color: inherit;
  background: transparent;
  border: 0;
  cursor: pointer;
}
</style>
