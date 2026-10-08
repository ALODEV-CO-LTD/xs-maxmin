<!--
  /admin/messages/:userId - one customer's message thread, admin can reply.
  API: GET /admin/messages/:userId  -> { messages: [{ id, sender, content, createdAt }] }
       POST /admin/messages/:userId { content } -> the created message (sender 'admin')
-->
<script setup>
import AppIcon from '../../components/AppIcon.vue'
import { computed, ref, onBeforeUnmount, onMounted, watch } from 'vue'
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

// newest on top (same as the customer's popover and Bạn bè)
const ordered = computed(() => [...messages.value].reverse())
function timeLabel(iso) {
  const d = new Date(iso)
  return isNaN(d) ? '' : d.toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit', year: 'numeric' })
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

// Safety net when the push channel is blocked: refresh quietly every 8 s while the page is open.
let timer = null
onMounted(() => {
  notify.clear(`support:${userId}`)
  load()
  timer = setInterval(() => {
    if (!document.hidden) load({ quiet: true })
  }, 8000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <div class="page">
    <h1 class="page-title">Cuộc trò chuyện</h1>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="loading">Đang tải...</div>

    <template v-else>
      <section class="chat">
        <div class="thread" role="log" aria-label="Tin nhắn, mới nhất ở trên">
          <p v-if="messages.length === 0" class="empty">Chưa có tin nhắn nào</p>
          <div
            v-for="m in ordered"
            :key="m.id"
            class="msg"
            :class="m.sender === 'admin' ? 'msg-admin' : 'msg-user'"
          >
            <div class="msg-bubble">
              <span v-if="m.content" class="msg-text">{{ m.content }}</span>
              <MessageAttachment v-if="m.attachment" :att="m.attachment" :path="`/admin/messages/${userId}/attachment/${m.id}`" />
            </div>
            <time class="msg-time">{{ m.sender === 'admin' ? 'Admin · ' : 'Khách · ' }}{{ timeLabel(m.createdAt) }}</time>
          </div>
        </div>

        <div class="composer">
          <p v-if="sendError" class="alert alert-error">{{ sendError }}</p>
          <AttachmentPreview v-if="attachment" :file="attachment" @remove="attachment = null" />
          <form class="reply-row" @submit.prevent="send">
            <ChatAttachButtons :disabled="sending" @pick="(f) => { attachment = f; sendError = '' }" @error="(m) => (sendError = m)" />
            <input v-model="draft" type="text" placeholder="Nhập phản hồi..." :disabled="sending" aria-label="Nội dung phản hồi" />
            <button class="btn btn-primary" type="submit" :disabled="sending || (!draft.trim() && !attachment)">Gửi</button>
          </form>
        </div>
      </section>
    </template>
  </div>
</template>

<style scoped>
.chat {
  display: flex;
  flex-direction: column;
  max-width: 760px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  overflow: hidden;
}
.thread {
  display: flex;
  flex-direction: column;
  gap: 12px;
  height: clamp(320px, calc(100vh - 300px), 640px);
  padding: 16px;
  overflow-y: auto;
  overscroll-behavior: contain;
}
.empty {
  margin: auto;
  color: var(--text-secondary);
}
.msg {
  display: flex;
  flex-direction: column;
  gap: 3px;
  max-width: min(78%, 520px);
}
.msg-user {
  align-self: flex-start;
}
.msg-admin {
  align-self: flex-end;
  align-items: flex-end;
}
.msg-bubble {
  padding: 9px 13px;
  font-size: 15px;
  line-height: 1.45;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 14px 14px 14px 4px;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.msg-admin .msg-bubble {
  background: color-mix(in srgb, var(--primary) 14%, var(--card));
  border-color: color-mix(in srgb, var(--primary) 30%, var(--border));
  border-radius: 14px 14px 4px 14px;
}
.msg-time {
  padding: 0 4px;
  font-size: 12px;
  color: var(--text-secondary);
}
.composer {
  padding: 12px;
  border-top: 1px solid var(--border);
}
.composer .alert {
  margin: 0 0 8px;
}
.reply-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.reply-row input {
  flex: 1 1 0;
  min-width: 0; /* lets the box shrink so "Gửi" stays on screen on phones */
  height: 44px;
  padding: 0 14px;
  font: inherit;
  font-size: 15px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.reply-row input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.reply-row .btn {
  flex: none;
  min-height: 44px;
  padding: 0 20px;
}
</style>
