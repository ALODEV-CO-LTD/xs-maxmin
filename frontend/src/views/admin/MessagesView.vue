<!--
  /admin/messages - list of customers who have messaged admin (via the
  "Bạn bè" chat, same as everyone else's direct messages - admin's replies
  land in the same thread the customer already sees under their own "Bạn
  bè" tab, so there's no separate inbox to keep in sync). Click through to
  /admin/messages/:userId for the thread.
  API: GET /admin/messages -> { conversations: [{ userId, userName, avatar, lastMessage, lastMessageAt, unreadCount }] }
-->
<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { api, ApiError } from '../../api'

const router = useRouter()
const loading = ref(true)
const error = ref('')
const conversations = ref([])

async function load() {
  loading.value = true
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

function openThread(userId) {
  router.push({ name: 'admin-messages-thread', params: { userId } })
}

onMounted(load)
</script>

<template>
  <div class="page">
    <h1 class="page-title">Phản hồi khách hàng</h1>
    <p class="page-subtitle">Khách hàng đã nhắn tin cho bạn, mới nhất trước</p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="loading">Đang tải...</div>
    <div v-else-if="conversations.length === 0" class="card">Chưa có ai nhắn tin cho bạn</div>

    <div v-else class="list">
      <div v-for="c in conversations" :key="c.userId" class="card conv-row" @click="openThread(c.userId)">
        <div class="avatar">{{ (c.userName || '?').charAt(0).toUpperCase() }}</div>
        <div class="conv-body">
          <div class="conv-top">
            <strong>{{ c.userName }}</strong>
            <span class="conv-time">{{ c.lastMessageAt ? new Date(c.lastMessageAt).toLocaleString('vi-VN') : '' }}</span>
          </div>
          <div class="conv-last">{{ c.lastMessage }}</div>
        </div>
        <span v-if="c.unreadCount > 0" class="chip chip-brand">{{ c.unreadCount }}</span>
      </div>
    </div>
  </div>
</template>

<style scoped>
.list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.conv-row {
  display: flex;
  align-items: center;
  gap: 12px;
  cursor: pointer;
}

.avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: var(--accent-soft);
  color: var(--accent-strong);
  display: flex;
  align-items: center;
  justify-content: center;
  font-weight: 700;
  flex-shrink: 0;
}

.conv-body {
  flex: 1;
  min-width: 0;
}

.conv-top {
  display: flex;
  justify-content: space-between;
  gap: 8px;
}

.conv-time {
  font-size: 12px;
  color: var(--muted);
  white-space: nowrap;
}

.conv-last {
  color: var(--muted);
  font-size: 13px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
