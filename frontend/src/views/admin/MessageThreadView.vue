<!--
  /admin/messages/:userId - one customer's message thread, admin can reply.
  API: GET /admin/messages/:userId  -> { messages: [{ id, sender, content, createdAt }] }
       POST /admin/messages/:userId { content } -> the created message (sender 'admin')
-->
<script setup>
import AppIcon from '../../components/AppIcon.vue'
import { ref, onMounted, watch } from 'vue'
import { useNotifyStore } from '../../stores/notify'
import { useRoute, useRouter } from 'vue-router'
import { api, ApiError } from '../../api'
import ChatAttachButtons from '../../components/ChatAttachButtons.vue'
import AttachmentPreview from '../../components/AttachmentPreview.vue'
import MessageAttachment from '../../components/MessageAttachment.vue'
import { fileToPayload } from '../../attachments'

const route = useRoute()
const router = useRouter()
const userId = route.params.userId

const loading = ref(true)
const error = ref('')
const messages = ref([])
const draft = ref('')
const sending = ref(false)
const attachment = ref(null) // File waiting to be sent with the next reply
const sendError = ref('')

async function load({ quiet = false } = {}) {
  if (!quiet) loading.value = true
  error.value = ''
  try {
    const res = await api.get(`/admin/messages/${userId}`)
    messages.value = res.messages
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải cuộc trò chuyện'
  } finally {
    loading.value = false
  }
}

async function send() {
  const content = draft.value.trim()
  if (!content && !attachment.value) return
  sending.value = true
  sendError.value = ''
  try {
    const body = { content }
    if (attachment.value) body.attachment = await fileToPayload(attachment.value)
    const msg = await api.post(`/admin/messages/${userId}`, body)
    messages.value.push(msg)
    draft.value = ''
    attachment.value = null
  } catch (err) {
    sendError.value = err instanceof ApiError ? err.message : 'Không thể gửi tin nhắn'
  } finally {
    sending.value = false
  }
}

function goBack() {
  router.push({ name: 'admin-messages' })
}

const notify = useNotifyStore()
// The customer wrote again while this thread is open (pushed over the WebSocket).
watch(
  () => notify.incomingTick,
  () => {
    const m = notify.lastIncoming
    if (m?.source === 'support' && m.from === userId) {
      load({ quiet: true })
      notify.clear(`support:${userId}`)
    }
  },
)

onMounted(() => {
  notify.clear(`support:${userId}`)
  load()
})
</script>

<template>
  <div class="page">
    <h1 class="page-title">Cuộc trò chuyện</h1>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="loading">Đang tải...</div>

    <template v-else>
      <div class="card thread">
        <div v-if="messages.length === 0" class="empty">Chưa có tin nhắn nào</div>
        <div
          v-for="m in messages"
          :key="m.id"
          class="msg"
          :class="m.sender === 'admin' ? 'msg-admin' : 'msg-user'"
        >
          <div class="msg-bubble">
            <span v-if="m.content">{{ m.content }}</span>
            <MessageAttachment v-if="m.attachment" :att="m.attachment" :path="`/admin/messages/${userId}/attachment/${m.id}`" />
          </div>
          <div class="msg-time">{{ new Date(m.createdAt).toLocaleString('vi-VN') }}</div>
        </div>
      </div>

      <div v-if="sendError" class="alert alert-error">{{ sendError }}</div>

      <AttachmentPreview v-if="attachment" :file="attachment" @remove="attachment = null" />
      <form class="reply-row" @submit.prevent="send">
        <ChatAttachButtons :disabled="sending" @pick="(f) => { attachment = f; sendError = '' }" @error="(m) => (sendError = m)" />
        <input v-model="draft" type="text" placeholder="Nhập phản hồi..." :disabled="sending" />
        <button class="btn btn-primary" type="submit" :disabled="sending || (!draft.trim() && !attachment)">Gửi</button>
      </form>
    </template>
  </div>
</template>

<style scoped>
.thread {
  display: flex;
  flex-direction: column;
  gap: 12px;
  min-height: 200px;
}

.empty {
  color: var(--muted);
  text-align: center;
  padding: 24px 0;
}

.msg {
  display: flex;
  flex-direction: column;
  max-width: 70%;
}

.msg-user {
  align-self: flex-start;
}

.msg-admin {
  align-self: flex-end;
  align-items: flex-end;
}

.msg-bubble {
  padding: 10px 14px;
  border-radius: var(--radius-md);
  background: var(--surface-2);
}

.msg-admin .msg-bubble {
  background: var(--accent-soft);
  color: var(--accent-strong);
}

.msg-time {
  font-size: 11px;
  color: var(--muted);
  margin-top: 4px;
}

.reply-row {
  display: flex;
  gap: 8px;
  margin-top: 16px;
}

.reply-row input {
  flex: 1;
  font-family: var(--font-body);
  font-size: 15px;
  color: var(--text);
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 12px 14px;
}

.reply-row input:focus {
  outline: 2px solid var(--focus);
  outline-offset: 1px;
  border-color: var(--focus);
}

.reply-row {
  align-items: center;
  gap: 8px;
}
</style>
