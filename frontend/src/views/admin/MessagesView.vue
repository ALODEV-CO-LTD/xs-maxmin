<!--
  /admin/messages and /admin/messages/:userId - admin inbox, two columns:
  customers on the left (search + "Chưa trả lời" filter), the selected customer's
  thread on the right. Below 860px it collapses to one column: the list, or the
  thread with a back arrow once a customer is chosen. Both routes render this view;
  the selected customer is the :userId param.
  API: GET /admin/messages -> { conversations: [{ userId, userName, username, packageType,
       packageExpiresAt, awaitingReply, lastMessage, lastMessageAt }] }
-->
<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useNotifyStore } from '../../stores/notify'
import { api, ApiError } from '../../api'
import AdminChatPane from '../../components/AdminChatPane.vue'

const route = useRoute()
const router = useRouter()
const notify = useNotifyStore()

const loading = ref(true)
const error = ref('')
const conversations = ref([])
const query = ref('')
const onlyAwaiting = ref(false)

const selectedId = computed(() => (route.params.userId ? String(route.params.userId) : ''))
const selected = computed(() => conversations.value.find((c) => c.userId === selectedId.value) || null)

const packageLabels = {
  none: 'Chưa đăng ký',
  trial: 'Dùng thử',
  '1m': 'Gói 1 tháng',
  '3m': 'Gói 3 tháng',
  '6m': 'Gói 6 tháng',
  '12m': 'Gói 12 tháng',
}

function noAccents(s) {
  return String(s || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D')
    .toLowerCase()
}

const awaitingCount = computed(() => conversations.value.filter((c) => c.awaitingReply).length)
const filtered = computed(() => {
  const q = noAccents(query.value.trim())
  return conversations.value.filter((c) => {
    if (onlyAwaiting.value && !c.awaitingReply) return false
    if (!q) return true
    return noAccents(c.userName).includes(q) || noAccents(c.username).includes(q)
  })
})

function shortTime(iso) {
  const d = new Date(iso)
  if (!iso || isNaN(d)) return ''
  const now = new Date()
  const startOf = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
  const days = Math.round((startOf(now) - startOf(d)) / 86400000)
  if (days === 0) return d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })
  if (days === 1) return 'Hôm qua'
  return d.toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit' })
}

function expiryLabel(iso) {
  const d = new Date(iso)
  return !iso || isNaN(d) ? '' : d.toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' })
}

const subtitle = computed(() => {
  const c = selected.value
  if (!c) return ''
  const parts = []
  if (c.username) parts.push(`@${c.username}`)
  if (c.packageType) parts.push(packageLabels[c.packageType] || c.packageType)
  if (c.packageExpiresAt) parts.push(`hết hạn ${expiryLabel(c.packageExpiresAt)}`)
  return parts.join(' · ')
})

async function load({ quiet = false } = {}) {
  if (!quiet) loading.value = true
  error.value = ''
  try {
    const res = await api.get('/admin/messages')
    conversations.value = res.conversations
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải danh sách phản hồi'
  } finally {
    loading.value = false
  }
}

function open(userId) {
  if (userId === selectedId.value) return
  router.push({ name: 'admin-messages-thread', params: { userId } })
}
function backToList() {
  router.push({ name: 'admin-messages' })
}

// A customer just wrote to Admin: refresh the list (pushed over the WebSocket).
watch(
  () => notify.incomingTick,
  () => {
    if (notify.lastIncoming?.source === 'support') load({ quiet: true })
  },
)

onMounted(() => {
  load()
  // Safety net when the push channel is blocked.
  setInterval(() => {
    if (!document.hidden) load({ quiet: true })
  }, 15000)
})
</script>

<template>
  <div class="inbox-wrap">
    <div class="inbox" :class="{ 'has-selection': selectedId }">
      <aside class="list-col" aria-label="Danh sách khách hàng">
        <header class="list-head">
          <h1 class="list-title">Phản hồi khách hàng</h1>
          <input v-model="query" type="search" class="search" placeholder="Tìm tên hoặc tên đăng nhập" aria-label="Tìm khách hàng" />
          <div class="tabs" role="tablist">
            <button type="button" role="tab" class="tab" :class="{ on: !onlyAwaiting }" :aria-selected="!onlyAwaiting" @click="onlyAwaiting = false">
              Tất cả <span class="count">{{ conversations.length }}</span>
            </button>
            <button type="button" role="tab" class="tab" :class="{ on: onlyAwaiting }" :aria-selected="onlyAwaiting" @click="onlyAwaiting = true">
              Chưa trả lời <span v-if="awaitingCount" class="count count-warn">{{ awaitingCount }}</span>
            </button>
          </div>
        </header>

        <div class="list" role="list">
          <div v-if="error" class="alert alert-error">{{ error }}</div>
          <p v-if="loading" class="hint">Đang tải...</p>
          <p v-else-if="conversations.length === 0" class="hint">Chưa có ai nhắn tin cho bạn</p>
          <p v-else-if="filtered.length === 0" class="hint">Không có cuộc trò chuyện phù hợp</p>
          <button
            v-for="c in filtered"
            :key="c.userId"
            type="button"
            class="conv"
            :class="{ active: c.userId === selectedId }"
            role="listitem"
            @click="open(c.userId)"
          >
            <span class="avatar">{{ (c.userName || '?').charAt(0).toUpperCase() }}</span>
            <span class="conv-body">
              <span class="conv-top">
                <strong class="conv-name">{{ c.userName }}</strong>
                <span class="conv-time">{{ shortTime(c.lastMessageAt) }}</span>
              </span>
              <span class="conv-last">
                <span class="conv-text">{{ c.lastMessage }}</span>
                <span v-if="c.awaitingReply" class="dot" title="Chưa trả lời" aria-label="Chưa trả lời"></span>
              </span>
            </span>
          </button>
        </div>
      </aside>

      <section class="chat-col" aria-label="Cuộc trò chuyện">
        <template v-if="selectedId">
          <header class="chat-head">
            <button type="button" class="back" aria-label="Quay lại danh sách" @click="backToList">‹</button>
            <span class="avatar">{{ (selected?.userName || '?').charAt(0).toUpperCase() }}</span>
            <div class="who">
              <strong class="who-name">{{ selected?.userName || 'Khách hàng' }}</strong>
              <span v-if="subtitle" class="who-sub">{{ subtitle }}</span>
            </div>
          </header>
          <AdminChatPane :key="selectedId" :user-id="selectedId" @sent="load({ quiet: true })" />
        </template>
        <div v-else class="placeholder">Chọn một khách hàng ở bên trái để xem và trả lời tin nhắn</div>
      </section>
    </div>
  </div>
</template>

<style scoped>
.inbox-wrap {
  padding: 16px;
}
.inbox {
  display: grid;
  grid-template-columns: 340px minmax(0, 1fr);
  height: calc(100dvh - 104px);
  min-height: 480px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  overflow: hidden;
}

/* ---- left column ---- */
.list-col {
  display: flex;
  flex-direction: column;
  min-height: 0;
  border-right: 1px solid var(--border);
}
.list-head {
  padding: 16px 16px 8px;
  border-bottom: 1px solid var(--border);
}
.list-title {
  font-size: 18px;
  margin: 0 0 10px;
}
.search {
  width: 100%;
  height: 40px;
  padding: 0 12px;
  font: inherit;
  font-size: 14px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.search:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.tabs {
  display: flex;
  gap: 4px;
  margin-top: 10px;
}
.tab {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 10px;
  font: inherit;
  font-size: 13px;
  font-weight: 600;
  color: var(--text-secondary);
  background: none;
  border: 0;
  border-bottom: 2px solid transparent;
  cursor: pointer;
}
.tab.on {
  color: var(--text-primary);
  border-bottom-color: var(--primary);
}
.count {
  min-width: 20px;
  padding: 0 6px;
  font-size: 12px;
  line-height: 20px;
  text-align: center;
  color: var(--text-secondary);
  background: var(--surface);
  border-radius: var(--radius-pill);
}
.count-warn {
  color: var(--warning-text);
  background: var(--warning-soft);
}
.list {
  flex: 1;
  min-height: 0;
  overflow-y: auto;
  padding: 6px;
}
.hint {
  padding: 24px 12px;
  text-align: center;
  color: var(--text-secondary);
  font-size: 14px;
}
.conv {
  display: flex;
  align-items: center;
  gap: 12px;
  width: 100%;
  padding: 10px;
  font: inherit;
  text-align: left;
  color: var(--text-primary);
  background: none;
  border: 0;
  border-radius: 12px;
  cursor: pointer;
}
.conv:hover {
  background: var(--surface);
}
.conv.active {
  background: var(--primary-soft);
}
.conv:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 50%, transparent);
  outline-offset: -2px;
}
.avatar {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  flex: none;
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: var(--primary-soft);
  color: var(--link);
  font-weight: 700;
}
.conv.active .avatar {
  background: var(--card);
}
.conv-body {
  display: flex;
  flex-direction: column;
  gap: 2px;
  flex: 1;
  min-width: 0;
}
.conv-top,
.conv-last {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.conv-name {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 15px;
}
.conv-time {
  flex: none;
  font-size: 12px;
  color: var(--text-secondary);
}
.conv-text {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 14px;
  color: var(--text-secondary);
}
.dot {
  flex: none;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  background: var(--warning);
}

/* ---- right column ---- */
.chat-col {
  display: flex;
  flex-direction: column;
  min-width: 0;
  min-height: 0;
}
.chat-head {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  border-bottom: 1px solid var(--border);
}
.who {
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.who-name {
  font-size: 16px;
}
.who-sub {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  font-size: 13px;
  color: var(--text-secondary);
}
.back {
  display: none;
  width: 40px;
  height: 40px;
  flex: none;
  font-size: 28px;
  line-height: 1;
  color: var(--text-primary);
  background: var(--surface);
  border: 0;
  border-radius: 10px;
  cursor: pointer;
}
.placeholder {
  margin: auto;
  padding: 24px;
  text-align: center;
  color: var(--text-secondary);
}

/* ---- phones / small tablets: one column at a time ---- */
@media (max-width: 859px) {
  .inbox-wrap {
    padding: 8px;
  }
  .inbox {
    grid-template-columns: minmax(0, 1fr);
    height: calc(100dvh - 88px);
  }
  .inbox.has-selection .list-col,
  .inbox:not(.has-selection) .chat-col {
    display: none;
  }
  .list-col {
    border-right: 0;
  }
  .back {
    display: inline-flex;
    align-items: center;
    justify-content: center;
  }
}
</style>
