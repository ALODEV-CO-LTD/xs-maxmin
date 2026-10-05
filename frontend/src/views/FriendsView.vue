<!--
  Friend list + message thread. On desktop shows a split view (list left,
  thread right); on mobile the list and thread are two separate "screens"
  driven by the nested route `/friends/:friendId` (see router/index.js) so
  the back button/bottom-nav behave sensibly.

  API: GET/POST /me/friends, DELETE /me/friends/:friendId,
       GET/POST /me/friends/:friendId/messages,
       GET /me/friends/search?q= (find people by name/username to add)

  Voice-only calling (the 📞 button on the thread header; no video) goes through
  useCallStore, not this component - it just tells the store who to call;
  the actual call UI is CallOverlay.vue, mounted globally in AppShell.vue.
-->
<script setup>
import { showConfirm } from '../confirm'
import AppIcon from '../components/AppIcon.vue'
import ChatAttachButtons from '../components/ChatAttachButtons.vue'
import AttachmentPreview from '../components/AttachmentPreview.vue'
import ChatRetentionPanel from '../components/ChatRetentionPanel.vue'
import MessageAttachment from '../components/MessageAttachment.vue'
import { fileToPayload } from '../attachments'
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../api'
import { useCallStore } from '../stores/call'
import { useAuthStore } from '../stores/auth'
import { useNotifyStore } from '../stores/notify'

const route = useRoute()
const router = useRouter()
const call = useCallStore()
const auth = useAuthStore()
const notify = useNotifyStore()

const friends = ref([])
const loading = ref(true)
const loadError = ref('')

// Filters the already-added friend list client-side (no round trip needed).
const listFilter = ref('')
const filteredFriends = computed(() => {
  const q = listFilter.value.trim().toLowerCase()
  if (!q) return friends.value
  return friends.value.filter(
    (f) => f.name.toLowerCase().includes(q) || f.username.toLowerCase().includes(q),
  )
})

// Search-to-add: finds accounts by name/username via GET /me/friends/search
// so people don't have to exchange a customer code just to add each other.
const searchQuery = ref('')
const searchResults = ref([])
const searching = ref(false)
const searchError = ref('')
let searchTimer = null

watch(searchQuery, (q) => {
  clearTimeout(searchTimer)
  const query = q.trim()
  if (!query) {
    searchResults.value = []
    searching.value = false
    return
  }
  searching.value = true
  searchTimer = setTimeout(async () => {
    searchError.value = ''
    try {
      const res = await api.get(`/me/friends/search?q=${encodeURIComponent(query)}`)
      searchResults.value = res.results
    } catch (err) {
      searchError.value = err.message || 'Không tìm kiếm được'
    } finally {
      searching.value = false
    }
  }, 300)
})

const addingId = ref(null)
async function addFromSearch(result) {
  addingId.value = result.id
  try {
    const friend = await api.post('/me/friends', { userId: result.id })
    const idx = friends.value.findIndex((f) => f.id === friend.id)
    if (idx === -1) friends.value.unshift(friend)
    const r = searchResults.value.find((r) => r.id === result.id)
    if (r) r.isFriend = true
  } catch (err) {
    searchError.value = err.message || 'Không thêm được bạn bè'
  } finally {
    addingId.value = null
  }
}

const addCode = ref('')
const addError = ref('')
const adding = ref(false)

const messages = ref([])
const messagesLoading = ref(false)
const messagesError = ref('')
const newMessage = ref('')
const sending = ref(false)
const attachment = ref(null) // File waiting to be sent with the next message

// Voice-call history with the open friend (GET /me/calls), shown inside the
// conversation next to the messages, plus the per-friend count of missed
// calls the user has not looked at yet (badge in the friend list).
const calls = ref([])
const threadBody = ref(null) // scroll box of the open conversation
const unseenMissed = ref({})

function callLine(c) {
  const mins = Math.floor((c.durationSeconds || 0) / 60)
  const secs = String((c.durationSeconds || 0) % 60).padStart(2, '0')
  const dur = `${mins}:${secs}`
  const out = c.direction === 'outgoing'
  switch (c.status) {
    case 'completed':
      return `${out ? 'Cuộc gọi thoại đi' : 'Cuộc gọi thoại đến'} · ${dur}`
    case 'missed':
      return out ? 'Cuộc gọi đi · Không ai nghe máy' : 'Cuộc gọi nhỡ'
    case 'busy':
      return out ? 'Cuộc gọi đi · Máy bận' : 'Cuộc gọi nhỡ (bạn đang bận)'
    case 'rejected':
      return out ? 'Cuộc gọi đi · Bị từ chối' : 'Bạn đã từ chối cuộc gọi'
    case 'failed':
      return 'Cuộc gọi · Không kết nối được âm thanh'
    default:
      return 'Cuộc gọi thoại'
  }
}
const isMissedCall = (c) => c.direction === 'incoming' && (c.status === 'missed' || c.status === 'busy')

// Messages and call entries in one list, newest on top.
const timeline = computed(() => {
  const items = [
    ...messages.value.map((m) => ({ kind: 'msg', key: m.id, at: m.createdAt, m })),
    ...calls.value.map((c) => ({ kind: 'call', key: `call-${c.id}`, at: c.createdAt, c })),
  ]
  // Newest first: the latest message is always at the top, no scrolling down.
  return items.sort((a, b) => (a.at < b.at ? 1 : a.at > b.at ? -1 : 0))
})

async function loadCalls(friendId) {
  try {
    const res = await api.get(`/me/calls?friendId=${encodeURIComponent(friendId)}&limit=50`)
    calls.value = res.calls
    unseenMissed.value = res.unseenMissed || {}
    if (unseenMissed.value[friendId]) {
      await api.post('/me/calls/seen', { friendId })
      delete unseenMissed.value[friendId]
    }
  } catch {
    /* history is a nicety; the conversation still works without it */
  }
}
async function loadUnseenMissed() {
  try {
    const res = await api.get('/me/calls?limit=1')
    unseenMissed.value = res.unseenMissed || {}
  } catch {
    /* ignore */
  }
}

const selectedFriendId = computed(() => route.params.friendId || null)
const selectedFriend = computed(() =>
  friends.value.find((f) => f.id === selectedFriendId.value) || null,
)
// Calls exist only between customers: nobody can call Admin and Admin calls
// nobody (chat with Admin is unaffected). The server enforces this too -
// hiding the buttons just avoids offering something that would be refused.
const canCall = computed(() => !auth.isAdmin && !!selectedFriend.value && !selectedFriend.value.isAdmin)


async function loadFriends({ quiet = false } = {}) {
  if (!quiet) loading.value = true
  loadError.value = ''
  try {
    const res = await api.get('/me/friends')
    friends.value = res.friends
  } catch (err) {
    loadError.value = err.message || 'Không tải được danh sách bạn bè'
  } finally {
    loading.value = false
  }
}

async function loadMessages(friendId, { quiet = false } = {}) {
  if (!quiet) messagesLoading.value = true
  messagesError.value = ''
  try {
    const res = await api.get(`/me/friends/${friendId}/messages`)
    messages.value = res.messages
  } catch (err) {
    messagesError.value = err.message || 'Không tải được tin nhắn'
  } finally {
    messagesLoading.value = false
  }
}

// The customer's own Mã ID, shown at the top so they can read it out to
// someone who wants to add them. The server gives every account one; an
// account that somehow has none (created before that) gets one made here
// instead of being left with nothing to share.
const myCode = ref('')
const codeCopied = ref(false)
async function loadMyCode() {
  try {
    const res = await api.get('/me/customer-codes')
    myCode.value = res.codes?.[0]?.code || (await api.post('/me/customer-codes', {})).code || ''
  } catch {
    /* the card simply stays hidden - adding friends still works without it */
  }
}
async function copyMyCode() {
  try {
    await navigator.clipboard.writeText(myCode.value)
    codeCopied.value = true
    setTimeout(() => (codeCopied.value = false), 1800)
  } catch {
    /* clipboard unavailable - the ID is on screen to read out */
  }
}

onMounted(() => {
  loadFriends()
  if (!auth.isAdmin) {
    loadMyCode()
    loadUnseenMissed()
  }
})

// A new chat message arrived over the WebSocket: refresh the open
// conversation, or the friend list (last message preview) otherwise.
watch(
  () => notify.incomingTick,
  () => {
    const m = notify.lastIncoming
    if (!m || m.source !== 'friend') return
    if (selectedFriendId.value === m.from) {
      loadMessages(m.from, { quiet: true })
      notify.clear(`friend:${m.from}`)
    } else {
      loadFriends({ quiet: true })
    }
  },
)

// A call just ended (or was missed): refresh history and the badges.
watch(
  () => call.endedTick,
  () => {
    if (auth.isAdmin) return
    if (selectedFriendId.value) loadCalls(selectedFriendId.value)
    else loadUnseenMissed()
  },
)

watch(
  selectedFriendId,
  (id) => {
    if (id) {
      notify.clear(`friend:${id}`)
      loadMessages(id)
      if (!auth.isAdmin) loadCalls(id)
    } else {
      messages.value = []
      calls.value = []
    }
  },
  { immediate: true },
)

function openFriend(friend) {
  router.push({ name: 'friend-thread', params: { friendId: friend.id } })
}

function backToList() {
  router.push({ name: 'friends' })
}

async function addFriend() {
  addError.value = ''
  const code = addCode.value.trim()
  if (!code) {
    addError.value = 'Vui lòng nhập mã ID'
    return
  }
  adding.value = true
  try {
    const friend = await api.post('/me/friends', { code })
    const idx = friends.value.findIndex((f) => f.id === friend.id)
    if (idx === -1) friends.value.unshift(friend)
    addCode.value = ''
  } catch (err) {
    addError.value = err.message || 'Không thêm được bạn bè'
  } finally {
    adding.value = false
  }
}

async function removeFriend(friend) {
  if (!(await showConfirm({
    title: 'Xoá bạn bè',
    message: `Xoá bạn bè "${friend.name}"? Cuộc trò chuyện sẽ không còn hiển thị.`,
    confirmText: 'Xoá',
    danger: true,
  }))) return
  try {
    await api.del(`/me/friends/${friend.id}`)
    friends.value = friends.value.filter((f) => f.id !== friend.id)
    if (selectedFriendId.value === friend.id) backToList()
  } catch (err) {
    alert(err.message || 'Không xoá được bạn bè')
  }
}

async function sendMessage() {
  const content = newMessage.value.trim()
  if ((!content && !attachment.value) || !selectedFriendId.value) return
  sending.value = true
  messagesError.value = ''
  try {
    const body = { content }
    if (attachment.value) body.attachment = await fileToPayload(attachment.value)
    const msg = await api.post(`/me/friends/${selectedFriendId.value}/messages`, body)
    messages.value.push(msg)
    threadBody.value && (threadBody.value.scrollTop = 0)
    newMessage.value = ''
    attachment.value = null
  } catch (err) {
    messagesError.value = err.message || 'Không gửi được tin nhắn'
  } finally {
    sending.value = false
  }
}
</script>

<template>
  <div class="page friends-page">
    <h1 class="page-title">Bạn bè & tin nhắn</h1>
    <p class="page-subtitle">Kết bạn bằng mã ID và nhắn tin trực tiếp.</p>

    <div class="split" :class="{ 'show-thread': !!selectedFriendId }">
      <div class="list-pane">
        <div v-if="myCode" class="card my-id">
          <div>
            <div class="my-id-label">ID của bạn</div>
            <div class="my-id-code">{{ myCode }}</div>
          </div>
          <button type="button" class="btn btn-secondary btn-sm" @click="copyMyCode">
            {{ codeCopied ? 'Đã chép' : 'Sao chép' }}
          </button>
        </div>
        <div class="card search-form">
          <label for="searchQuery" style="font-size: 13px; font-weight: 700; color: var(--muted)">
            Tìm người theo tên, tài khoản hoặc mã ID
          </label>
          <input id="searchQuery" v-model="searchQuery" type="text" placeholder="Nhập tên, tài khoản hoặc mã ID..." style="margin-top: 6px" />
          <div v-if="searchError" class="alert alert-error" style="margin: 8px 0 0">{{ searchError }}</div>

          <div v-if="searchQuery.trim()" class="search-results">
            <div v-if="searching" class="search-hint">Đang tìm...</div>
            <div v-else-if="searchResults.length === 0" class="search-hint">Không tìm thấy ai phù hợp.</div>
            <div v-else v-for="r in searchResults" :key="r.id" class="search-item">
              <div class="friend-info">
                <strong>{{ r.name }} <span v-if="r.isAdmin" class="chip chip-brand" style="font-size: 10px; padding: 1px 6px">Admin</span></strong>
                <span class="friend-last">@{{ r.username }}</span>
              </div>
              <button
                v-if="!r.isFriend"
                class="btn btn-secondary btn-sm"
                :disabled="addingId === r.id"
                @click="addFromSearch(r)"
              >
                {{ addingId === r.id ? '...' : 'Kết bạn' }}
              </button>
              <span v-else class="chip chip-accent">Đã là bạn</span>
            </div>
          </div>
        </div>

        <details class="card add-form">
          <summary style="font-size: 13px; font-weight: 700; color: var(--muted); cursor: pointer">
            Hoặc kết bạn bằng mã ID
          </summary>
          <form class="add-row" style="margin-top: 8px" @submit.prevent="addFriend">
            <input id="addCode" v-model="addCode" type="text" placeholder="Nhập mã ID" />
            <button type="submit" class="btn btn-primary btn-sm" :disabled="adding">
              {{ adding ? '...' : 'Thêm' }}
            </button>
          </form>
          <div v-if="addError" class="alert alert-error" style="margin: 8px 0 0">{{ addError }}</div>
        </details>

        <div v-if="loading" class="card">Đang tải...</div>
        <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
        <template v-else>
          <div v-if="friends.length > 0" class="field" style="margin-bottom: 10px">
            <input v-model="listFilter" type="text" placeholder="Lọc trong danh sách bạn bè..." />
          </div>
          <div v-if="friends.length === 0" class="card">Chưa có bạn bè nào.</div>
          <div v-else-if="filteredFriends.length === 0" class="card">Không có bạn bè nào khớp.</div>
          <div v-else class="friend-list">
            <div
              v-for="f in filteredFriends"
              :key="f.id"
              class="card friend-item"
              :class="{ active: f.id === selectedFriendId }"
              @click="openFriend(f)"
            >
              <div class="friend-info">
                <strong>
                  {{ f.name }}
                  <span v-if="notify.unread[`friend:${f.id}`]" class="unread-badge" title="Tin nhắn chưa đọc">
                    {{ notify.unread[`friend:${f.id}`] > 99 ? '99+' : notify.unread[`friend:${f.id}`] }}
                  </span>
                  <span v-if="unseenMissed[f.id]" class="missed-badge" title="Cuộc gọi nhỡ">
                    <AppIcon name="phone" /> {{ unseenMissed[f.id] }}
                  </span>
                </strong>
                <span class="friend-last" :class="{ 'has-unread': notify.unread[`friend:${f.id}`] }">{{ f.lastMessage || 'Chưa có tin nhắn' }}</span>
              </div>
              <button class="btn btn-ghost btn-sm" @click.stop="removeFriend(f)">Xoá</button>
            </div>
          </div>
        </template>
      </div>

      <div class="thread-pane">
        <div v-if="!selectedFriendId" class="card empty-thread">Chọn một người bạn để xem tin nhắn.</div>
        <template v-else>
          <div class="thread-header">
            <button class="btn btn-ghost btn-sm back-btn" @click="backToList"><AppIcon name="arrow-left" /> Danh sách</button>
            <strong class="thread-title">{{ selectedFriend?.name || '...' }}</strong>
            <div v-if="canCall" class="call-buttons">
              <button
                class="btn btn-ghost btn-sm"
                title="Gọi thoại"
                :disabled="call.status !== 'idle' || call.acquiring"
                @click="selectedFriend && call.startCall(selectedFriend)"
              >
                <AppIcon name="phone" />
              </button>
            </div>
          </div>
          <ChatRetentionPanel
            v-if="!selectedFriend?.isAdmin"
            :friend-id="selectedFriendId"
            :friend-name="selectedFriend?.name || ''"
            @applied="loadMessages(selectedFriendId)"
          />
          <div v-if="messagesError" class="alert alert-error">{{ messagesError }}</div>
          <div ref="threadBody" class="card thread-body">
            <div v-if="messagesLoading">Đang tải tin nhắn...</div>
            <div v-else-if="timeline.length === 0" class="empty-thread">Chưa có tin nhắn nào.</div>
            <div v-else class="messages">
              <template v-for="item in timeline" :key="item.key">
                <div
                  v-if="item.kind === 'msg'"
                  class="msg"
                  :class="{ mine: item.m.fromUserId !== selectedFriendId }"
                >
                  <div class="msg-bubble">
                    <span v-if="item.m.content">{{ item.m.content }}</span>
                    <MessageAttachment
                      v-if="item.m.attachment"
                      :att="item.m.attachment"
                      :path="`/me/friends/${selectedFriendId}/messages/${item.m.id}/attachment`"
                    />
                  </div>
                </div>
                <div v-else class="call-line" :class="{ missed: isMissedCall(item.c) || item.c.status === 'failed' }">
                  <AppIcon name="phone" />
                  <span>{{ callLine(item.c) }}</span>
                  <button
                    v-if="canCall && (isMissedCall(item.c) || item.c.status === 'rejected' || item.c.status === 'failed')"
                    class="btn btn-ghost btn-sm"
                    :disabled="call.status !== 'idle' || call.acquiring"
                    @click="selectedFriend && call.startCall(selectedFriend)"
                  >Gọi lại</button>
                </div>
              </template>
            </div>
          </div>
          <AttachmentPreview v-if="attachment" :file="attachment" @remove="attachment = null" />
          <form class="send-row" @submit.prevent="sendMessage">
            <ChatAttachButtons :disabled="sending" @pick="(f) => { attachment = f; messagesError = '' }" @error="(m) => (messagesError = m)" />
            <input v-model="newMessage" type="text" placeholder="Nhập tin nhắn..." />
            <button type="submit" class="btn btn-primary" :disabled="sending || (!newMessage.trim() && !attachment)">Gửi</button>
          </form>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.my-id {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 10px;
}
.my-id-label {
  font-size: 12px;
  font-weight: 700;
  color: var(--muted);
}
.my-id-code {
  font-size: 24px;
  font-weight: 800;
  letter-spacing: 3px;
  color: var(--accent-strong);
  font-variant-numeric: tabular-nums;
}
.split {
  display: grid;
  grid-template-columns: 320px 1fr;
  gap: 16px;
}
.search-form {
  margin-bottom: 10px;
}
.search-form input,
.add-row input {
  width: 100%;
  flex: 1;
  font-family: var(--font-body);
  font-size: 15px;
  color: var(--text);
  background: var(--surface-2);
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  padding: 10px 12px;
  box-sizing: border-box;
}
.search-results {
  margin-top: 10px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.search-hint {
  color: var(--muted);
  font-size: 13px;
  padding: 6px 2px;
}
.search-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 10px;
  border: 1px solid var(--border);
  border-radius: var(--radius-md);
  background: var(--surface-2);
}
.add-form {
  margin-bottom: 12px;
}
.add-row {
  display: flex;
  gap: 8px;
  margin-top: 6px;
}
.friend-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.friend-item {
  padding: 12px 14px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  cursor: pointer;
  gap: 8px;
}
.friend-item.active {
  border-color: var(--accent);
  background: var(--accent-soft);
}
.friend-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
  min-width: 0;
}
.friend-last {
  font-size: 12px;
  color: var(--muted);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  max-width: 180px;
}
.thread-pane {
  display: flex;
  flex-direction: column;
  min-height: 0;
}
.thread-header {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 10px;
}
.thread-title {
  flex: 1;
}
.call-buttons {
  display: flex;
  gap: 4px;
}
.back-btn {
  display: none;
}
.thread-body {
  flex: 1;
  min-height: 300px;
  max-height: 480px;
  overflow-y: auto;
  margin-bottom: 12px;
}
.empty-thread {
  color: var(--muted);
  text-align: center;
  padding: 24px 0;
}
.unread-badge {
  display: inline-block;
  margin-left: 6px;
  min-width: 20px;
  padding: 1px 7px;
  border-radius: 999px;
  background: var(--danger, #ef4444);
  color: #fff;
  font-size: 12px;
  font-weight: 700;
  text-align: center;
}
.friend-last.has-unread {
  color: var(--text);
  font-weight: 600;
}
.missed-badge {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  margin-left: 6px;
  padding: 1px 7px;
  border-radius: 999px;
  background: var(--danger, #d64545);
  color: #fff;
  font-size: 12px;
  font-weight: 700;
}
.call-line {
  align-self: center;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 12px;
  border-radius: 999px;
  background: var(--surface-2);
  color: var(--muted);
  font-size: 13px;
}
.call-line.missed {
  color: var(--danger, #d64545);
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
}
.msg.mine .msg-bubble {
  background: var(--accent-soft);
  color: var(--accent-strong);
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

@media (max-width: 800px) {
  .split {
    grid-template-columns: 1fr;
  }
  .list-pane {
    display: block;
  }
  .thread-pane {
    display: none;
  }
  .split.show-thread .list-pane {
    display: none;
  }
  .split.show-thread .thread-pane {
    display: flex;
  }
  .back-btn {
    display: inline-flex;
  }
}
/* ---- One unified left panel (ID, search, add by ID, friend list) ---- */
.split {
  grid-template-columns: 380px minmax(0, 1fr);
  gap: 16px;
  align-items: start;
}
.list-pane {
  padding: 16px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: var(--shadow-sm);
}
/* the former small cards become flat sections separated by hairlines */
.list-pane > .my-id,
.list-pane > .search-form,
.list-pane > .add-form {
  margin: 0 0 16px;
  padding: 0 0 16px;
  background: transparent;
  border: 0;
  border-bottom: 1px solid var(--border);
  border-radius: 0;
  box-shadow: none;
}

/* ID + copy */
.my-id-label {
  font-size: 13px;
  color: var(--text-secondary);
}
.my-id-code {
  font-size: 22px;
  letter-spacing: 2px;
  line-height: 1.2;
  color: var(--text-primary);
}
.my-id .btn,
.search-item .btn,
.add-row .btn {
  min-height: 36px;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
}

/* labels + consistent 44px inputs */
.search-form > label,
.add-form > summary {
  display: block;
  font-size: 14px !important;
  font-weight: 700 !important;
  color: var(--text-primary) !important;
}
.add-form > summary {
  cursor: pointer;
}
.list-pane input {
  height: 44px;
  padding: 0 14px;
  font-size: 15px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.list-pane input::placeholder {
  color: var(--text-secondary);
  opacity: 1;
}
.list-pane input:hover {
  border-color: var(--input-border-hover);
}
.list-pane input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.list-pane .field {
  margin-bottom: 8px !important;
}
.add-row {
  margin-top: 8px !important;
}

.search-hint {
  font-size: 14px;
  color: var(--text-secondary);
}
.search-item {
  background: var(--surface);
}

/* Friend list: flat rows, not stacked cards */
.friend-list {
  gap: 2px;
}
.list-pane .friend-item.card {
  padding: 10px 12px;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 10px;
  box-shadow: none;
}
.list-pane .friend-item.card:hover {
  background: var(--surface);
}
.list-pane .friend-item.card.active {
  background: var(--primary-soft);
  border-color: color-mix(in srgb, var(--primary) 35%, transparent);
}
.friend-info strong {
  font-size: 15px;
}
.friend-last {
  font-size: 13px;
  color: var(--text-secondary);
  max-width: none;
}
.friend-item .btn-ghost {
  min-height: 32px;
  padding: 0 10px;
  font-size: 13px;
  color: var(--text-secondary);
}
.friend-item .btn-ghost:hover {
  color: var(--danger-text);
  background: var(--danger-soft);
}
/* empty states in the left panel */
.list-pane > .card:not(.my-id):not(.search-form):not(.add-form):not(.friend-item) {
  padding: 24px 16px;
  background: var(--surface);
  border: 1px dashed var(--input-border);
  border-radius: 12px;
  box-shadow: none;
  color: var(--text-secondary);
  font-size: 15px;
  text-align: center;
}

/* ---- Chat panel: a clear card; empty state centred both ways ---- */
.thread-pane {
  min-height: 560px;
  padding: 16px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: var(--shadow-sm);
}
.thread-pane > .empty-thread {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 24px;
  background: transparent;
  border: 0;
  box-shadow: none;
  font-size: 16px;
  color: var(--text-secondary);
}
.thread-header {
  padding-bottom: 12px;
  margin-bottom: 12px;
  border-bottom: 1px solid var(--border);
}
.thread-title {
  font-size: 16px;
}
.thread-pane .thread-body {
  min-height: 320px;
  max-height: 60vh;
  padding: 4px 0;
  background: transparent;
  border: 0;
  box-shadow: none;
}
.thread-body .empty-thread {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 280px;
  padding: 0;
  font-size: 15px;
  color: var(--text-secondary);
}
.msg-bubble {
  font-size: 15px;
  background: var(--surface);
}
.msg.mine .msg-bubble {
  background: var(--primary-soft);
  color: var(--text-primary);
}
.send-row input {
  height: 44px;
  padding: 0 14px;
  font-size: 15px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.send-row input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.send-row .btn {
  min-height: 44px;
  padding: 0 20px;
  border-radius: 10px;
}

@media (max-width: 800px) {
  .thread-pane {
    min-height: 0;
  }
}

/* call buttons: icons the same 20px as the rest of the app's icons */
.call-buttons .btn {
  width: 40px;
  height: 40px;
  min-height: 40px;
  padding: 0;
  font-size: 20px;
  color: var(--text-secondary);
  border-radius: 10px;
}
.call-buttons .btn:hover:not(:disabled) {
  color: var(--text-primary);
  background: var(--surface);
}
.call-buttons .btn:disabled {
  opacity: 0.45;
}
</style>
