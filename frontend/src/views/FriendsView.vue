<!--
  Friend list + message thread. On desktop shows a split view (list left,
  thread right); on mobile the list and thread are two separate "screens"
  driven by the nested route `/friends/:friendId` (see router/index.js) so
  the back button/bottom-nav behave sensibly.

  API: GET/POST /me/friends, DELETE /me/friends/:friendId,
       GET /me/friends/search?q= (find people by name/username to add)
  Messages are end-to-end encrypted: composed, encrypted and kept only on this
  device (e2ee/chat.js), relayed live over the WebSocket to a friend who is online.
  Nothing is stored on the server (docs/MA_HOA_2_DAU.md).

  Voice-only calling (the 📞 button on the thread header; no video) goes through
  useCallStore, not this component - it just tells the store who to call;
  the actual call UI is CallOverlay.vue, mounted globally in AppShell.vue.
-->
<script setup>
import AppButton from '../components/AppButton.vue'
import { showConfirm } from '../confirm'
import { fold } from '../messageParser'
import { kindSymbolsFor, typesOf } from '../scoringConfig'
import AppIcon from '../components/AppIcon.vue'
import ChatAttachButtons from '../components/ChatAttachButtons.vue'
import AttachmentPreview from '../components/AttachmentPreview.vue'
import ChatCalcDialog from '../components/ChatCalcDialog.vue'
import ChatDecodeDialog from '../components/ChatDecodeDialog.vue'
import ChatKeyboard from '../components/ChatKeyboard.vue'
import ChatRetentionPanel from '../components/ChatRetentionPanel.vue'
import MessageAttachment from '../components/MessageAttachment.vue'
import { useChatStore } from '../e2ee/chat'
import { onScreenshotAttempt } from '../screenshotGuard'
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
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
const chat = useChatStore()

const friends = ref([])
const loading = ref(true)
const loadError = ref('')

// One search box does two things at once (see the template):
//   - filters the friends you already have, instantly and without accents
//     ("do ngoc" finds "Đỗ Ngọc Mai"), and
//   - looks for other people on the server by name, username or exact Mã ID so
//     they can be added (the "kết bạn bằng mã ID" box is no longer separate).
// A friend that only matched by Mã ID (not by name) is kept in the list too.
const filteredFriends = computed(() => {
  const q = fold(searchQuery.value.trim())
  if (!q) return friends.value
  const matchedById = new Set(searchResults.value.filter((r) => r.isFriend).map((r) => r.id))
  return friends.value.filter(
    (f) => fold(f.name).includes(q) || fold(f.username).includes(q) || matchedById.has(f.id),
  )
})
// People from the server search who are not friends yet (friends are shown in the list below).
const newPeople = computed(() => searchResults.value.filter((r) => !r.isFriend))

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

// Messages and call entries in one list, oldest on top, newest at the bottom.
const timeline = computed(() => {
  const items = [
    ...messages.value.map((m) => ({ kind: 'msg', key: m.id, at: m.createdAt, m })),
    ...calls.value.map((c) => ({ kind: 'call', key: `call-${c.id}`, at: c.createdAt, c })),
  ]
  return items.sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : 0))
})

async function loadCalls(friendId) {
  try {
    const res = await api.get(`/me/calls?friendId=${encodeURIComponent(friendId)}&limit=50`)
    calls.value = res.calls
    scrollToEnd()
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
// Sửa: hiện nút Xoá trên từng dòng. Chọn tin: "Nhập số liệu" bật hộp chọn, nút thành "Tính toán" khi chọn ≥1 tin.
const editMode = ref(false)
const selecting = ref(false)
const pickedIds = ref([])
const calcNotice = ref(false)
const decodeOpen = ref(false)
const calcOpen = ref(false)
const calcText = ref('')
const calcDate = ref('')
const calcCustomer = ref('')
function startCalc(text, date, customer) {
  calcText.value = text
  calcDate.value = date
  calcCustomer.value = customer
  decodeOpen.value = false
  calcOpen.value = true
}
function calcBack() {
  calcOpen.value = false
  decodeOpen.value = true
}
const actionLabel = computed(() => (selecting.value && pickedIds.value.length ? 'Tính toán' : 'Nhập số liệu'))
function onAction() {
  if (!selecting.value) { selecting.value = true; return }
  if (pickedIds.value.length) openDecode()
}
function togglePick(id) {
  const i = pickedIds.value.indexOf(id)
  if (i >= 0) pickedIds.value.splice(i, 1)
  else pickedIds.value.push(id)
}
function pickAll() {
  pickedIds.value = timeline.value.filter((t) => t.kind === 'msg' && !t.m.system && t.m.content).map((t) => t.m.id)
}
function cancelPick() { selecting.value = false; pickedIds.value = []; calcNotice.value = false }

// Tính toán: màn hình đối chiếu tin gốc và nội dung giải mã của các tin đã chọn (theo thứ tự trong cuộc trò chuyện).
const decodeRates = ref({})
const decodeMessages = computed(() =>
  timeline.value.filter((t) => t.kind === 'msg' && !t.m.system && pickedIds.value.includes(t.m.id)).map((t) => ({ id: t.m.id, content: t.m.content })),
)
const decodeTypes = computed(() => {
  const list = typesOf(decodeRates.value)
  return list.length ? list : ['de', 'lo']
})
const decodeSymbols = computed(() => kindSymbolsFor(decodeRates.value, null, 'mb'))
async function openDecode() {
  try {
    const { rates } = await api.get('/me/scoring-settings')
    if (rates && Object.keys(rates).length) decodeRates.value = rates
  } catch { /* giải mã với loại mặc định */ }
  decodeOpen.value = true
}
function useDecoded(text, where = {}) {
  try { sessionStorage.setItem('entries-prefill', JSON.stringify({ text, ...where })) } catch { /* private mode */ }
  decodeOpen.value = false
  router.push({ name: 'entries' })
}

// ---- Nhấn giữ / chuột phải một tin nhắn: Trả lời, Sao chép, Ghim, Chuyển tiếp, Xoá, Chọn ----------------------------------
const menu = ref(null) // { m, x, y }
let pressTimer = null
function openMenu(m, e) {
  if (selecting.value || m.system) return
  const r = e.currentTarget.getBoundingClientRect()
  menu.value = { m, x: Math.min(Math.max(8, r.left), window.innerWidth - 200), y: Math.min(r.bottom + 4, window.innerHeight - 280) }
}
function pressStart(m, e) {
  clearTimeout(pressTimer)
  const el = e.currentTarget
  pressTimer = setTimeout(() => openMenu(m, { currentTarget: el }), 450)
}
function pressEnd() { clearTimeout(pressTimer) }

const replyTo = ref(null) // tin đang trả lời
const REPLY_MARK = '↪ '
function quoteOf(content) {
  const [first, ...rest] = String(content || '').split('\n')
  if (!first.startsWith(REPLY_MARK) || !rest.length) return { quote: '', body: content }
  return { quote: first.slice(REPLY_MARK.length), body: rest.join('\n') }
}
const quoteText = (m) => (m.content || (m.attachment ? '[Ảnh]' : '')).split('\n').filter((l) => !l.startsWith(REPLY_MARK)).join(' ').slice(0, 60)
function menuReply() { replyTo.value = menu.value.m; menu.value = null; focusInput() }
async function menuCopy() {
  const m = menu.value.m
  menu.value = null
  try { await navigator.clipboard.writeText(quoteOf(m.content).body || m.content || '') } catch { messagesError.value = 'Không sao chép được' }
}
const pins = ref([]) // id các tin đã ghim của cuộc trò chuyện đang mở (lưu trên máy)
async function loadPins() { pins.value = (selectedFriendId.value && (await chat.metaGet(`pin:${selectedFriendId.value}`))) || [] }
watch(selectedFriendId, loadPins, { immediate: true })
const isPinned = (id) => pins.value.includes(id)
async function menuPin() {
  const id = menu.value.m.id
  menu.value = null
  pins.value = isPinned(id) ? pins.value.filter((x) => x !== id) : [...pins.value, id]
  await chat.metaSet(`pin:${selectedFriendId.value}`, pins.value.length ? pins.value : null)
}
const pinnedMsg = computed(() => {
  for (let i = pins.value.length - 1; i >= 0; i--) {
    const t = timeline.value.find((x) => x.kind === 'msg' && x.m.id === pins.value[i])
    if (t) return t.m
  }
  return null
})
const forwardOf = ref(null)
function menuForward() { forwardOf.value = menu.value.m; menu.value = null }
async function doForward(f) {
  const m = forwardOf.value
  forwardOf.value = null
  try {
    const body = quoteOf(m.content).body || ''
    const file = m.attachment?.blob ? new File([m.attachment.blob], m.attachment.name || 'anh.jpg', { type: m.attachment.type }) : null
    await chat.send(f, body, file)
    messagesError.value = ''
    openFriend(f)
  } catch (err) {
    messagesError.value = err.message || 'Không chuyển tiếp được'
  }
}
async function menuDelete() {
  const m = menu.value.m
  menu.value = null
  if (!(await showConfirm({ title: 'Xoá tin nhắn', message: 'Xoá tin nhắn này khỏi máy này? Người kia vẫn giữ bản của họ.', confirmText: 'Xoá', danger: true }))) return
  await chat.deleteMessage(m.id)
  if (isPinned(m.id)) pins.value = pins.value.filter((x) => x !== m.id)
  await loadMessages(selectedFriendId.value, { quiet: true })
}
function menuSelect() {
  const m = menu.value.m
  menu.value = null
  selecting.value = true
  if (m.content && !pickedIds.value.includes(m.id)) pickedIds.value.push(m.id)
}

// ---- Thanh dưới cùng: Danh bạ | Cuộc gọi | Tin nhắn | Cài đặt ----------------------------------------------------------
// Thanh dưới cùng (Danh bạ | Cuộc gọi | Tin nhắn | Cài đặt) hiện chỉ dành cho app: web ẩn đi (đổi true để hiện lại).
const SHOW_BOTTOM_NAV = false
const tab = ref('chats') // 'contacts' | 'calls' | 'chats' | 'settings'
const searchInput = ref(null)

// Lưu trữ cuộc trò chuyện: ẩn khỏi danh sách Tin nhắn, chỉ lưu trên máy này (theo tài khoản).
const archiveKey = () => `chat-archive:${auth.user?.id || ''}`
function readArchive() { try { return JSON.parse(localStorage.getItem(archiveKey()) || '[]') } catch { return [] } }
const archived = ref(readArchive())
function saveArchive() { try { localStorage.setItem(archiveKey(), JSON.stringify(archived.value)) } catch { /* private mode */ } }
const showArchived = ref(false)
const archivedCount = computed(() => friends.value.filter((f) => archived.value.includes(f.id)).length)

// Tin nhắn = những người đã có tin (hoặc đang mở), mới nhất trên; Danh bạ = mọi bạn bè theo tên.
const chatList = computed(() =>
  filteredFriends.value.filter(
    (f) => (archived.value.includes(f.id) === showArchived.value) && (!SHOW_BOTTOM_NAV || f.lastMessageAt || notify.unread[`friend:${f.id}`] || f.id === selectedFriendId.value || showArchived.value),
  ),
)
const contactList = computed(() => [...filteredFriends.value].sort((a, b) => displayName(a).localeCompare(displayName(b), 'vi')))

// Sửa (tab Tin nhắn): chọn nhiều cuộc trò chuyện để lưu trữ hoặc xoá.
const editPicked = ref([])
function toggleEditPick(id) {
  const i = editPicked.value.indexOf(id)
  if (i >= 0) editPicked.value.splice(i, 1)
  else editPicked.value.push(id)
}
function toggleEdit() { editMode.value = !editMode.value; editPicked.value = [] }
function archiveSelected() {
  const ids = editPicked.value
  if (showArchived.value) archived.value = archived.value.filter((id) => !ids.includes(id))
  else archived.value = [...new Set([...archived.value, ...ids])]
  saveArchive()
  if (ids.includes(selectedFriendId.value)) backToList()
  toggleEdit()
}
async function deleteSelected() {
  const ids = [...editPicked.value]
  if (!ids.length) return
  if (!(await showConfirm({
    title: 'Xoá cuộc trò chuyện',
    message: `Xoá ${ids.length} cuộc trò chuyện khỏi máy này? Tin nhắn và ảnh trong đó sẽ mất trên máy này (người kia vẫn giữ bản của họ). Bạn bè vẫn còn trong danh bạ.`,
    confirmText: 'Xoá',
    danger: true,
  }))) return
  for (const id of ids) await chat.deleteConversation(id)
  if (ids.includes(selectedFriendId.value)) backToList()
  await loadFriends({ quiet: true })
  toggleEdit()
}

// Cuộc gọi: lịch sử gần đây với mọi bạn bè.
const callRows = ref([])
const callsLoading = ref(false)
async function loadAllCalls() {
  callsLoading.value = true
  try {
    const res = await api.get('/me/calls?limit=60')
    callRows.value = res.calls
  } catch {
    callRows.value = []
  } finally {
    callsLoading.value = false
  }
}
watch(tab, (t) => { if (t === 'calls') loadAllCalls(); editMode.value = false; editPicked.value = [] })
const friendOf = (id) => friends.value.find((f) => f.id === id) || null
function callTime(iso) {
  const d = new Date(iso)
  return isNaN(d) ? '' : d.toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' })
}

// Thêm: Tin nhắn mới / Nhóm mới / Danh bạ mới.
const newOpen = ref(false)
const newMsgOpen = ref(false)
function pickNew(kind) {
  newOpen.value = false
  if (kind === 'message') newMsgOpen.value = true
  else if (kind === 'group') groupOpen.value = true
  else {
    if (SHOW_BOTTOM_NAV) tab.value = 'contacts'
    nextTick(() => searchInput.value?.focus())
  }
}
function startChat(f) { newMsgOpen.value = false; tab.value = 'chats'; openFriend(f) }

// Tên hiển thị riêng cho từng cuộc trò chuyện (lưu trên máy này, theo tài khoản).
const prefsKey = () => `chat-prefs:${auth.user?.id || ''}`
function readPrefs() { try { return JSON.parse(localStorage.getItem(prefsKey()) || '{}') } catch { return {} } }
const prefs = ref(readPrefs())
const displayName = (f) => (f ? prefs.value[f.id]?.alias || f.name : '')
const initial = (name) => (name || '?').trim().charAt(0).toUpperCase()
const settingsOpen = ref(false)
const aliasDraft = ref('')
function openSettings() { aliasDraft.value = prefs.value[selectedFriendId.value]?.alias || ''; settingsOpen.value = true }
function saveSettings() {
  const alias = aliasDraft.value.trim()
  const next = { ...prefs.value }
  if (alias && alias !== selectedFriend.value?.name) next[selectedFriendId.value] = { alias }
  else delete next[selectedFriendId.value]
  prefs.value = next
  try { localStorage.setItem(prefsKey(), JSON.stringify(next)) } catch { /* không lưu được: dùng tạm */ }
  settingsOpen.value = false
}

// Calls exist only between customers: nobody can call Admin and Admin calls
// nobody (chat with Admin is unaffected). The server enforces this too -
// hiding the buttons just avoids offering something that would be refused.
const canCall = computed(() => !auth.isAdmin && !!selectedFriend.value && !selectedFriend.value.isAdmin)


async function loadFriends({ quiet = false } = {}) {
  if (!quiet) loading.value = true
  loadError.value = ''
  try {
    const res = await api.get('/me/friends')
    await chat.rememberFriends(res.friends)
    const prev = await chat.previews()
    friends.value = res.friends
      .map((f) => ({ ...f, lastMessage: prev[f.id]?.text || null, lastMessageAt: prev[f.id]?.at || 0 }))
      .sort((a, b) => b.lastMessageAt - a.lastMessageAt || a.name.localeCompare(b.name, 'vi'))
  } catch (err) {
    loadError.value = err.message || 'Không tải được danh sách bạn bè'
  } finally {
    loading.value = false
  }
}

async function scrollToEnd() {
  await nextTick()
  if (threadBody.value) threadBody.value.scrollTop = threadBody.value.scrollHeight
}

async function loadMessages(friendId, { quiet = false } = {}) {
  if (!quiet) messagesLoading.value = true
  messagesError.value = ''
  try {
    const list = await chat.messages(friendId)
    const grew = list.length !== messages.value.length
    messages.value = list.map((m) => ({
      id: m.id,
      fromUserId: m.mine ? auth.user?.id : friendId,
      content: m.text,
      attachment: m.att,
      createdAt: new Date(m.createdAt).toISOString(),
      mine: m.mine,
      system: m.sys || null,
      status: m.status,
      reason: m.reason,
    }))
    if (!quiet || grew) scrollToEnd()
  } catch (err) {
    messagesError.value = err.message || 'Không đọc được tin nhắn trên thiết bị'
  } finally {
    messagesLoading.value = false
  }
}

// The customer's own Mã ID, shown at the top so they can read it out to
// someone who wants to add them. The server gives every account one; an
// account that has none is NOT given one here (just opening this page must
// not create an ID) - it is pointed to Tài khoản instead.
const myCode = ref('')
const noMyCode = ref(false)
const codeCopied = ref(false)
async function loadMyCode() {
  try {
    const res = await api.get('/me/customer-codes')
    myCode.value = res.codes?.[0]?.code || ''
    noMyCode.value = !myCode.value
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

// The local store opens a moment after the page (a reload on /friends/<id> asked for the messages too early): read them again once it is ready.
watch(
  () => chat.ready,
  (ok) => {
    if (!ok) return
    if (selectedFriendId.value) loadMessages(selectedFriendId.value, { quiet: true })
    loadFriends({ quiet: true })
    loadPins()
  },
  { immediate: true },
)

// Local chat store changed (incoming message, delivery status, auto-delete).
watch(
  () => chat.tick,
  () => {
    if (selectedFriendId.value) loadMessages(selectedFriendId.value, { quiet: true })
    loadFriends({ quiet: true })
  },
)

// Fallback when the push never arrived: the periodic unread refresh (AppShell) changed the
// counters, so bring the list order/preview - and the open conversation - up to date too.
watch(
  () => JSON.stringify(notify.unread),
  () => {
    const open = selectedFriendId.value
    if (open && notify.unread[`friend:${open}`]) {
      loadMessages(open, { quiet: true })
      notify.clear(`friend:${open}`)
    }
    loadFriends({ quiet: true })
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
    cancelPick()
    settingsOpen.value = false
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
  if ((!content && !attachment.value) || !selectedFriendId.value || !selectedFriend.value) return
  sending.value = true
  messagesError.value = ''
  try {
    const text = replyTo.value ? `${REPLY_MARK}${quoteText(replyTo.value)}\n${content}` : content
    await chat.send(selectedFriend.value, text, attachment.value)
    replyTo.value = null
    newMessage.value = ''
    attachment.value = null
    await loadMessages(selectedFriendId.value, { quiet: true })
    scrollToEnd()
  } catch (err) {
    messagesError.value = err.message || 'Không gửi được tin nhắn'
  } finally {
    sending.value = false
  }
}

async function retryMessage(m) {
  await chat.retry({ id: m.id, mine: true })
  await loadMessages(selectedFriendId.value, { quiet: true })
}

// A screenshot shortcut while this conversation is on screen: warn the friend (best effort).
const stopShotWatch = onScreenshotAttempt(() => {
  if (selectedFriend.value && !document.hidden && !auth.isAdmin) chat.notifyScreenshot(selectedFriend.value)
})
onBeforeUnmount(stopShotWatch)

const peerInfo = computed(() => chat.peerInfo[selectedFriendId.value] || null)
// Thêm: tạo nhóm. Giao diện đã có; nhóm chat chưa có trên máy chủ nên chưa tạo được nhóm thật.
// Mở cuộc trò chuyện: ô nhập CHƯA được chọn, không con trỏ, không bàn phím (cả bàn phím ảo của app lẫn bàn phím hệ thống), nội dung
// tin nhắn chiếm hết chỗ. Chạm vào ô nhập thì bàn phím hệ thống hiện như thường lệ; nút ⌨ mới bật bàn phím ảo của app (mặc định tắt).
const msgInput = ref(null)
const kbOpen = ref(false)
function focusInput() { nextTick(() => msgInput.value?.focus({ preventScroll: true })) }
function toggleKeyboard() { kbOpen.value = !kbOpen.value; if (kbOpen.value) focusInput() }

const groupOpen = ref(false)
const groupName = ref('')
const groupMembers = ref([])
function toggleMember(id) {
  const i = groupMembers.value.indexOf(id)
  if (i >= 0) groupMembers.value.splice(i, 1)
  else groupMembers.value.push(id)
}

const showSecurity = ref(false)
// Top-bar buttons control the auto-delete panel (ChatRetentionPanel) below the header.
const retentionOpen = ref(false)
const retentionRule = ref(null)
const retentionPanel = ref(null)
async function acceptKey() {
  await chat.acceptKeyChange(selectedFriendId.value)
}
</script>

<template>
  <div class="page friends-page">
    <div class="page-head">
      <div class="page-head-text">
        <h1 class="page-title">Bạn bè & tin nhắn</h1>
        <p class="page-subtitle">Kết bạn bằng mã ID và nhắn tin trực tiếp.</p>
      </div>
      <!-- Your own ID, top-right corner of the page -->
      <div v-if="myCode" class="my-id-corner">
        <span class="my-id-label">ID của bạn</span>
        <span class="my-id-code">{{ myCode }}</span>
        <AppButton variant="secondary" size="sm" @click="copyMyCode">{{ codeCopied ? 'Đã chép' : 'Sao chép' }}</AppButton>
      </div>
      <div v-else-if="noMyCode" class="my-id-corner">
        <span class="my-id-label">Chưa có ID. <router-link to="/account">Tạo ID trong Tài khoản.</router-link></span>
      </div>
    </div>

    <div class="split" :class="{ 'show-thread': !!selectedFriendId }">
      <div class="list-pane">
        <div class="card search-form">
          <div class="search-row">
            <button v-if="tab === 'chats'" type="button" class="tb-link" :aria-pressed="editMode" @click="toggleEdit">{{ editMode ? 'Xong' : 'Sửa' }}</button>
            <input id="searchQuery" ref="searchInput" v-model="searchQuery" type="search" aria-label="Tìm kiếm" placeholder="Tìm kiếm" autocomplete="off" />
            <button type="button" class="tb-link strong" @click="newOpen = true">Mới</button>
          </div>
          <p class="search-sub">Lọc bạn bè của bạn và tìm người mới để kết bạn.</p>
          <div v-if="searchError" class="alert alert-error" style="margin: 8px 0 0">{{ searchError }}</div>

          <!-- people who are not friends yet -->
          <div v-if="searchQuery.trim() && (searching || newPeople.length > 0)" class="search-results">
            <div class="search-group">Người mới</div>
            <div v-if="searching && newPeople.length === 0" class="search-hint">Đang tìm...</div>
            <div v-for="r in newPeople" :key="r.id" class="search-item">
              <div class="friend-info">
                <strong>{{ r.name }} <span v-if="r.isAdmin" class="chip chip-brand" style="font-size: 14px; padding: 1px 6px">Admin</span></strong>
                <span class="friend-last">@{{ r.username }}</span>
              </div>
              <AppButton variant="secondary" size="sm" :disabled="addingId === r.id" @click="addFromSearch(r)">{{ addingId === r.id ? '...' : 'Kết bạn' }}</AppButton>
            </div>
          </div>
        </div>

        <div v-if="loading" class="card">Đang tải...</div>
        <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
        <template v-else>
          <div v-if="searchQuery.trim() && filteredFriends.length > 0" class="search-group list-group">Bạn bè</div>

          <!-- Tin nhắn / Danh bạ -->
          <template v-if="tab === 'chats' || tab === 'contacts'">
            <div v-if="friends.length === 0" class="card">Chưa có bạn bè nào. Bấm Mới &gt; Danh bạ mới để tìm và kết bạn.</div>
            <div v-else-if="(tab === 'chats' ? chatList : contactList).length === 0">
              <div v-if="searchQuery.trim() && !searching && newPeople.length === 0" class="card">
                Không tìm thấy ai khớp với "{{ searchQuery.trim() }}". Nếu là mã ID, hãy kiểm tra lại các chữ số.
              </div>
              <div v-else-if="!searchQuery.trim()" class="card">
                {{ showArchived ? 'Chưa lưu trữ cuộc trò chuyện nào.' : 'Chưa có cuộc trò chuyện nào. Bấm Mới > Tin nhắn mới để bắt đầu.' }}
              </div>
            </div>
            <div v-else class="friend-list">
              <div
                v-for="f in (tab === 'chats' ? chatList : contactList)"
                :key="f.id"
                class="card friend-item"
                :class="{ active: f.id === selectedFriendId }"
                @click="editMode && tab === 'chats' ? toggleEditPick(f.id) : openFriend(f)"
              >
                <input v-if="editMode && tab === 'chats'" type="checkbox" class="pick" :checked="editPicked.includes(f.id)" aria-label="Chọn cuộc trò chuyện" @click.stop="toggleEditPick(f.id)" />
                <span class="avatar">{{ initial(displayName(f)) }}</span>
                <div class="friend-info">
                  <strong>
                    {{ displayName(f) }}
                    <span v-if="notify.unread[`friend:${f.id}`]" class="unread-badge" title="Tin nhắn chưa đọc">
                      {{ notify.unread[`friend:${f.id}`] > 99 ? '99+' : notify.unread[`friend:${f.id}`] }}
                    </span>
                    <span v-if="unseenMissed[f.id]" class="missed-badge" title="Cuộc gọi nhỡ">
                      <AppIcon name="phone" /> {{ unseenMissed[f.id] }}
                    </span>
                  </strong>
                  <span class="friend-last" :class="{ 'has-unread': notify.unread[`friend:${f.id}`] }">{{ tab === 'contacts' ? '@' + f.username : f.lastMessage || 'Chưa có tin nhắn' }}</span>
                </div>
              </div>
            </div>
            <div v-if="tab === 'chats' && editMode" class="edit-bar">
              <button type="button" class="tb-link" :disabled="!editPicked.length" @click="archiveSelected">{{ showArchived ? 'Bỏ lưu trữ' : 'Lưu trữ' }}{{ editPicked.length ? ` (${editPicked.length})` : '' }}</button>
              <button type="button" class="tb-link danger" :disabled="!editPicked.length" @click="deleteSelected">Xoá{{ editPicked.length ? ` (${editPicked.length})` : '' }}</button>
            </div>
            <button v-if="tab === 'chats' && !editMode && (archivedCount || showArchived)" type="button" class="tb-link archive-link" @click="showArchived = !showArchived">
              {{ showArchived ? '← Về tin nhắn' : `Đã lưu trữ (${archivedCount})` }}
            </button>
          </template>

          <!-- Cuộc gọi -->
          <template v-else-if="tab === 'calls'">
            <div v-if="callsLoading" class="card">Đang tải...</div>
            <div v-else-if="callRows.length === 0" class="card">Chưa có cuộc gọi nào.</div>
            <div v-else class="friend-list">
              <div v-for="c in callRows" :key="c.id" class="card friend-item" @click="friendOf(c.peerId) && openFriend(friendOf(c.peerId))">
                <span class="avatar">{{ initial(friendOf(c.peerId) ? displayName(friendOf(c.peerId)) : c.peerName) }}</span>
                <div class="friend-info">
                  <strong :class="{ 'missed-name': isMissedCall(c) }">{{ friendOf(c.peerId) ? displayName(friendOf(c.peerId)) : c.peerName }}</strong>
                  <span class="friend-last">{{ callLine(c) }} · {{ callTime(c.createdAt) }}</span>
                </div>
              </div>
            </div>
          </template>

          <!-- Cài đặt -->
          <template v-else>
            <div class="card chat-settings">
              <strong>Cài đặt tin nhắn</strong>
              <p class="search-sub">Tin nhắn mã hoá hai đầu, chỉ lưu trên máy này. Tên hiển thị riêng, mã bảo mật và tự xoá chỉnh ở nút ⚙ trong từng cuộc trò chuyện.</p>
              <button type="button" class="tb-link" @click="tab = 'chats'; showArchived = true">Cuộc trò chuyện đã lưu trữ ({{ archivedCount }})</button>
              <router-link class="tb-link" to="/account?tab=security">Bảo mật tài khoản</router-link>
              <p v-if="myCode" class="search-sub">ID của bạn: <strong>{{ myCode }}</strong></p>
            </div>
          </template>
        </template>

        <nav v-if="SHOW_BOTTOM_NAV" class="bottom-nav" aria-label="Điều hướng tin nhắn">
          <button type="button" :class="{ on: tab === 'contacts' }" @click="tab = 'contacts'"><AppIcon name="users" /><span>Danh bạ</span></button>
          <button type="button" :class="{ on: tab === 'calls' }" @click="tab = 'calls'"><AppIcon name="phone" /><span>Cuộc gọi</span></button>
          <button type="button" :class="{ on: tab === 'chats' }" @click="tab = 'chats'; showArchived = false"><AppIcon name="message-circle-more" /><span>Tin nhắn</span></button>
          <button type="button" :class="{ on: tab === 'settings' }" @click="tab = 'settings'"><AppIcon name="settings" /><span>Cài đặt</span></button>
        </nav>
      </div>

      <div class="thread-pane">
        <div v-if="!selectedFriendId" class="card empty-thread">Chọn một người bạn để xem tin nhắn.</div>
        <template v-else>
          <div class="thread-header">
            <button class="back-btn" aria-label="Quay lại danh sách" title="Quay lại" @click="backToList"><AppIcon name="arrow-left" /></button>
            <button type="button" class="who" title="Thông tin người trò chuyện" @click="openSettings">
              <span class="avatar sm">{{ initial(displayName(selectedFriend)) }}</span>
              <strong class="thread-title">{{ displayName(selectedFriend) || '...' }}</strong>
            </button>
            <button type="button" class="btn btn-ghost btn-sm gear" aria-label="Cài đặt cuộc trò chuyện" title="Cài đặt cuộc trò chuyện" @click="openSettings"><AppIcon name="settings" /></button>
            <div v-if="canCall" class="call-buttons">
              <AppButton variant="ghost" size="sm" icon="phone" title="Gọi thoại" :disabled="call.status !== 'idle' || call.acquiring" @click="selectedFriend && call.startCall(selectedFriend)"></AppButton>
            </div>
          </div>
          <div v-if="peerInfo?.changed" class="alert alert-warning e2ee-warn" role="alert">
            Khoá bảo mật của {{ selectedFriend?.name }} đã thay đổi (họ đổi máy hoặc xoá dữ liệu trình duyệt). Hãy xác minh mã bảo mật mới với họ qua kênh khác rồi bấm Đã hiểu.
            <AppButton variant="secondary" size="sm" @click="acceptKey">Đã hiểu</AppButton>
          </div>
          <div v-if="selectedFriend && !chat.friendKeys[selectedFriend.id]" class="alert alert-warning e2ee-warn">
            {{ selectedFriend.name }} chưa bật mã hoá 2 đầu (chưa mở phiên bản mới) nên chưa nhắn được.
          </div>
          <div class="e2ee-line">
            <span aria-hidden="true">🔒</span>
            <span>Mã hoá 2 đầu, không lưu trên máy chủ. Chỉ gửi được khi bạn bè đang online.</span>
          </div>
          <div v-if="showSecurity && peerInfo" class="e2ee-codes">
            <div>Của {{ selectedFriend?.name }}: <code>{{ peerInfo.fingerprint }}</code></div>
            <div>Của bạn: <code>{{ chat.myFingerprint }}</code></div>
            <div class="e2ee-hint">Đọc hai mã này cho nhau qua kênh khác (gọi điện, gặp mặt). Nếu khớp thì không ai chen giữa.</div>
          </div>
          <ChatRetentionPanel
            v-if="!selectedFriend?.isAdmin"
            :friend-id="selectedFriendId"
            :friend-name="selectedFriend?.name || ''"
            v-model:open="retentionOpen"
            ref="retentionPanel"
            @rule="(r) => (retentionRule = r)"
            @applied="loadMessages(selectedFriendId)"
          />
          <div v-if="pinnedMsg" class="pin-bar">
            <span>📌 {{ quoteText(pinnedMsg) }}</span>
            <button type="button" class="tb-link" aria-label="Bỏ ghim" @click="menu = { m: pinnedMsg }; menuPin()">✕</button>
          </div>
          <div v-if="messagesError" class="alert alert-error">{{ messagesError }}</div>
          <div ref="threadBody" class="card thread-body">
            <div v-if="messagesLoading">Đang tải tin nhắn...</div>
            <div v-else-if="timeline.length === 0" class="empty-thread">Chưa có tin nhắn nào.</div>
            <div v-else class="messages">
              <template v-for="item in timeline" :key="item.key">
                <div v-if="item.kind === 'msg' && item.m.system" class="sys-line" :class="{ failed: item.m.mine && item.m.status === 'failed' }">
                  <template v-if="item.m.system === 'screenshot'">📷 {{ selectedFriend?.name }} vừa chụp màn hình cuộc trò chuyện này</template>
                  <template v-else-if="item.m.status === 'failed'">📷 Bạn vừa chụp màn hình, nhưng {{ selectedFriend?.name }} đang offline nên chưa được báo</template>
                  <template v-else>📷 Bạn vừa chụp màn hình, {{ selectedFriend?.name }} đã được báo</template>
                </div>
                <div
                  v-else-if="item.kind === 'msg'"
                  class="msg"
                  :class="{ mine: item.m.mine, picking: selecting }"
                >
                  <input
                    v-if="selecting && item.m.content"
                    type="checkbox"
                    class="pick"
                    aria-label="Chọn tin nhắn"
                    :checked="pickedIds.includes(item.m.id)"
                    @change="togglePick(item.m.id)"
                  />
                  <div
                    class="msg-bubble"
                    @contextmenu.prevent="openMenu(item.m, $event)"
                    @touchstart.passive="pressStart(item.m, $event)"
                    @touchend="pressEnd"
                    @touchmove="pressEnd"
                    @touchcancel="pressEnd"
                  >
                    <span v-if="isPinned(item.m.id)" class="pin-mark" title="Đã ghim">📌</span>
                    <div v-if="quoteOf(item.m.content).quote" class="quote">{{ quoteOf(item.m.content).quote }}</div>
                    <span v-if="item.m.content">{{ quoteOf(item.m.content).body }}</span>
                    <MessageAttachment
                      v-if="item.m.attachment"
                      :att="item.m.attachment"
                      :blob="item.m.attachment.blob"
                    />
                  </div>
                  <div v-if="item.m.mine && item.m.status === 'failed'" class="msg-state msg-failed">
                    {{ chat.reasonText(item.m.reason) }}
                    <AppButton variant="ghost" size="sm" @click="retryMessage(item.m)">Gửi lại</AppButton>
                  </div>
                  <div v-else-if="item.m.mine && item.m.status !== 'delivered'" class="msg-state">
                    {{ item.m.status === 'sending' ? 'Đang gửi...' : 'Đã gửi, chờ xác nhận...' }}
                  </div>
                </div>
                <div v-else class="call-line" :class="{ missed: isMissedCall(item.c) || item.c.status === 'failed' }">
                  <AppIcon name="phone" />
                  <span>{{ callLine(item.c) }}</span>
                  <AppButton variant="ghost" size="sm" v-if="canCall && (isMissedCall(item.c) || item.c.status === 'rejected' || item.c.status === 'failed')" :disabled="call.status !== 'idle' || call.acquiring" @click="selectedFriend && call.startCall(selectedFriend)">Gọi lại</AppButton>
                </div>
              </template>
            </div>
          </div>
          <AttachmentPreview v-if="attachment" :file="attachment" @remove="attachment = null" />
          <div v-if="selecting" class="selbar">
            <span>Đã chọn {{ pickedIds.length }}</span>
            <button type="button" class="tb-link" @click="pickAll">Chọn tất cả</button>
            <button type="button" class="tb-link" @click="pickedIds = []">Bỏ chọn</button>
            <button type="button" class="tb-link" @click="cancelPick">Hủy</button>
          </div>
          <div v-if="replyTo" class="reply-bar">
            <span>↪ Trả lời: {{ quoteText(replyTo) }}</span>
            <button type="button" class="tb-link" aria-label="Bỏ trả lời" @click="replyTo = null">✕</button>
          </div>
          <div class="send-tools">
            <button type="button" class="calc-btn" :class="{ ready: selecting && pickedIds.length }" @click="onAction">{{ actionLabel }}</button>
            <button type="button" class="kb-toggle" :aria-pressed="kbOpen" :title="kbOpen ? 'Ẩn bàn phím' : 'Hiện bàn phím'" @click="toggleKeyboard">⌨</button>
          </div>
          <form class="send-row" @submit.prevent="sendMessage">
            <ChatAttachButtons icon="paperclip" :disabled="sending" @pick="(f) => { attachment = f; messagesError = '' }" @error="(m) => (messagesError = m)" />
            <input ref="msgInput" v-model="newMessage" type="text" placeholder="Nhập tin nhắn..." :inputmode="kbOpen ? 'none' : 'text'" autocomplete="off" />
            <AppButton variant="primary" type="submit" :disabled="sending || (!newMessage.trim() && !attachment)">Gửi</AppButton>
          </form>
          <ChatKeyboard v-if="kbOpen" v-model="newMessage" :can-send="!sending && (!!newMessage.trim() || !!attachment)" @enter="sendMessage" />
        </template>
      </div>
    </div>

    <div v-if="settingsOpen && selectedFriend" class="group-overlay" @click.self="settingsOpen = false">
      <div class="card group-sheet" role="dialog" aria-label="Cài đặt cuộc trò chuyện">
        <div class="set-head">
          <span class="avatar big">{{ initial(aliasDraft.trim() || selectedFriend.name) }}</span>
          <strong>{{ aliasDraft.trim() || selectedFriend.name }}</strong>
        </div>
        <label class="set-field">Tên hiển thị
          <input v-model="aliasDraft" type="text" :placeholder="selectedFriend.name" maxlength="40" />
        </label>
        <p class="search-sub">Chỉ đổi cách hiển thị trên máy này, người kia không thấy.</p>
        <div class="set-tools">
          <button v-if="peerInfo" type="button" class="tb-link" @click="showSecurity = !showSecurity; settingsOpen = false">Mã bảo mật</button>
          <button v-if="!selectedFriend.isAdmin" type="button" class="tb-link" @click="retentionOpen = !retentionOpen; settingsOpen = false">Cài đặt tự xoá</button>
          <button v-if="retentionRule" type="button" class="tb-link" @click="retentionPanel?.cancel(); settingsOpen = false">Tắt tự xoá</button>
          <button type="button" class="tb-link danger" @click="settingsOpen = false; removeFriend(selectedFriend)">Xoá khỏi bạn bè</button>
        </div>
        <div class="group-actions">
          <button type="button" class="tb-link" @click="settingsOpen = false">Đóng</button>
          <button type="button" class="tb-link strong" @click="saveSettings">Lưu</button>
        </div>
      </div>
    </div>

    <!-- menu nhấn giữ tin nhắn -->
    <div v-if="menu" class="msg-menu-overlay" @click="menu = null" @contextmenu.prevent="menu = null">
      <div class="card msg-menu" role="menu" :style="{ left: menu.x + 'px', top: menu.y + 'px' }" @click.stop>
        <button type="button" role="menuitem" class="tb-link" @click="menuReply">Trả lời</button>
        <button v-if="menu.m.content" type="button" role="menuitem" class="tb-link" @click="menuCopy">Sao chép</button>
        <button type="button" role="menuitem" class="tb-link" @click="menuPin">{{ isPinned(menu.m.id) ? 'Bỏ ghim' : 'Ghim' }}</button>
        <button type="button" role="menuitem" class="tb-link" @click="menuForward">Chuyển tiếp</button>
        <button type="button" role="menuitem" class="tb-link danger" @click="menuDelete">Xoá</button>
        <button v-if="menu.m.content" type="button" role="menuitem" class="tb-link" @click="menuSelect">Chọn</button>
      </div>
    </div>

    <div v-if="forwardOf" class="group-overlay" @click.self="forwardOf = null">
      <div class="card group-sheet" role="dialog" aria-label="Chuyển tiếp">
        <strong>Chuyển tiếp tới</strong>
        <ul class="group-members">
          <li v-for="f in friends.filter((x) => !x.isAdmin)" :key="f.id"><button type="button" class="tb-link new-opt" @click="doForward(f)">{{ displayName(f) }}</button></li>
          <li v-if="!friends.length" class="search-hint">Chưa có bạn bè.</li>
        </ul>
        <div class="group-actions"><button type="button" class="tb-link" @click="forwardOf = null">Đóng</button></div>
      </div>
    </div>

    <ChatDecodeDialog :open="decodeOpen" :messages="decodeMessages" :bet-types="decodeTypes" :kind-symbols="decodeSymbols" @close="decodeOpen = false" @use="useDecoded" @calc="startCalc" />
    <ChatCalcDialog :open="calcOpen" :text="calcText" :date="calcDate" :customer-id="calcCustomer" :friends="friends.filter((f) => !f.isAdmin)" @close="calcOpen = false" @back="calcBack" />

    <div v-if="newOpen" class="group-overlay" @click.self="newOpen = false">
      <div class="card group-sheet" role="dialog" aria-label="Tạo mới">
        <strong>Tạo mới</strong>
        <button type="button" class="tb-link new-opt" @click="pickNew('message')">Tin nhắn mới</button>
        <button type="button" class="tb-link new-opt" @click="pickNew('group')">Nhóm mới</button>
        <button type="button" class="tb-link new-opt" @click="pickNew('contact')">Danh bạ mới</button>
        <div class="group-actions"><button type="button" class="tb-link" @click="newOpen = false">Đóng</button></div>
      </div>
    </div>

    <div v-if="newMsgOpen" class="group-overlay" @click.self="newMsgOpen = false">
      <div class="card group-sheet" role="dialog" aria-label="Tin nhắn mới">
        <strong>Tin nhắn mới</strong>
        <ul class="group-members">
          <li v-for="f in contactList" :key="f.id"><button type="button" class="tb-link new-opt" @click="startChat(f)">{{ displayName(f) }}</button></li>
          <li v-if="!friends.length" class="search-hint">Chưa có bạn bè. Chọn Danh bạ mới để tìm người và kết bạn.</li>
        </ul>
        <div class="group-actions"><button type="button" class="tb-link" @click="newMsgOpen = false">Đóng</button></div>
      </div>
    </div>

    <div v-if="groupOpen" class="group-overlay" @click.self="groupOpen = false">
      <div class="card group-sheet" role="dialog" aria-label="Tạo nhóm">
        <strong>Tạo nhóm</strong>
        <input v-model="groupName" type="text" placeholder="Tên nhóm" />
        <ul class="group-members">
          <li v-for="f in friends" :key="f.id">
            <label><input type="checkbox" :checked="groupMembers.includes(f.id)" @change="toggleMember(f.id)" /> {{ f.name }}</label>
          </li>
          <li v-if="!friends.length" class="search-hint">Chưa có bạn bè nào để thêm vào nhóm.</li>
        </ul>
        <p class="search-sub">Nhóm chat chưa có trên máy chủ nên chưa tạo được nhóm thật.</p>
        <div class="group-actions">
          <AppButton variant="ghost" size="sm" @click="groupOpen = false">Đóng</AppButton>
          <AppButton variant="primary" size="sm" disabled>Tạo nhóm</AppButton>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Giao diện sáng theo yêu cầu khách: nền trắng, viền xanh mảnh, chữ đen, phụ xám nhạt; không nền tối, không xanh dương, không gradient. */
.friends-page {
  --background: #fff; --card: #fff; --surface: #fff; --surface-2: #fff; --bg: #fff;
  --text: #000; --text-primary: #000; --text-secondary: #8a8f8a; --muted: #8a8f8a;
  --border: #d9e8dd; --input-border: #16a34a; --input-border-hover: #15803d;
  --primary: #16a34a; --primary-hover: #15803d; --on-primary: #fff; --on-primary-hover: #fff;
  --primary-soft: #f0fdf4; --accent: #16a34a; --accent-strong: #16a34a; --accent-soft: #f0fdf4; --link: #16a34a;
  --shadow-sm: none; --shadow-md: none; --shadow-lg: none; --overlay: rgba(0, 0, 0, 0.25);
  background: #fff; color: #000; color-scheme: light; border-radius: 10px; padding: 12px;
}
.friends-page :deep(.btn-primary) { background: #16a34a; border-color: #16a34a; color: #fff; background-image: none; }
.search-row { display: flex; align-items: center; gap: 8px; }
.search-row input { flex: 1; border: 1px solid #16a34a !important; border-radius: 18px !important; padding: 7px 12px !important; background: #fff !important; color: #000 !important; }
.tb-link { background: none; border: 0; color: #000; font-size: 15px; cursor: pointer; padding: 4px; }
.tb-link.strong { color: #16a34a; font-weight: 600; }
.tb-link:disabled { color: #8a8f8a; cursor: default; }
.avatar { width: 40px; height: 40px; border-radius: 50%; border: 1px solid #16a34a; color: #16a34a; display: grid; place-items: center; font-weight: 600; flex: none; background: #fff; }
.avatar.sm { width: 28px; height: 28px; font-size: 13px; }
.avatar.big { width: 64px; height: 64px; font-size: 26px; }
.friend-item { gap: 10px; }
.friend-item .friend-info { flex: 1; }
.pick { accent-color: #16a34a; width: 18px; height: 18px; margin-right: 8px; align-self: center; }
.msg.picking { display: flex; align-items: flex-start; }
.msg.picking.mine { flex-direction: row-reverse; }
.selbar { display: flex; align-items: center; gap: 10px; padding: 6px 4px; font-size: 13px; }
.selbar span { flex: 1; color: #8a8f8a; }
.calc-note { color: #8a8f8a; font-size: 13px; margin: 2px 4px; }
.calc-btn { padding: 7px 12px; border: 1px solid #16a34a; border-radius: 16px; background: #fff; color: #16a34a; font-size: 13px; cursor: pointer; white-space: nowrap; }
.calc-btn.ready { background: #16a34a; color: #fff; }
.set-head { display: flex; flex-direction: column; align-items: center; gap: 6px; }
.set-field { display: flex; flex-direction: column; gap: 4px; font-size: 13px; color: #8a8f8a; }
.set-tools { display: flex; flex-wrap: wrap; gap: 4px 12px; }
.group-overlay { position: fixed; inset: 0; background: rgba(0, 0, 0, 0.35); display: grid; place-items: center; z-index: 50; }
.group-sheet { width: min(380px, 92vw); display: flex; flex-direction: column; gap: 10px; }
.group-sheet input[type='text'] { width: 100%; box-sizing: border-box; }
.group-members { list-style: none; margin: 0; padding: 0; max-height: 220px; overflow-y: auto; }
.group-members label { display: flex; gap: 8px; padding: 5px 0; }
.group-actions { display: flex; justify-content: space-between; }
.my-id-label {
  font-size: 14px;
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
.search-form input {
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
  font-size: 14px;
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
.bottom-nav { position: sticky; bottom: 0; display: grid; grid-template-columns: repeat(4, 1fr); margin-top: 12px; background: #fff; border-top: 1px solid #d9e8dd; }
.bottom-nav button { display: flex; flex-direction: column; align-items: center; gap: 2px; padding: 8px 4px; background: none; border: 0; color: #8a8f8a; font-size: 12px; cursor: pointer; }
.bottom-nav button.on { color: #16a34a; font-weight: 600; }
.edit-bar { display: flex; justify-content: space-between; padding: 10px 4px; border-top: 1px solid #d9e8dd; }
.tb-link.danger { color: #b91c1c; }
.archive-link { display: block; margin: 8px auto 0; color: #16a34a; }
.new-opt { display: block; width: 100%; text-align: left; padding: 10px 4px; }
.chat-settings { display: flex; flex-direction: column; gap: 10px; align-items: flex-start; }
.missed-name { color: #b91c1c; }
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
  font-size: 14px;
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
.sys-line {
  align-self: center;
  margin: 6px 0;
  padding: 4px 12px;
  font-size: 12.5px;
  color: var(--danger-text);
  text-align: center;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 999px;
}
.sys-line.failed {
  color: var(--text-secondary);
}
.thread-tools {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  align-items: center;
  gap: 2px 4px;
}
.thread-tools .btn {
  white-space: nowrap;
}
/* Narrow screens: name + call icon on the first row, the tools on their own row below. */
@media (max-width: 640px) {
  .thread-header {
    flex-wrap: wrap;
  }
  .thread-tools {
    order: 5;
    flex: 1 0 100%;
    justify-content: flex-start;
  }
}
.call-buttons {
  display: flex;
  gap: 4px;
}
.back-btn {
  flex: none;
  width: 40px;
  height: 40px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 22px;
  color: #000;
  background: #fff;
  border: 1px solid #16a34a;
  border-radius: 50%;
  cursor: pointer;
}
.who { display: flex; align-items: center; gap: 10px; flex: 1; min-width: 0; padding: 0; background: none; border: 0; text-align: left; cursor: pointer; color: inherit; }
.msg-menu-overlay { position: fixed; inset: 0; z-index: 80; }
.msg-menu { position: fixed; min-width: 170px; padding: 6px; display: flex; flex-direction: column; background: #fff; border: 1px solid #d9e8dd; border-radius: 12px; box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12); }
.msg-menu .tb-link { text-align: left; padding: 10px 12px; font-size: 15px; }
.quote { margin-bottom: 4px; padding: 3px 8px; font-size: 13px; color: #6b716c; border-left: 3px solid #16a34a; background: #f6faf7; border-radius: 4px; }
.pin-mark { margin-right: 4px; font-size: 12px; }
.pin-bar, .reply-bar { display: flex; justify-content: space-between; align-items: center; gap: 8px; margin: 0 0 6px; padding: 4px 10px; font-size: 13.5px; background: #f0fdf4; border-left: 3px solid #16a34a; border-radius: 6px; }
.pin-bar span, .reply-bar span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.send-tools { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
.kb-toggle { flex: none; width: 40px; height: 40px; font-size: 20px; background: #fff; color: #16a34a; border: 1px solid #d9e8dd; border-radius: 10px; cursor: pointer; }
.kb-toggle[aria-pressed='true'] { background: #f0fdf4; border-color: #16a34a; }
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
.e2ee-line {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 8px;
  font-size: 13px;
  color: var(--text-secondary);
}
.e2ee-line span:not([aria-hidden]) {
  flex: 1;
}
.e2ee-warn {
  margin-bottom: 8px;
}
.e2ee-codes {
  margin-bottom: 8px;
  padding: 8px 10px;
  font-size: 13px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.e2ee-codes code {
  letter-spacing: 0.04em;
  overflow-wrap: anywhere;
}
.e2ee-hint {
  margin-top: 4px;
  color: var(--text-secondary);
}
.msg-state {
  padding: 2px 4px 0;
  font-size: 12px;
  color: var(--text-secondary);
}
.msg-failed {
  color: var(--danger-text);
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
  font-size: 14px;
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
  flex-direction: column;
  align-items: flex-start;
}
.msg.mine {
  align-items: flex-end;
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
    /* minmax(0, ...) lets the column shrink to the screen; a plain 1fr stretched to the
       widest content inside it and pushed the cards past the right edge on phones. */
    grid-template-columns: minmax(0, 1fr);
  }
  .list-pane,
  .thread-pane {
    min-width: 0;
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
  /* Điện thoại: màn hình trò chuyện chiếm trọn màn hình, tin nhắn cuộn ở giữa, ô nhập và bàn phím sát đáy */
  .split.show-thread .thread-pane {
    display: flex;
    position: fixed;
    inset: 0;
    z-index: 70;
    height: 100dvh;
    padding: 10px 10px env(safe-area-inset-bottom);
    background: #fff;
    border: 0;
    border-radius: 0;
  }
  .split.show-thread .thread-pane .thread-body {
    flex: 1;
    min-height: 0;
    max-height: none;
  }
}
/* ---- One unified left panel (ID, search, add by ID, friend list) ---- */
/* wide screens only: on phones the single-column rule in the media query above must win */
@media (min-width: 801px) {
  .split {
    grid-template-columns: 380px minmax(0, 1fr);
    gap: 16px;
    align-items: start;
  }
}
.list-pane {
  padding: 16px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: var(--shadow-sm);
}
/* the former small cards become flat sections separated by hairlines */
.list-pane > .search-form {
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
  font-size: 14px;
  color: var(--text-secondary);
}
.my-id-code {
  font-size: 22px;
  letter-spacing: 2px;
  line-height: 1.2;
  color: var(--text-primary);
}
.my-id-corner .btn,
.search-item .btn {
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
  font-size: 14px;
  color: var(--text-secondary);
  max-width: none;
}
.friend-item .btn-ghost {
  min-height: 32px;
  padding: 0 10px;
  font-size: 14px;
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
  white-space: pre-wrap; /* giữ xuống dòng của tin (vd. báo cáo kết quả) */
  overflow-wrap: anywhere;
}
.msg.mine .msg-bubble {
  background: var(--primary-soft);
  color: var(--text-primary);
}
.send-row input {
  /* min-width:0 lets the box shrink; otherwise its intrinsic width pushed "Gửi" off a phone screen */
  flex: 1 1 0;
  min-width: 0;
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
  flex: none;
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
.call-buttons .btn,
.thread-header .gear {
  width: 44px;
  height: 44px;
  min-height: 44px;
  padding: 0;
  font-size: 20px;
  color: var(--text-secondary);
  border-radius: 10px;
}
.call-buttons .btn:hover:not(:disabled),
.thread-header .gear:hover {
  color: var(--text-primary);
  background: var(--surface);
}
.call-buttons .btn:disabled {
  opacity: 0.45;
}

/* Page header: title on the left, own ID in the top-right corner */
.page-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 20px;
}
.page-head .page-subtitle {
  margin-bottom: 0;
}
.my-id-corner {
  flex: none;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
  text-align: right;
}
.my-id-corner .my-id-code {
  font-size: 22px;
  font-weight: 800;
  letter-spacing: 2px;
  line-height: 1.15;
  color: var(--accent-strong);
  font-variant-numeric: tabular-nums;
}
.my-id-corner .btn {
  margin-top: 4px;
}
@media (max-width: 480px) {
  .my-id-corner .my-id-code {
    font-size: 19px;
    letter-spacing: 1px;
  }
}

/* the single search box: short explanation, and small group headings for its two kinds of results */
.search-sub {
  margin: 6px 0 0;
  font-size: 14px;
  color: var(--muted);
}
.search-group {
  margin: 12px 0 6px;
  font-size: 14px;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--muted);
}
.list-group {
  margin-top: 0;
}
</style>
