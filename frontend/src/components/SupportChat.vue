<!--
  Customer <-> Admin support chat as a small popover under the top-bar button (next to the
  light/dark switch). Replaces the old full "Phản hồi" page for customers; Admin still answers
  from admin/MessagesView.vue (same thread, same API).

  API: GET /me/messages -> { messages: [{ id, sender: 'user'|'admin', content, createdAt, attachment? }] }
       POST /me/messages { content, attachment? }
  Newest message on top (like Bạn bè), composer pinned at the bottom of the popover.
  The red badge on the button is notify.supportUnread; opening the popover marks it read.
  notify.supportOpen lets other code (a message toast, the old /feedback link) open it.
-->
<script setup>
import { computed, nextTick, onBeforeUnmount, ref, watch } from 'vue'
import { api } from '../api'
import { fileToPayload } from '../attachments'
import { useNotifyStore } from '../stores/notify'
import AppIcon from './AppIcon.vue'
import AttachmentPreview from './AttachmentPreview.vue'
import ChatAttachButtons from './ChatAttachButtons.vue'
import MessageAttachment from './MessageAttachment.vue'

const notify = useNotifyStore()
const root = ref(null)
const input = ref(null)
const open = ref(false)

const messages = ref([])
const loading = ref(false)
const loadError = ref('')
const sendError = ref('')
const draft = ref('')
const sending = ref(false)
const attachment = ref(null)

const unread = computed(() => notify.supportUnread)
// newest first
const ordered = computed(() => [...messages.value].reverse())

let timer = null
async function load({ initial = false } = {}) {
  if (initial) loading.value = true
  try {
    const res = await api.get('/me/messages')
    messages.value = res.messages
    loadError.value = ''
  } catch (err) {
    if (initial) loadError.value = err.message || 'Không tải được tin nhắn'
  } finally {
    loading.value = false
  }
}

async function openChat() {
  open.value = true
  notify.supportOpen = false
  notify.clear('support')
  load({ initial: messages.value.length === 0 })
  clearInterval(timer)
  timer = setInterval(load, 8000)
  await nextTick()
  input.value?.focus()
}
function closeChat() {
  open.value = false
  clearInterval(timer)
  timer = null
}
function toggle() {
  if (open.value) closeChat()
  else openChat()
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

// Admin replied (WebSocket push): refresh at once while the popover is open.
watch(
  () => notify.incomingTick,
  () => {
    if (notify.lastIncoming?.source !== 'support') return
    if (open.value) {
      load()
      notify.clear('support')
    }
  },
)
watch(open, (v) => (notify.supportVisible = v))
// While the popover is open anything new counts as read at once (the 10 s unread refresh must not bring the badge back).
watch(
  () => notify.supportUnread,
  (n) => {
    if (open.value && n > 0) notify.clear('support')
  },
)
watch(
  () => notify.supportOpen,
  (v) => {
    if (v && !open.value) openChat()
  },
  { immediate: true },
)

function onDocDown(e) {
  if (open.value && root.value && !root.value.contains(e.target)) closeChat()
}
document.addEventListener('mousedown', onDocDown)
onBeforeUnmount(() => {
  notify.supportVisible = false
  document.removeEventListener('mousedown', onDocDown)
  clearInterval(timer)
})
</script>

<template>
  <div ref="root" class="support" @keydown.esc="closeChat">
    <button
      type="button"
      class="support-btn"
      :class="{ active: open }"
      aria-haspopup="dialog"
      :aria-expanded="open"
      aria-label="Phản hồi cho Admin"
      title="Phản hồi cho Admin"
      @click="toggle"
    >
      <AppIcon name="message-square-more" />
      <span v-if="unread" class="support-badge" aria-label="Tin nhắn chưa đọc">{{ unread > 9 ? '9+' : unread }}</span>
    </button>

    <section v-if="open" class="support-pop" role="dialog" aria-label="Phản hồi cho Admin">
      <header class="sp-head">
        <div>
          <strong>Hỗ trợ từ Admin</strong>
          <span>Gửi câu hỏi hoặc báo lỗi, Admin trả lời tại đây.</span>
        </div>
        <button type="button" class="sp-close" aria-label="Đóng" @click="closeChat"><AppIcon name="x" /></button>
      </header>

      <div class="sp-body">
        <p v-if="loadError" class="sp-note sp-error">{{ loadError }}</p>
        <p v-else-if="loading" class="sp-note">Đang tải tin nhắn...</p>
        <p v-else-if="messages.length === 0" class="sp-note">Chưa có tin nhắn nào. Hãy gửi tin nhắn đầu tiên cho Admin.</p>
        <ul v-else class="sp-list">
          <li v-for="m in ordered" :key="m.id" class="sp-msg" :class="{ mine: m.sender === 'user' }">
            <div class="sp-bubble">
              <span v-if="m.sender === 'admin'" class="sp-from">Admin</span>
              <span v-if="m.content" class="sp-text">{{ m.content }}</span>
              <MessageAttachment v-if="m.attachment" :att="m.attachment" :path="`/me/messages/${m.id}/attachment`" />
            </div>
            <time class="sp-time">{{ timeLabel(m.createdAt) }}</time>
          </li>
        </ul>
      </div>

      <footer class="sp-foot">
        <p v-if="sendError" class="sp-note sp-error">{{ sendError }}</p>
        <AttachmentPreview v-if="attachment" :file="attachment" @remove="attachment = null" />
        <form class="sp-form" @submit.prevent="send">
          <ChatAttachButtons :disabled="sending" @pick="(f) => { attachment = f; sendError = '' }" @error="(m) => (sendError = m)" />
          <input ref="input" v-model="draft" type="text" placeholder="Nhập tin nhắn..." maxlength="2000" aria-label="Nội dung tin nhắn" />
          <button type="submit" class="btn btn-primary" :disabled="sending || (!draft.trim() && !attachment)">Gửi</button>
        </form>
      </footer>
    </section>
  </div>
</template>

<style scoped>
.support {
  position: relative;
  flex: none;
}
.support-btn {
  position: relative;
  width: 44px;
  height: 44px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  font-size: 20px;
  color: var(--text-secondary);
  background: transparent;
  border: 1px solid transparent;
  border-radius: 10px;
  cursor: pointer;
}
.support-btn:hover,
.support-btn.active {
  color: var(--text-primary);
  background: var(--surface);
  border-color: var(--border);
}
.support-btn:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 2px;
}
.support-badge {
  position: absolute;
  top: 2px;
  right: 2px;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  font-size: 11px;
  font-weight: 800;
  line-height: 18px;
  text-align: center;
  color: #fff;
  background: #ef4444;
  border-radius: 999px;
}

.support-pop {
  position: absolute;
  top: calc(100% + 8px);
  right: 0;
  z-index: 60;
  display: flex;
  flex-direction: column;
  width: 360px;
  height: min(540px, calc(100vh - 90px));
  overflow: hidden;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: var(--shadow-lg);
}
.sp-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 8px;
  padding: 12px 12px 10px 16px;
  border-bottom: 1px solid var(--border);
}
.sp-head div {
  display: grid;
  gap: 2px;
}
.sp-head strong {
  font-size: 15px;
}
.sp-head span {
  font-size: 13px;
  color: var(--text-secondary);
}
.sp-close {
  width: 32px;
  height: 32px;
  flex: none;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  color: var(--text-secondary);
  background: transparent;
  border: 0;
  border-radius: 8px;
  cursor: pointer;
}
.sp-close:hover {
  background: var(--surface);
}
.sp-body {
  flex: 1;
  min-height: 0;
  padding: 12px 14px;
  overflow-y: auto;
  overscroll-behavior: contain;
}
.sp-note {
  margin: 0;
  padding: 24px 8px;
  font-size: 14px;
  line-height: 1.5;
  text-align: center;
  color: var(--text-secondary);
}
.sp-error {
  padding: 6px 0;
  color: var(--danger-text);
}
.sp-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin: 0;
  padding: 0;
  list-style: none;
}
.sp-msg {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 3px;
}
.sp-msg.mine {
  align-items: flex-end;
}
.sp-bubble {
  max-width: 85%;
  padding: 8px 12px;
  font-size: 14px;
  line-height: 1.45;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 14px 14px 14px 4px;
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}
.sp-msg.mine .sp-bubble {
  background: color-mix(in srgb, var(--primary) 14%, var(--card));
  border-color: color-mix(in srgb, var(--primary) 30%, var(--border));
  border-radius: 14px 14px 4px 14px;
}
.sp-from {
  display: block;
  margin-bottom: 2px;
  font-size: 12px;
  font-weight: 700;
  color: var(--primary);
}
.sp-time {
  padding: 0 4px;
  font-size: 12px;
  color: var(--text-secondary);
}
.sp-foot {
  padding: 10px 12px 12px;
  border-top: 1px solid var(--border);
}
.sp-form {
  display: flex;
  align-items: center;
  gap: 6px;
}
.sp-form input {
  flex: 1 1 0;
  min-width: 0;
  height: 40px;
  padding: 0 12px;
  font: inherit;
  font-size: 14px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.sp-form input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.sp-form .btn {
  min-height: 40px;
  padding: 0 14px;
  font-size: 14px;
  border-radius: 10px;
}

@media (max-width: 640px) {
  .support {
    position: static;
  }
  .support-pop {
    position: fixed;
    top: 60px;
    right: 8px;
    left: 8px;
    width: auto;
    height: min(560px, calc(100dvh - 76px));
  }
}
</style>
