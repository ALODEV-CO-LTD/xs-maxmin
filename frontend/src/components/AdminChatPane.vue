<!--
  One customer's support thread inside the admin inbox (views/admin/MessagesView.vue).
  Oldest message on top, newest at the bottom, grouped by day; the composer stays pinned.
  API: GET /admin/messages/:userId  -> { messages: [{ id, sender, content, createdAt, attachment }] }
       POST /admin/messages/:userId { content, attachment? } -> the created message
-->
<script setup>
import AppButton from './AppButton.vue'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useNotifyStore } from '../stores/notify'
import { api, ApiError } from '../api'
import ChatAttachButtons from './ChatAttachButtons.vue'
import AttachmentPreview from './AttachmentPreview.vue'
import MessageAttachment from './MessageAttachment.vue'
import { fileToPayload } from '../attachments'

const props = defineProps({
  userId: { type: String, required: true },
})
const emit = defineEmits(['sent'])

const loading = ref(true)
const error = ref('')
const messages = ref([])
const draft = ref('')
const sending = ref(false)
const attachment = ref(null)
const sendError = ref('')
const threadEl = ref(null)

async function scrollToEnd() {
  await nextTick()
  if (threadEl.value) threadEl.value.scrollTop = threadEl.value.scrollHeight
}

async function load({ quiet = false } = {}) {
  const id = props.userId
  if (!quiet) loading.value = true
  error.value = ''
  try {
    const res = await api.get(`/admin/messages/${id}`)
    if (id !== props.userId) return // user switched conversation meanwhile
    const grew = res.messages.length !== messages.value.length
    messages.value = res.messages
    if (!quiet || grew) scrollToEnd()
  } catch (err) {
    if (id === props.userId) error.value = err instanceof ApiError ? err.message : 'Không thể tải cuộc trò chuyện'
  } finally {
    if (id === props.userId) loading.value = false
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
    const msg = await api.post(`/admin/messages/${props.userId}`, body)
    messages.value.push(msg)
    draft.value = ''
    attachment.value = null
    scrollToEnd()
    emit('sent')
  } catch (err) {
    sendError.value = err instanceof ApiError ? err.message : 'Không thể gửi tin nhắn'
  } finally {
    sending.value = false
  }
}

function dayKey(iso) {
  const d = new Date(iso)
  return isNaN(d) ? '' : `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`
}
function dayLabel(iso) {
  const d = new Date(iso)
  if (isNaN(d)) return ''
  const today = new Date()
  const yesterday = new Date()
  yesterday.setDate(today.getDate() - 1)
  if (dayKey(iso) === dayKey(today)) return 'Hôm nay'
  if (dayKey(iso) === dayKey(yesterday)) return 'Hôm qua'
  return d.toLocaleDateString('vi-VN', { day: '2-digit', month: '2-digit', year: 'numeric' })
}
function timeLabel(iso) {
  const d = new Date(iso)
  return isNaN(d) ? '' : d.toLocaleTimeString('vi-VN', { hour: '2-digit', minute: '2-digit' })
}

// Flat list with a date divider before the first message of each day.
const items = computed(() => {
  const out = []
  let last = ''
  for (const m of messages.value) {
    const k = dayKey(m.createdAt)
    if (k !== last) {
      out.push({ divider: true, id: `d-${k}`, label: dayLabel(m.createdAt) })
      last = k
    }
    out.push(m)
  }
  return out
})

const notify = useNotifyStore()
watch(
  () => notify.incomingTick,
  () => {
    const m = notify.lastIncoming
    if (m?.source === 'support' && m.from === props.userId) {
      load({ quiet: true })
      notify.clear(`support:${props.userId}`)
    }
  },
)

watch(
  () => props.userId,
  () => {
    messages.value = []
    draft.value = ''
    attachment.value = null
    sendError.value = ''
    notify.clear(`support:${props.userId}`)
    load()
  },
)

// Safety net when the push channel is blocked: refresh quietly every 8 s while visible.
let timer = null
onMounted(() => {
  notify.clear(`support:${props.userId}`)
  load()
  timer = setInterval(() => {
    if (!document.hidden) load({ quiet: true })
  }, 8000)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <div class="pane">
    <div ref="threadEl" class="thread" role="log" aria-label="Tin nhắn, mới nhất ở dưới">
      <div v-if="error" class="alert alert-error">{{ error }}</div>
      <p v-if="loading" class="empty">Đang tải...</p>
      <p v-else-if="messages.length === 0" class="empty">Chưa có tin nhắn nào</p>
      <template v-for="m in items" :key="m.id">
        <div v-if="m.divider" class="day"><span>{{ m.label }}</span></div>
        <div v-else class="msg" :class="m.sender === 'admin' ? 'msg-admin' : 'msg-user'">
          <div class="msg-bubble">
            <span v-if="m.content" class="msg-text">{{ m.content }}</span>
            <MessageAttachment v-if="m.attachment" :att="m.attachment" :path="`/admin/messages/${userId}/attachment/${m.id}`" />
          </div>
          <time class="msg-time">{{ timeLabel(m.createdAt) }}</time>
        </div>
      </template>
    </div>

    <div class="composer">
      <p v-if="sendError" class="alert alert-error">{{ sendError }}</p>
      <AttachmentPreview v-if="attachment" :file="attachment" @remove="attachment = null" />
      <form class="reply-row" @submit.prevent="send">
        <ChatAttachButtons :disabled="sending" @pick="(f) => { attachment = f; sendError = '' }" @error="(m) => (sendError = m)" />
        <input v-model="draft" type="text" placeholder="Nhập phản hồi..." :disabled="sending" aria-label="Nội dung phản hồi" />
        <AppButton variant="primary" type="submit" :disabled="sending || (!draft.trim() && !attachment)">Gửi</AppButton>
      </form>
    </div>
  </div>
</template>

<style scoped>
.pane {
  display: flex;
  flex-direction: column;
  flex: 1;
  min-height: 0;
}
.thread {
  display: flex;
  flex-direction: column;
  gap: 8px;
  flex: 1;
  min-height: 0;
  padding: 16px;
  overflow-y: auto;
  overscroll-behavior: contain;
}
.empty {
  margin: auto;
  color: var(--text-secondary);
}
.day {
  align-self: center;
  margin: 8px 0 4px;
  padding: 3px 12px;
  font-size: 12px;
  font-weight: 600;
  color: var(--text-secondary);
  background: var(--surface);
  border-radius: var(--radius-pill);
}
.msg {
  display: flex;
  flex-direction: column;
  gap: 2px;
  max-width: min(72%, 560px);
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
  min-width: 0;
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
