<!--
  /feedback - the customer's thread with Admin support. This is the ONLY place
  a customer messages Admin: Admin is deliberately not in the Bạn bè list (no
  chat, no calls there), so questions and problems come through here and
  Admin answers from the admin "Phản hồi" page (admin/MessagesView.vue) - both
  sides read the same thread.

  API: GET /me/messages -> { messages: [{ id, sender: 'user'|'admin', content, createdAt }] }
       POST /me/messages { content }
-->
<script setup>
import { nextTick, onBeforeUnmount, onMounted, ref } from 'vue'
import { api } from '../api'
import ChatAttachButtons from '../components/ChatAttachButtons.vue'
import AttachmentPreview from '../components/AttachmentPreview.vue'
import MessageAttachment from '../components/MessageAttachment.vue'
import { fileToPayload } from '../attachments'

const messages = ref([])
const loading = ref(true)
const loadError = ref('')
const sendError = ref('')
const draft = ref('')
const sending = ref(false)
const attachment = ref(null) // File waiting to be sent with the next message
const bodyEl = ref(null)

// Admin's replies arrive without any push channel to this page, so poll
// gently while it's open instead of making the customer reload to see them.
const POLL_MS = 8000
let timer = null

function scrollToEnd() {
  nextTick(() => {
    if (bodyEl.value) bodyEl.value.scrollTop = bodyEl.value.scrollHeight
  })
}

async function load({ initial = false } = {}) {
  try {
    const res = await api.get('/me/messages')
    const grew = res.messages.length !== messages.value.length
    messages.value = res.messages
    loadError.value = ''
    if (initial || grew) scrollToEnd()
  } catch (err) {
    // A failed background poll shouldn't blank a thread the customer is reading.
    if (initial) loadError.value = err.message || 'Không tải được tin nhắn'
  } finally {
    loading.value = false
  }
}

async function send() {
  const content = draft.value.trim()
  if ((!content && !attachment.value) || sending.value) return
  sending.value = true
  sendError.value = ''
  try {
    const body = { content }
    if (attachment.value) body.attachment = await fileToPayload(attachment.value)
    const msg = await api.post('/me/messages', body)
    messages.value.push(msg)
    draft.value = ''
    attachment.value = null
    scrollToEnd()
  } catch (err) {
    sendError.value = err.message || 'Không gửi được tin nhắn'
  } finally {
    sending.value = false
  }
}

function timeLabel(iso) {
  const d = new Date(iso)
  return isNaN(d) ? '' : d.toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' })
}

onMounted(() => {
  load({ initial: true })
  timer = setInterval(() => load(), POLL_MS)
})
onBeforeUnmount(() => clearInterval(timer))
</script>

<template>
  <div class="page">
    <h1 class="page-title">Phản hồi</h1>
    <p class="page-subtitle">Gửi câu hỏi hoặc báo lỗi cho Admin. Admin sẽ trả lời tại đây.</p>

    <div v-if="loadError" class="alert alert-error">{{ loadError }}</div>
    <div v-if="sendError" class="alert alert-error">{{ sendError }}</div>

    <div ref="bodyEl" class="card thread-body">
      <div v-if="loading">Đang tải tin nhắn...</div>
      <div v-else-if="messages.length === 0" class="empty-thread">
        Chưa có tin nhắn nào. Hãy gửi tin nhắn đầu tiên cho Admin.
      </div>
      <div v-else class="messages">
        <div v-for="m in messages" :key="m.id" class="msg" :class="{ mine: m.sender === 'user' }">
          <div class="msg-bubble">
            <div v-if="m.sender === 'admin'" class="msg-from">Admin</div>
            <span v-if="m.content">{{ m.content }}</span>
            <MessageAttachment v-if="m.attachment" :att="m.attachment" :path="`/me/messages/${m.id}/attachment`" />
            <div class="msg-time">{{ timeLabel(m.createdAt) }}</div>
          </div>
        </div>
      </div>
    </div>

    <div class="composer">
      <AttachmentPreview v-if="attachment" :file="attachment" @remove="attachment = null" />
      <form class="send-row composer-row" @submit.prevent="send">
        <ChatAttachButtons :disabled="sending" @pick="(f) => { attachment = f; sendError = '' }" @error="(m) => (sendError = m)" />
        <input v-model="draft" type="text" placeholder="Nhập nội dung phản hồi..." maxlength="2000" />
        <button type="submit" class="btn btn-primary" :disabled="sending || (!draft.trim() && !attachment)">Gửi</button>
      </form>
    </div>
  </div>
</template>

<style scoped>
.thread-body {
  min-height: 300px;
  max-height: 60vh;
  overflow-y: auto;
  margin-bottom: 12px;
}
.empty-thread {
  color: var(--muted);
  text-align: center;
  padding: 24px 0;
}
.messages {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.msg {
  display: flex;
}
.msg.mine {
  justify-content: flex-end;
}
.msg-bubble {
  max-width: 75%;
  padding: 8px 12px;
  border-radius: var(--radius-md);
  background: var(--surface-2);
  font-size: 14px;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.msg.mine .msg-bubble {
  background: var(--accent-soft);
  color: var(--accent-strong);
}
.msg-from {
  font-size: 11px;
  font-weight: 700;
  color: var(--accent-strong);
  margin-bottom: 2px;
}
.msg-time {
  font-size: 11px;
  color: var(--muted);
  margin-top: 4px;
}
.send-row {
  display: flex;
  gap: 8px;
}
.send-row input {
  flex: 1;
  font-family: var(--font-body);
  font-size: 15px;
  color: var(--text);
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 12px 14px;
}
/* ---- Chat: bounded reading width, one panel (messages + composer) ---- */
.thread-body,
.send-row {
  max-width: 880px;
}
.thread-body {
  height: clamp(320px, calc(100vh - 360px), 640px);
  min-height: 0;
  max-height: none;
  margin-bottom: 0;
  padding: 20px;
  border-radius: 14px 14px 0 0;
  border-bottom: 0;
  box-shadow: none;
  overscroll-behavior: contain;
}
.empty-thread {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  padding: 0 16px;
  font-size: 15px;
  line-height: 1.5;
  color: var(--text-secondary);
}
.messages {
  gap: 12px;
}
.msg-bubble {
  max-width: min(75%, 560px);
  padding: 10px 14px;
  border-radius: 14px 14px 14px 4px;
  background: var(--surface);
  border: 1px solid var(--border);
  color: var(--text-primary);
  font-size: 15px;
  line-height: 1.5;
}
.msg.mine .msg-bubble {
  border-radius: 14px 14px 4px 14px;
  background: color-mix(in srgb, var(--primary) 10%, var(--card));
  border-color: color-mix(in srgb, var(--primary) 25%, var(--border));
  color: var(--text-primary);
}
.msg-from {
  font-size: 12px;
  color: var(--text-secondary);
  margin-bottom: 2px;
}
.msg-time {
  font-size: 12px;
  line-height: 1.2;
  color: var(--text-secondary);
  margin-top: 6px;
}
.msg.mine .msg-time {
  text-align: right;
}

/* Composer: attached to the message panel */
.send-row {
  align-items: center;
  padding: 12px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 0 0 14px 14px;
}
.send-row input {
  height: 44px;
  padding: 0 14px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  min-width: 0;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.send-row input::placeholder {
  color: var(--text-secondary);
  opacity: 1;
}
.send-row input:hover {
  border-color: var(--input-border-hover);
}
.send-row input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.send-row .btn {
  min-height: 44px;
  padding: 0 20px;
  font-size: 14px;
  border-radius: 10px;
}

@media (max-width: 640px) {
  .thread-body {
    height: clamp(300px, calc(100vh - 340px), 560px);
    padding: 16px;
  }
  .msg-bubble {
    max-width: 85%;
  }
}

/* Composer = preview (when a file is chosen) + the input row, attached to the message panel */
.composer {
  max-width: 880px;
  padding: 12px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 0 0 14px 14px;
}
.composer .send-row.composer-row {
  max-width: none;
  padding: 0;
  background: transparent;
  border: 0;
  border-radius: 0;
  gap: 8px;
}
</style>
