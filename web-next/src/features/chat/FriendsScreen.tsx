'use client'
/* eslint-disable react-hooks/set-state-in-effect, react-hooks/exhaustive-deps, @typescript-eslint/no-explicit-any */
import './Friends.css'
import Link from 'next/link'
import { useRouter, useSearchParams } from 'next/navigation'
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppIcon from '@/components/AppIcon'
import AttachmentPreview from '@/components/AttachmentPreview'
import ChatAttachButtons from '@/components/ChatAttachButtons'
import MessageAttachment from '@/components/MessageAttachment'
import { api } from '@/lib/api'
import { useAuthStore } from '@/lib/authStore'
import { showConfirm } from '@/lib/confirm'
import { badgeText, incomingFrom, interpretAddResponse, normalizeRequests, removeRequest, searchAction, showRequestsBlock, upsertFriend } from '@/lib/friendRequests'
import { isGroupId } from '@/lib/e2ee/groups'
import { fold } from '@/lib/messageParser'
import { useNotifyStore } from '@/lib/notifyStore'
import { kindSymbolsFor, typesOf } from '@/lib/scoringConfig'
import { onScreenshotAttempt } from '@/lib/screenshotGuard'
import { useCallStore } from '@/features/calls/callStore'
import PasswordPromptDialog from '@/components/PasswordPromptDialog'
import ChatCalcDialog from './ChatCalcDialog'
import ChatDecodeDialog from './ChatDecodeDialog'
import ChatRetentionPanel, { type RetentionHandle, type RetentionRule } from './ChatRetentionPanel'
import { callLine, isMissedCall, peerOfflineLabel, quoteOf, quoteText, REPLY_MARK } from './chatView'
import { useChatStore } from './chatStore'

// Friend list + message thread (port of views/FriendsView.vue). Desktop: list left, thread right; phones: two "screens"
// driven by the address `/friends?thread=<id>` (nginx rewrites the old /friends/<id>).
//
// Messages are end-to-end encrypted: composed, encrypted and kept only on this device (chatStore), relayed live over the
// WebSocket to a friend who is online. Nothing is stored on the server (docs/MA_HOA_2_DAU.md). Voice calls go through the
// call store; the call UI is <CallOverlay /> in the app shell.
const SHOW_BOTTOM_NAV = false // the bottom bar (Danh bạ | Cuộc gọi | Tin nhắn | Cài đặt) is for the app only
type Tab = 'contacts' | 'calls' | 'chats' | 'settings'

const jsonKey = (k: string) => {
  try { return JSON.parse(localStorage.getItem(k) || 'null') } catch { return null }
}
const saveKey = (k: string, v: unknown) => {
  try { localStorage.setItem(k, JSON.stringify(v)) } catch { /* private mode */ }
}
const initial = (name?: string) => (name || '?').trim().charAt(0).toUpperCase()
const callTime = (iso: string) => {
  const d = new Date(iso)
  return isNaN(d.getTime()) ? '' : d.toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' })
}

export default function FriendsScreen() {
  const router = useRouter()
  const params = useSearchParams()
  const selectedId = params.get('thread')
  const user = useAuthStore((s) => s.user)
  const isAdmin = useAuthStore((s) => s.role === 'admin')

  const unread = useNotifyStore((s) => s.unread)
  const friendRequestCount = useNotifyStore((s) => s.friendRequests)
  const requestsTick = useNotifyStore((s) => s.requestsTick)
  const incomingTick = useNotifyStore((s) => s.incomingTick)
  const chatReady = useChatStore((s) => s.ready)
  const chatTick = useChatStore((s) => s.tick)
  const friendKeys = useChatStore((s) => s.friendKeys)
  const groups = useChatStore((s) => s.groups)
  const peerInfoMap = useChatStore((s) => s.peerInfo)
  const myFingerprint = useChatStore((s) => s.myFingerprint)
  const callStatus = useCallStore((s) => s.status)
  const callAcquiring = useCallStore((s) => s.acquiring)
  const callEndedTick = useCallStore((s) => s.endedTick)
  const socketReady = useCallStore((s) => s.socketReady)
  const chat = useChatStore.getState
  const notify = useNotifyStore.getState

  const [friends, setFriends] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')

  // ---- search + friend requests ----
  const [searchOpen, setSearchOpen] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [searchResults, setSearchResults] = useState<any[]>([])
  const [searching, setSearching] = useState(false)
  const [searchError, setSearchError] = useState('')
  const [searchNotice, setSearchNotice] = useState('')
  const [addingId, setAddingId] = useState<string | null>(null)
  const [requests, setRequests] = useState<{ incoming: any[]; outgoing: any[] }>({ incoming: [], outgoing: [] })
  const [requestBusy, setRequestBusy] = useState<string | null>(null)
  const [requestError, setRequestError] = useState('')
  const searchInput = useRef<HTMLInputElement>(null)
  const requestsRef = useRef(requests)
  requestsRef.current = requests

  // One search box filters the friends you have (without accents) AND looks for other people on the server.
  const q = fold(searchQuery.trim())
  const filteredFriends = useMemo(() => {
    if (!q) return friends
    const byId = new Set(searchResults.filter((r) => r.isFriend).map((r) => r.id))
    return friends.filter((f) => fold(f.name).includes(q) || fold(f.username).includes(q) || byId.has(f.id))
  }, [friends, q, searchResults])
  const newPeople = searchResults.filter((r) => !r.isFriend)

  useEffect(() => {
    setSearchNotice('')
    const query = searchQuery.trim()
    if (!query) {
      setSearchResults([])
      setSearching(false)
      return
    }
    setSearching(true)
    const t = setTimeout(async () => {
      setSearchError('')
      try {
        const res = await api.get(`/me/friends/search?q=${encodeURIComponent(query)}`)
        setSearchResults(res.results)
      } catch (err) {
        setSearchError((err as Error).message || 'Không tìm kiếm được')
      } finally {
        setSearching(false)
      }
    }, 300)
    return () => clearTimeout(t)
  }, [searchQuery])

  const loadRequests = useCallback(async () => {
    try {
      const r = normalizeRequests(await api.get('/me/friend-requests'))
      setRequests(r)
      notify().setFriendRequests(r.incoming.length)
    } catch { /* the block is a nicety - keep whatever we have */ }
  }, [])

  const loadFriends = useCallback(async ({ quiet = false } = {}) => {
    if (!quiet) setLoading(true)
    setLoadError('')
    try {
      const res = await api.get('/me/friends')
      await chat().rememberFriends(res.friends)
      const prev = await chat().previews()
      // Group chats (kept on this device only) are rows of the same list.
      const groupRows = Object.values(chat().groups).map((g: any) => {
        const p = prev[g.id]
        const last = p ? `${p.mine ? 'Bạn' : chat().memberName(g, p.from)}: ${p.text}` : null
        return { id: g.id, name: g.name, username: '', isGroup: true, memberCount: g.members.length, lastMessage: last, lastMessageAt: p?.at || g.updatedAt }
      })
      setFriends(
        [
          ...res.friends.map((f: any) => ({ ...f, lastMessage: prev[f.id]?.text || null, lastMessageAt: prev[f.id]?.at || 0 })),
          ...groupRows,
        ].sort((a, b) => b.lastMessageAt - a.lastMessageAt || a.name.localeCompare(b.name, 'vi')),
      )
    } catch (err) {
      setLoadError((err as Error).message || 'Không tải được danh sách bạn bè')
    } finally {
      setLoading(false)
    }
  }, [])

  async function addFromSearch(r: any) {
    setAddingId(r.id)
    setSearchError('')
    setSearchNotice('')
    try {
      const res = await api.post('/me/friends', { userId: r.id })
      const out = interpretAddResponse(res, r.name)
      if (out.kind === 'friends') {
        setFriends((cur) => upsertFriend(cur, out.friend))
        setSearchResults((cur) => cur.map((x) => (x.id === r.id ? { ...x, isFriend: true } : x)))
        loadFriends({ quiet: true })
      } else setSearchResults((cur) => cur.map((x) => (x.id === r.id ? { ...x, requestState: 'outgoing' } : x)))
      setSearchNotice(out.message)
      loadRequests()
    } catch (err) {
      setSearchError((err as Error).message || 'Không gửi được lời mời kết bạn')
    } finally {
      setAddingId(null)
    }
  }

  async function acceptRequest(req: any, searchRow: any = null) {
    setRequestBusy(req.id)
    setRequestError('')
    setSearchError('')
    try {
      const res = await api.post(`/me/friend-requests/${encodeURIComponent(req.id)}/accept`, {})
      setRequests((cur) => ({ ...cur, incoming: removeRequest(cur.incoming, req.id) }))
      notify().setFriendRequests(removeRequest(requestsRef.current.incoming, req.id).length)
      if (res?.friend) setFriends((cur) => upsertFriend(cur, res.friend))
      const fromId = searchRow?.id || req.fromId
      setSearchResults((cur) => cur.map((x) => (x.id === fromId ? { ...x, isFriend: true, requestState: 'none' } : x)))
      await loadFriends({ quiet: true })
    } catch (err) {
      const msg = (err as Error).message || 'Không chấp nhận được lời mời'
      if (searchRow) setSearchError(msg)
      else setRequestError(msg)
      loadRequests()
    } finally {
      setRequestBusy(null)
    }
  }
  async function acceptFromSearch(r: any) {
    let req = incomingFrom(requestsRef.current.incoming, r.id)
    if (!req) {
      await loadRequests()
      req = incomingFrom(requestsRef.current.incoming, r.id)
      if (!req) return
    }
    return acceptRequest(req, r)
  }
  const onSearchButton = (r: any) => {
    const a = searchAction(r).action
    if (a === 'add') addFromSearch(r)
    else if (a === 'accept') acceptFromSearch(r)
  }
  async function declineRequest(req: any) {
    setRequestBusy(req.id)
    setRequestError('')
    try {
      await api.post(`/me/friend-requests/${encodeURIComponent(req.id)}/decline`, {})
      setRequests((cur) => ({ ...cur, incoming: removeRequest(cur.incoming, req.id) }))
      notify().setFriendRequests(removeRequest(requestsRef.current.incoming, req.id).length)
    } catch (err) {
      setRequestError((err as Error).message || 'Không từ chối được lời mời')
      loadRequests()
    } finally {
      setRequestBusy(null)
    }
  }
  async function cancelRequest(req: any) {
    setRequestBusy(req.id)
    setRequestError('')
    try {
      await api.del(`/me/friend-requests/${encodeURIComponent(req.id)}`)
      setRequests((cur) => ({ ...cur, outgoing: removeRequest(cur.outgoing, req.id) }))
      setSearchResults((cur) => cur.map((x) => (x.id === req.toId ? { ...x, requestState: 'none' } : x)))
    } catch (err) {
      setRequestError((err as Error).message || 'Không huỷ được lời mời')
      loadRequests()
    } finally {
      setRequestBusy(null)
    }
  }
  const hasRequests = requests.incoming.length + requests.outgoing.length > 0

  // ---- open conversation ----
  const [messages, setMessages] = useState<any[]>([])
  const [messagesLoading, setMessagesLoading] = useState(false)
  const [messagesError, setMessagesError] = useState('')
  const [newMessage, setNewMessage] = useState('')
  const [sending, setSending] = useState(false)
  const [attachment, setAttachment] = useState<File | null>(null)
  const [calls, setCalls] = useState<any[]>([])
  const [unseenMissed, setUnseenMissed] = useState<Record<string, number>>({})
  const threadBody = useRef<HTMLDivElement>(null)
  const msgInput = useRef<HTMLInputElement>(null)
  const selectedRef = useRef(selectedId)
  selectedRef.current = selectedId
  const selectedFriend = friends.find((f) => f.id === selectedId) || null

  const scrollToEnd = () => setTimeout(() => { if (threadBody.current) threadBody.current.scrollTop = threadBody.current.scrollHeight }, 0)

  const timeline = useMemo(() => {
    const items = [
      ...messages.map((m) => ({ kind: 'msg' as const, key: m.id, at: m.createdAt as string, m })),
      ...calls.map((c) => ({ kind: 'call' as const, key: `call-${c.id}`, at: c.createdAt as string, c })),
    ]
    return items.sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : 0))
  }, [messages, calls])

  const loadMessages = useCallback(async (friendId: string, { quiet = false } = {}) => {
    if (!quiet) setMessagesLoading(true)
    setMessagesError('')
    try {
      const list = await chat().messages(friendId)
      if (selectedRef.current !== friendId) return
      const me = useAuthStore.getState().user?.id
      setMessages((cur) => {
        if (!quiet || list.length !== cur.length) scrollToEnd()
        return list.map((m: any) => ({
          id: m.id,
          fromUserId: m.mine ? me : m.fromId || friendId,
          fromName: m.fromId && !m.mine ? chat().memberName(chat().groups[friendId], m.fromId) : '',
          content: m.text,
          attachment: m.att,
          createdAt: new Date(m.createdAt).toISOString(),
          mine: m.mine,
          system: m.sys || null,
          status: m.status,
          reason: m.reason,
        }))
      })
    } catch (err) {
      setMessagesError((err as Error).message || 'Không đọc được tin nhắn trên thiết bị')
    } finally {
      setMessagesLoading(false)
    }
  }, [])

  const loadCalls = useCallback(async (friendId: string) => {
    if (isGroupId(friendId)) { setCalls([]); return } // no calls with a group
    try {
      const res = await api.get(`/me/calls?friendId=${encodeURIComponent(friendId)}&limit=50`)
      if (selectedRef.current !== friendId) return
      setCalls(res.calls)
      scrollToEnd()
      setUnseenMissed(res.unseenMissed || {})
      if (res.unseenMissed?.[friendId]) {
        await api.post('/me/calls/seen', { friendId })
        setUnseenMissed((cur) => { const { [friendId]: _gone, ...rest } = cur; return rest })
      }
    } catch { /* history is a nicety */ }
  }, [])
  const loadUnseenMissed = useCallback(async () => {
    try { setUnseenMissed((await api.get('/me/calls?limit=1')).unseenMissed || {}) } catch { /* ignore */ }
  }, [])

  // ---- my ID card ----
  const [showId, setShowId] = useState(false)
  const [myCode, setMyCode] = useState('')
  const [codeCopied, setCodeCopied] = useState(false)
  async function copyMyCode() {
    try {
      await navigator.clipboard.writeText(myCode)
      setCodeCopied(true)
      setTimeout(() => setCodeCopied(false), 1800)
    } catch { /* clipboard unavailable - the ID is on screen to read out */ }
  }

  useEffect(() => {
    loadFriends()
    loadRequests()
    if (!isAdmin) {
      api.get('/me/customer-codes').then((r: any) => setMyCode(r.codes?.[0]?.code || ''), () => {})
      loadUnseenMissed()
    }
  }, [])

  // someone sent me a request / accepted mine -> reload the lists
  const firstTick = useRef(true)
  useEffect(() => {
    if (firstTick.current) { firstTick.current = false; return }
    loadRequests()
    const ev = notify().lastFriendEvent
    if (ev?.type === 'friend-accepted') {
      loadFriends({ quiet: true })
      if (searchQuery.trim()) setSearchResults((cur) => cur.map((r) => (r.id === ev.friendId ? { ...r, isFriend: true, requestState: 'none' } : r)))
    }
  }, [requestsTick])
  // fallback when the push never arrived: the periodic unread refresh changed the count
  useEffect(() => {
    if (friendRequestCount !== requestsRef.current.incoming.length) loadRequests()
  }, [friendRequestCount])

  // A new chat message arrived over the WebSocket: refresh the open conversation, or the list otherwise.
  const firstIncoming = useRef(true)
  useEffect(() => {
    if (firstIncoming.current) { firstIncoming.current = false; return }
    const m = notify().lastIncoming
    if (!m || m.source !== 'friend') return
    if (selectedRef.current === m.from) {
      loadMessages(m.from, { quiet: true })
      notify().clear(`friend:${m.from}`)
    } else loadFriends({ quiet: true })
  }, [incomingTick])

  // The local store opens a moment after the page: read the messages again once it is ready.
  useEffect(() => {
    if (!chatReady) return
    if (selectedRef.current) loadMessages(selectedRef.current, { quiet: true })
    loadFriends({ quiet: true })
    loadPins()
  }, [chatReady])
  // local chat store changed (incoming message, delivery status, auto-delete)
  useEffect(() => {
    if (selectedRef.current) loadMessages(selectedRef.current, { quiet: true })
    loadFriends({ quiet: true })
  }, [chatTick])
  // fallback: the periodic unread refresh changed the counters
  const unreadKey = JSON.stringify(unread)
  useEffect(() => {
    const open = selectedRef.current
    if (open && notify().unread[`friend:${open}`]) {
      loadMessages(open, { quiet: true })
      notify().clear(`friend:${open}`)
    }
    loadFriends({ quiet: true })
  }, [unreadKey])
  // a call just ended (or was missed)
  useEffect(() => {
    if (isAdmin || !callEndedTick) return
    if (selectedRef.current) loadCalls(selectedRef.current)
    else loadUnseenMissed()
  }, [callEndedTick])

  // ---- selection mode, menu, reply, pins, forward ----
  const [editMode, setEditMode] = useState(false)
  const [selecting, setSelecting] = useState(false)
  const [pickedIds, setPickedIds] = useState<string[]>([])
  const [decodeOpen, setDecodeOpen] = useState(false)
  const [calcOpen, setCalcOpen] = useState(false)
  const [calcText, setCalcText] = useState('')
  const [calcDate, setCalcDate] = useState('')
  const [calcCustomer, setCalcCustomer] = useState('')
  const [decodeRates, setDecodeRates] = useState<any>({})
  const [menu, setMenu] = useState<{ m: any; x: number; y: number } | null>(null)
  const [replyTo, setReplyTo] = useState<any>(null)
  const [pins, setPins] = useState<string[]>([])
  const [forwardOf, setForwardOf] = useState<any>(null)
  const pressTimer = useRef<any>(null)

  const cancelPick = () => { setSelecting(false); setPickedIds([]) }
  const togglePick = (id: string) => setPickedIds((cur) => (cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id]))
  const pickable = timeline.filter((t) => t.kind === 'msg' && !t.m.system && t.m.content)
  const decodeMessages = timeline.filter((t) => t.kind === 'msg' && !t.m.system && pickedIds.includes(t.m.id)).map((t: any) => ({ id: t.m.id, content: t.m.content }))
  const decodeTypes = useMemo(() => { const l = typesOf(decodeRates); return l.length ? l : ['de', 'lo'] }, [decodeRates])
  const decodeSymbols = useMemo(() => kindSymbolsFor(decodeRates, null, 'mb'), [decodeRates])
  const actionLabel = selecting && pickedIds.length ? `Nhập số (${pickedIds.length})` : 'Nhập số'

  function useDecoded(text: string, where: object = {}) {
    try { sessionStorage.setItem('entries-prefill', JSON.stringify({ text, ...where })) } catch { /* private mode */ }
    setDecodeOpen(false)
    router.push('/entries')
  }
  function sendToEntries() {
    const text = timeline
      .filter((t: any) => t.kind === 'msg' && !t.m.system && pickedIds.includes(t.m.id))
      .map((t: any) => quoteOf(t.m.content).body)
      .filter(Boolean)
      .join('\n')
    if (!text) return
    cancelPick()
    useDecoded(text)
  }
  function onAction() {
    if (!selecting) { setSelecting(true); return }
    if (pickedIds.length) sendToEntries()
  }
  async function openDecode() {
    try {
      const { rates } = await api.get('/me/scoring-settings')
      if (rates && Object.keys(rates).length) setDecodeRates(rates)
    } catch { /* decode with the default types */ }
    setDecodeOpen(true)
  }
  void openDecode

  function openMenu(m: any, el: HTMLElement) {
    if (selecting || m.system) return
    const r = el.getBoundingClientRect()
    setMenu({ m, x: Math.min(Math.max(8, r.left), window.innerWidth - 200), y: Math.min(r.bottom + 4, window.innerHeight - 280) })
  }
  const pressStart = (m: any, e: React.TouchEvent) => {
    clearTimeout(pressTimer.current)
    const el = e.currentTarget as HTMLElement
    pressTimer.current = setTimeout(() => openMenu(m, el), 450)
  }
  const pressEnd = () => clearTimeout(pressTimer.current)

  const focusInput = () => setTimeout(() => msgInput.current?.focus({ preventScroll: true }), 0)
  async function menuCopy() {
    const m = menu!.m
    setMenu(null)
    try { await navigator.clipboard.writeText(quoteOf(m.content).body || m.content || '') } catch { setMessagesError('Không sao chép được') }
  }
  async function loadPins() {
    const id = selectedRef.current
    setPins((id && (await chat().metaGet(`pin:${id}`))) || [])
  }
  const isPinned = (id: string) => pins.includes(id)
  async function togglePin(id: string) {
    const next = isPinned(id) ? pins.filter((x) => x !== id) : [...pins, id]
    setPins(next)
    await chat().metaSet(`pin:${selectedRef.current}`, next.length ? next : null)
  }
  const pinnedMsg = (() => {
    for (let i = pins.length - 1; i >= 0; i--) {
      const t: any = timeline.find((x) => x.kind === 'msg' && x.m.id === pins[i])
      if (t) return t.m
    }
    return null
  })()
  async function doForward(f: any) {
    const m = forwardOf
    setForwardOf(null)
    try {
      const body = quoteOf(m.content).body || '' // the "↪" quote line is not forwarded
      const file = m.attachment?.blob ? new File([m.attachment.blob], m.attachment.name || 'anh.jpg', { type: m.attachment.type }) : null
      await chat().send(f, body, file)
      setMessagesError('')
      openFriend(f)
    } catch (err) {
      setMessagesError((err as Error).message || 'Không chuyển tiếp được')
    }
  }
  async function menuDelete() {
    const m = menu!.m
    setMenu(null)
    if (!(await showConfirm({ title: 'Xoá tin nhắn', message: 'Xoá tin nhắn này khỏi máy này? Người kia vẫn giữ bản của họ.', confirmText: 'Xoá', danger: true }))) return
    await chat().deleteMessage(m.id)
    if (isPinned(m.id)) setPins((cur) => cur.filter((x) => x !== m.id))
    await loadMessages(selectedRef.current!, { quiet: true })
  }

  // ---- list modes ----
  const [tab, setTab] = useState<Tab>('chats')
  const [showArchived, setShowArchived] = useState(false)
  const [editPicked, setEditPicked] = useState<string[]>([])
  const archiveKey = `chat-archive:${user?.id || ''}`
  const prefsKey = `chat-prefs:${user?.id || ''}`
  const [archived, setArchived] = useState<string[]>([])
  const [prefs, setPrefs] = useState<Record<string, { alias: string }>>({})
  useEffect(() => {
    setArchived(jsonKey(archiveKey) || [])
    setPrefs(jsonKey(prefsKey) || {})
  }, [archiveKey, prefsKey])
  const displayName = (f: any) => (f ? prefs[f.id]?.alias || f.name : '')
  // Tin nhắn lưu trữ nằm sau mật khẩu (POST /me/verify-password: mật khẩu đăng nhập hoặc mật khẩu cấp 2) và không hiện số lượng;
  // rời khỏi mục này là khoá lại, lần sau phải nhập lại.
  const [archiveAsk, setArchiveAsk] = useState(false)
  // Nút mũi tên lên đầu danh sách khi lướt xuống (cuộn trang hoặc cuộn khung chứa danh sách).
  const listRef = useRef<HTMLDivElement>(null)
  const scrollerRef = useRef<Element | null>(null)
  const [showTop, setShowTop] = useState(false)
  useEffect(() => {
    const onScroll = (e: Event) => {
      const t = e.target as Node
      const el = (t === document ? document.scrollingElement : t) as Element | null
      if (!el || !listRef.current || !(el.contains(listRef.current) || el === document.scrollingElement)) return
      scrollerRef.current = el
      setShowTop(el.scrollTop > 400)
    }
    document.addEventListener('scroll', onScroll, true)
    return () => document.removeEventListener('scroll', onScroll, true)
  }, [])
  const scrollToTop = () => scrollerRef.current?.scrollTo({ top: 0, behavior: 'smooth' })
  const chatList = filteredFriends.filter(
    (f) => archived.includes(f.id) === showArchived && (!SHOW_BOTTOM_NAV || f.lastMessageAt || unread[`friend:${f.id}`] || f.id === selectedId || showArchived),
  )
  const contactList = [...filteredFriends].filter((f) => !f.isGroup).sort((a, b) => displayName(a).localeCompare(displayName(b), 'vi'))
  const friendOf = (id: string) => friends.find((f) => f.id === id) || null
  const listRows = tab === 'chats' ? chatList : contactList

  const openFriend = (f: { id: string }) => router.push(`/friends?thread=${encodeURIComponent(f.id)}`)
  const backToList = () => router.push('/friends')

  function toggleEdit() { setEditMode((e) => !e); setEditPicked([]) }
  const toggleEditPick = (id: string) => setEditPicked((cur) => (cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id]))
  function archiveSelected() {
    const next = showArchived ? archived.filter((id) => !editPicked.includes(id)) : [...new Set([...archived, ...editPicked])]
    setArchived(next)
    saveKey(archiveKey, next)
    if (selectedId && editPicked.includes(selectedId)) backToList()
    toggleEdit()
  }
  async function deleteSelected() {
    const ids = [...editPicked]
    if (!ids.length) return
    if (!(await showConfirm({
      title: 'Xoá cuộc trò chuyện',
      message: `Xoá ${ids.length} cuộc trò chuyện khỏi máy này? Tin nhắn và ảnh trong đó sẽ mất trên máy này (người kia vẫn giữ bản của họ). Bạn bè vẫn còn trong danh bạ; nhóm thì bạn sẽ rời khỏi nhóm.`,
      confirmText: 'Xoá',
      danger: true,
    }))) return
    // a group is left (the members are told); a friend's conversation is only cleared on this device
    for (const id of ids) await (isGroupId(id) ? chat().leaveGroup(id) : chat().deleteConversation(id))
    if (selectedId && ids.includes(selectedId)) backToList()
    await loadFriends({ quiet: true })
    toggleEdit()
  }

  // calls tab
  const [callRows, setCallRows] = useState<any[]>([])
  const [callsLoading, setCallsLoading] = useState(false)
  useEffect(() => {
    setEditMode(false)
    setEditPicked([])
    if (tab !== 'calls') return
    setCallsLoading(true)
    api.get('/me/calls?limit=60').then((r: any) => setCallRows(r.calls), () => setCallRows([])).finally(() => setCallsLoading(false))
  }, [tab])

  // new: message / group / contact
  const [newOpen, setNewOpen] = useState(false)
  const [newMsgOpen, setNewMsgOpen] = useState(false)
  const [groupOpen, setGroupOpen] = useState(false)
  function openSearch() { setSearchOpen(true); setTimeout(() => searchInput.current?.focus(), 0) }
  function closeSearch() { setSearchOpen(false); setSearchQuery('') }
  function pickNew(kind: 'message' | 'group' | 'contact') {
    setNewOpen(false)
    if (kind === 'message') setNewMsgOpen(true)
    else if (kind === 'group') setGroupOpen(true)
    else { if (SHOW_BOTTOM_NAV) setTab('contacts'); openSearch() }
  }
  function startChat(f: any) { setNewMsgOpen(false); setTab('chats'); openFriend(f) }

  // per-conversation settings
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [aliasDraft, setAliasDraft] = useState('')
  const [showSecurity, setShowSecurity] = useState(false)
  const [retentionOpen, setRetentionOpen] = useState(false)
  const [retentionRule, setRetentionRule] = useState<RetentionRule | null>(null)
  const retentionPanel = useRef<RetentionHandle>(null)
  const [groupSettingsOpen, setGroupSettingsOpen] = useState(false)
  const [groupNameDraft, setGroupNameDraft] = useState('')
  const [addOpen, setAddOpen] = useState(false)
  const [addPicked, setAddPicked] = useState<string[]>([])
  const [groupManageError, setGroupManageError] = useState('')

  const selectedGroup: any = selectedFriend?.isGroup ? groups[selectedFriend.id] || null : null
  const isGroupCreator = !!selectedGroup && selectedGroup.creatorId === user?.id
  const groupCanSend = !!selectedGroup?.members.some((m: any) => m.id !== user?.id && friendKeys[m.id])
  const peerInfo = (selectedId && peerInfoMap[selectedId]) || null
  const canCall = !isAdmin && !!selectedFriend && !selectedFriend.isAdmin && !selectedFriend.isGroup

  function openSettings() {
    if (selectedFriend?.isGroup) { setGroupNameDraft(selectedFriend.name); setAddOpen(false); setAddPicked([]); setGroupManageError(''); setGroupSettingsOpen(true); return }
    setAliasDraft(prefs[selectedId!]?.alias || '')
    setSettingsOpen(true)
  }
  function saveSettings() {
    const alias = aliasDraft.trim()
    const next = { ...prefs }
    if (alias && alias !== selectedFriend?.name) next[selectedId!] = { alias }
    else delete next[selectedId!]
    setPrefs(next)
    saveKey(prefsKey, next)
    setSettingsOpen(false)
  }
  async function removeFriend(friend: any) {
    if (!(await showConfirm({ title: 'Xoá bạn bè', message: `Xoá bạn bè "${friend.name}"? Cuộc trò chuyện sẽ không còn hiển thị.`, confirmText: 'Xoá', danger: true }))) return
    try {
      await api.del(`/me/friends/${friend.id}`)
      setFriends((cur) => cur.filter((f) => f.id !== friend.id))
      if (selectedId === friend.id) backToList()
    } catch (err) {
      setMessagesError((err as Error).message || 'Không xoá được bạn bè')
    }
  }

  // selected conversation changes
  useEffect(() => {
    cancelPick()
    setSettingsOpen(false)
    setReplyTo(null)
    setShowSecurity(false)
    setMessages([])
    setCalls([])
    if (selectedId) {
      notify().clear(`friend:${selectedId}`)
      loadMessages(selectedId)
      loadPins()
      if (!isAdmin) loadCalls(selectedId)
    } else setPins([])
  }, [selectedId])

  // A screenshot shortcut while this conversation is on screen: warn the friend (best effort).
  useEffect(() => {
    const stop = onScreenshotAttempt(() => {
      const f = friends.find((x) => x.id === selectedRef.current)
      if (f && !document.hidden && !isAdmin) chat().notifyScreenshot(f)
    })
    return () => void stop()
  }, [friends, isAdmin])

  async function sendMessage(e: React.FormEvent) {
    e.preventDefault()
    const content = newMessage.trim()
    if ((!content && !attachment) || !selectedId || !selectedFriend) return
    setSending(true)
    setMessagesError('')
    try {
      const text = replyTo ? `${REPLY_MARK}${quoteText(replyTo)}\n${content}` : content
      await chat().send(selectedFriend, text, attachment)
      setReplyTo(null)
      setNewMessage('')
      setAttachment(null)
      await loadMessages(selectedId, { quiet: true })
      scrollToEnd()
    } catch (err) {
      setMessagesError((err as Error).message || 'Không gửi được tin nhắn')
    } finally {
      setSending(false)
    }
  }
  async function retryMessage(m: any) {
    await chat().retry({ id: m.id, mine: true })
    await loadMessages(selectedId!, { quiet: true })
  }

  // ---- group creation / management ----
  const [groupName, setGroupName] = useState('')
  const [groupMembers, setGroupMembers] = useState<string[]>([])
  const [groupError, setGroupError] = useState('')
  const [groupBusy, setGroupBusy] = useState(false)
  useEffect(() => { if (groupOpen) { setGroupName(''); setGroupMembers([]); setGroupError('') } }, [groupOpen])
  // friends that can be put in a group: real friends (not Admin) whose end-to-end key is known
  const groupCandidates = friends.filter((f) => !f.isGroup && !f.isAdmin && friendKeys[f.id]).sort((a, b) => displayName(a).localeCompare(displayName(b), 'vi'))
  const canCreateGroup = !groupBusy && groupName.trim() && groupMembers.length >= 2
  async function createGroup() {
    setGroupBusy(true)
    setGroupError('')
    try {
      const others = groupMembers.map((id) => ({ id, name: displayName(friendOf(id)) }))
      const g = await chat().createGroup(groupName, user?.name || '', others)
      setGroupOpen(false)
      setTab('chats')
      setShowArchived(false)
      await loadFriends({ quiet: true })
      openFriend({ id: g.id })
    } catch (err) {
      setGroupError((err as Error).message || 'Không tạo được nhóm')
    } finally {
      setGroupBusy(false)
    }
  }
  const addCandidates = friends.filter((f) => !f.isGroup && !f.isAdmin && friendKeys[f.id] && !selectedGroup?.members.some((m: any) => m.id === f.id))
  async function addMembers() {
    setGroupManageError('')
    try {
      await chat().addGroupMembers(selectedGroup.id, addPicked.map((id) => ({ id, name: displayName(friendOf(id)) })))
      setAddPicked([])
      setAddOpen(false)
      await loadFriends({ quiet: true })
    } catch (err) {
      setGroupManageError((err as Error).message || 'Không thêm được thành viên')
    }
  }
  async function removeMember(m: any) {
    const g = selectedGroup
    if (!(await showConfirm({ title: 'Xoá khỏi nhóm', message: `Xoá ${chat().memberName(g, m.id)} khỏi nhóm "${g.name}"? Họ sẽ không còn nhận tin của nhóm.`, confirmText: 'Xoá', danger: true }))) return
    setGroupManageError('')
    try {
      await chat().removeGroupMember(g.id, m.id)
      await loadFriends({ quiet: true })
    } catch (err) {
      setGroupManageError((err as Error).message || 'Không xoá được thành viên')
    }
  }
  async function saveGroupName() {
    if (!selectedGroup) return
    const name = groupNameDraft.trim()
    if (name && name !== selectedGroup.name) await chat().renameGroup(selectedGroup.id, name)
    setGroupSettingsOpen(false)
    await loadFriends({ quiet: true })
  }
  async function leaveSelectedGroup() {
    const g = selectedGroup
    if (!g) return
    setGroupSettingsOpen(false)
    if (!(await showConfirm({ title: 'Rời nhóm', message: `Rời nhóm "${g.name}"? Tin nhắn của nhóm sẽ bị xoá khỏi máy này và các thành viên được báo là bạn đã rời.`, confirmText: 'Rời nhóm', danger: true }))) return
    await chat().leaveGroup(g.id)
    backToList()
    await loadFriends({ quiet: true })
  }

  const offlineLabel = selectedFriend && !selectedFriend.isGroup ? peerOfflineLabel(messages, socketReady) : null
  const unreadOf = (id: string) => unread[`friend:${id}`] || 0
  const showSearchCard = !!searchError || !!searchNotice || (!!searchQuery.trim() && (searching || newPeople.length > 0))

  return (
    <div className="page friends-page">
      <div className="page-head">
        <h1 className="page-title">Tin nhắn</h1>
        {/* search, Sửa, Thêm and your own ID (hidden until asked for) */}
        <div className="head-actions">
          {searchOpen && (
            <>
              <input id="searchQuery" ref={searchInput} className="head-search" type="search" aria-label="Tìm kiếm" placeholder="Tìm kiếm" autoComplete="off" value={searchQuery} onChange={(e) => setSearchQuery(e.target.value)} onKeyDown={(e) => e.key === 'Escape' && closeSearch()} />
              <AppButton variant="ghost" size="sm" onClick={closeSearch}>Đóng</AppButton>
            </>
          )}
          {!searchOpen && (
            <>
              <AppButton variant="ghost" size="sm" icon="search" aria-label="Tìm kiếm" onClick={openSearch}>Tìm kiếm</AppButton>
              {tab === 'chats' && <AppButton variant="ghost" size="sm" aria-pressed={editMode} onClick={toggleEdit}>{editMode ? 'Xong' : 'Sửa'}</AppButton>}
              <AppButton variant="primary" size="sm" onClick={() => setNewOpen(true)}>Thêm</AppButton>
              <div className="my-id-wrap" onKeyDown={(e) => e.key === 'Escape' && setShowId(false)}>
                <AppButton variant="secondary" size="sm" icon="user" aria-expanded={showId} aria-haspopup="dialog" onClick={() => setShowId(!showId)}>ID của bạn</AppButton>
                {showId && (
                  <div className="my-id-pop" role="dialog" aria-label="ID của bạn">
                    {myCode ? (
                      <>
                        <span className="my-id-label">Đưa ID này cho người muốn kết bạn với bạn</span>
                        <span className="my-id-code">{myCode}</span>
                        <AppButton variant="primary" size="sm" onClick={copyMyCode}>{codeCopied ? 'Đã chép' : 'Sao chép'}</AppButton>
                      </>
                    ) : (
                      <span className="my-id-label">Chưa có ID. <Link href="/account">Tạo ID trong Tài khoản.</Link></span>
                    )}
                  </div>
                )}
              </div>
            </>
          )}
        </div>
      </div>

      <div className={`split${selectedId ? ' show-thread' : ''}`}>
        <div className="list-pane" ref={listRef}>
          {showSearchCard && (
            <div className="card search-form">
              {searchError && <div className="alert alert-error" style={{ margin: '8px 0 0' }}>{searchError}</div>}
              {searchNotice && <div className="alert alert-success req-notice" role="status">{searchNotice}</div>}
              {/* people who are not friends yet */}
              {searchQuery.trim() && (searching || newPeople.length > 0) && (
                <div className="search-results">
                  <div className="search-group">Người mới</div>
                  {searching && newPeople.length === 0 && <div className="search-hint">Đang tìm...</div>}
                  {newPeople.map((r) => (
                    <div key={r.id} className="search-item">
                      <div className="friend-info">
                        <strong>{r.name} {r.isAdmin && <span className="chip chip-brand" style={{ fontSize: 14, padding: '1px 6px' }}>Admin</span>}</strong>
                        <span className="friend-last">@{r.username}</span>
                      </div>
                      <AppButton variant="secondary" size="sm" disabled={searchAction(r).disabled || addingId === r.id || requestBusy !== null} onClick={() => onSearchButton(r)}>{addingId === r.id ? '...' : searchAction(r).label}</AppButton>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {loading ? (
            <div className="card">Đang tải...</div>
          ) : loadError ? (
            <div className="alert alert-error">{loadError}</div>
          ) : (
            <>
              {searchQuery.trim() && filteredFriends.length > 0 && <div className="search-group list-group">Bạn bè</div>}

              {(tab === 'chats' || tab === 'contacts') && (
                <>
                  {/* Lời mời kết bạn: a friend request must be accepted before it becomes a friendship */}
                  {showRequestsBlock(tab, SHOW_BOTTOM_NAV, hasRequests) && (
                    <div className="card req-block">
                      <div className="req-title">
                        <strong>Lời mời kết bạn</strong>
                        {friendRequestCount > 0 && <span className="unread-badge" title="Lời mời chưa trả lời">{badgeText(friendRequestCount)}</span>}
                      </div>
                      {requestError && <div className="alert alert-error" style={{ margin: '8px 0 0' }}>{requestError}</div>}
                      {requests.incoming.map((r) => (
                        <div key={r.id} className="req-row">
                          <span className="avatar">{initial(r.fromName)}</span>
                          <div className="friend-info">
                            <strong>{r.fromName}</strong>
                            <span className="friend-last">@{r.fromUsername}</span>
                          </div>
                          <div className="req-actions">
                            <AppButton variant="primary" size="sm" disabled={requestBusy === r.id} onClick={() => acceptRequest(r)}>Chấp nhận</AppButton>
                            <AppButton variant="ghost" size="sm" disabled={requestBusy === r.id} onClick={() => declineRequest(r)}>Từ chối</AppButton>
                          </div>
                        </div>
                      ))}
                      {requests.outgoing.length > 0 && (
                        <>
                          <div className="req-sub">Đã gửi lời mời, chờ chấp nhận</div>
                          {requests.outgoing.map((r) => (
                            <div key={r.id} className="req-row">
                              <span className="avatar">{initial(r.toName)}</span>
                              <div className="friend-info">
                                <strong>{r.toName}</strong>
                                <span className="friend-last">@{r.toUsername}</span>
                              </div>
                              <div className="req-actions">
                                <AppButton variant="ghost" size="sm" disabled={requestBusy === r.id} onClick={() => cancelRequest(r)}>Huỷ lời mời</AppButton>
                              </div>
                            </div>
                          ))}
                        </>
                      )}
                    </div>
                  )}
                  {friends.length === 0 ? (
                    <div className="card">Chưa có bạn bè nào. Bấm Thêm &gt; Danh bạ mới để tìm và kết bạn.</div>
                  ) : listRows.length === 0 ? (
                    <div>
                      {searchQuery.trim() && !searching && newPeople.length === 0 && (
                        <div className="card">Không tìm thấy ai khớp với &quot;{searchQuery.trim()}&quot;. Nếu là mã ID, hãy kiểm tra lại các chữ số.</div>
                      )}
                      {!searchQuery.trim() && (
                        <div className="card">{showArchived ? 'Chưa lưu trữ cuộc trò chuyện nào.' : 'Chưa có cuộc trò chuyện nào. Bấm Thêm > Tin nhắn mới để bắt đầu.'}</div>
                      )}
                    </div>
                  ) : (
                    <div className="friend-list">
                      {listRows.map((f) => (
                        <div key={f.id} className={`card friend-item${f.id === selectedId ? ' active' : ''}`} onClick={() => (editMode && tab === 'chats' ? toggleEditPick(f.id) : openFriend(f))}>
                          {editMode && tab === 'chats' && <input type="checkbox" className="pick" checked={editPicked.includes(f.id)} aria-label="Chọn cuộc trò chuyện" onClick={(e) => e.stopPropagation()} onChange={() => toggleEditPick(f.id)} />}
                          <span className={`avatar${f.isGroup ? ' avatar-group' : ''}`}>{f.isGroup ? '👥' : initial(displayName(f))}</span>
                          <div className="friend-info">
                            <strong>
                              {displayName(f)}
                              {unreadOf(f.id) > 0 && <span className="unread-badge" title="Tin nhắn chưa đọc">{unreadOf(f.id) > 99 ? '99+' : unreadOf(f.id)}</span>}
                              {unseenMissed[f.id] > 0 && <span className="missed-badge" title="Cuộc gọi nhỡ"><AppIcon name="phone" /> {unseenMissed[f.id]}</span>}
                            </strong>
                            <span className={`friend-last${unreadOf(f.id) ? ' has-unread' : ''}`}>{tab === 'contacts' ? '@' + f.username : f.lastMessage || 'Chưa có tin nhắn'}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                  {tab === 'chats' && editMode && (
                    <div className="edit-bar">
                      <button type="button" className="tb-link" disabled={!editPicked.length} onClick={archiveSelected}>{showArchived ? 'Bỏ lưu trữ' : 'Lưu trữ'}{editPicked.length ? ` (${editPicked.length})` : ''}</button>
                      <button type="button" className="tb-link danger" disabled={!editPicked.length} onClick={deleteSelected}>Xoá{editPicked.length ? ` (${editPicked.length})` : ''}</button>
                    </div>
                  )}
                  {tab === 'chats' && !editMode && (
                    <button type="button" className="tb-link archive-link" onClick={() => (showArchived ? setShowArchived(false) : setArchiveAsk(true))}>{showArchived ? '← Về tin nhắn' : 'Tin nhắn lưu trữ'}</button>
                  )}
                </>
              )}

              {tab === 'calls' && (
                callsLoading ? <div className="card">Đang tải...</div> : callRows.length === 0 ? <div className="card">Chưa có cuộc gọi nào.</div> : (
                  <div className="friend-list">
                    {callRows.map((c) => {
                      const f = friendOf(c.peerId)
                      return (
                        <div key={c.id} className="card friend-item" onClick={() => f && openFriend(f)}>
                          <span className="avatar">{initial(f ? displayName(f) : c.peerName)}</span>
                          <div className="friend-info">
                            <strong className={isMissedCall(c) ? 'missed-name' : ''}>{f ? displayName(f) : c.peerName}</strong>
                            <span className="friend-last">{callLine(c)} · {callTime(c.createdAt)}</span>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                )
              )}

              {tab === 'settings' && (
                <div className="card chat-settings">
                  <strong>Cài đặt tin nhắn</strong>
                  <button type="button" className="tb-link" onClick={() => { setTab('chats'); setArchiveAsk(true) }}>Tin nhắn lưu trữ</button>
                  <Link className="tb-link" href="/account?tab=security">Bảo mật tài khoản</Link>
                  {myCode && <p className="search-sub">ID của bạn: <strong>{myCode}</strong></p>}
                </div>
              )}
            </>
          )}

          {SHOW_BOTTOM_NAV && (
            <nav className="bottom-nav" aria-label="Điều hướng tin nhắn">
              <button type="button" className={tab === 'contacts' ? 'on' : ''} onClick={() => setTab('contacts')}><AppIcon name="users" /><span>Danh bạ</span></button>
              <button type="button" className={tab === 'calls' ? 'on' : ''} onClick={() => setTab('calls')}><AppIcon name="phone" /><span>Cuộc gọi</span></button>
              <button type="button" className={tab === 'chats' ? 'on' : ''} onClick={() => { setTab('chats'); setShowArchived(false) }}><AppIcon name="message-circle-more" /><span>Tin nhắn</span></button>
              <button type="button" className={tab === 'settings' ? 'on' : ''} onClick={() => setTab('settings')}><AppIcon name="settings" /><span>Cài đặt</span></button>
            </nav>
          )}
        </div>

        <div className="thread-pane">
          {!selectedId ? (
            <div className="card empty-thread">Chọn một người bạn để xem tin nhắn.</div>
          ) : (
            <>
              <div className="thread-header">
                <button className="back-btn" aria-label="Quay lại danh sách" title="Quay lại" onClick={backToList}><AppIcon name="arrow-left" /></button>
                <button type="button" className="who" title="Thông tin người trò chuyện" onClick={openSettings}>
                  <span className={`avatar sm${selectedFriend?.isGroup ? ' avatar-group' : ''}`}>{selectedFriend?.isGroup ? '👥' : initial(displayName(selectedFriend))}</span>
                  <strong className="thread-title">{displayName(selectedFriend) || '...'}</strong>
                  {selectedGroup && <span className="thread-sub">{selectedGroup.members.length} thành viên</span>}
                  {offlineLabel && <span className={`thread-sub conn conn-${offlineLabel.tone}`}>{offlineLabel.text}</span>}
                </button>
                <button type="button" className="btn btn-ghost btn-sm gear" aria-label="Cài đặt cuộc trò chuyện" title="Cài đặt cuộc trò chuyện" onClick={openSettings}><AppIcon name="settings" /></button>
                {canCall && (
                  <div className="call-buttons">
                    <AppButton variant="ghost" size="sm" icon="phone" title="Gọi thoại" disabled={callStatus !== 'idle' || callAcquiring} onClick={() => selectedFriend && useCallStore.getState().startCall(selectedFriend)} />
                  </div>
                )}
              </div>
              {peerInfo?.changed && (
                <div className="alert alert-warning e2ee-warn" role="alert">
                  Khoá bảo mật của {selectedFriend?.name} đã thay đổi (họ đổi máy hoặc xoá dữ liệu trình duyệt). Hãy xác minh mã bảo mật mới với họ qua kênh khác rồi bấm Đã hiểu.
                  <AppButton variant="secondary" size="sm" onClick={() => chat().acceptKeyChange(selectedId)}>Đã hiểu</AppButton>
                </div>
              )}
              {selectedGroup && !groupCanSend ? (
                <div className="alert alert-warning e2ee-warn">Chưa có thành viên nào là bạn bè của bạn dùng mã hoá 2 đầu nên chưa nhắn được trong nhóm này.</div>
              ) : selectedFriend && !selectedFriend.isGroup && !friendKeys[selectedFriend.id] ? (
                <div className="alert alert-warning e2ee-warn">{selectedFriend.name} chưa bật mã hoá 2 đầu (chưa mở phiên bản mới) nên chưa nhắn được.</div>
              ) : null}
              {showSecurity && peerInfo && (
                <div className="e2ee-codes">
                  <div>Của {selectedFriend?.name}: <code>{peerInfo.fingerprint}</code></div>
                  <div>Của bạn: <code>{myFingerprint}</code></div>
                  <div className="e2ee-hint">Đọc hai mã này cho nhau qua kênh khác (gọi điện, gặp mặt). Nếu khớp thì không ai chen giữa.</div>
                </div>
              )}
              {!selectedFriend?.isAdmin && (
                <ChatRetentionPanel
                  friendId={selectedId}
                  friendName={selectedFriend?.name || ''}
                  open={retentionOpen}
                  onOpenChange={setRetentionOpen}
                  handle={retentionPanel}
                  onRule={setRetentionRule}
                  onApplied={() => loadMessages(selectedId)}
                />
              )}
              {pinnedMsg && (
                <div className="pin-bar">
                  <span>📌 {quoteText(pinnedMsg)}</span>
                  <button type="button" className="tb-link" aria-label="Bỏ ghim" onClick={() => togglePin(pinnedMsg.id)}>✕</button>
                </div>
              )}
              {messagesError && <div className="alert alert-error">{messagesError}</div>}
              <div ref={threadBody} className="card thread-body">
                {messagesLoading ? (
                  <div>Đang tải tin nhắn...</div>
                ) : timeline.length === 0 ? (
                  <div className="empty-thread">Chưa có tin nhắn nào.</div>
                ) : (
                  <div className="messages">
                    {timeline.map((item: any) => {
                      if (item.kind === 'msg' && item.m.system) {
                        const m = item.m
                        return (
                          <div key={item.key} className={`sys-line${m.mine && m.status === 'failed' ? ' failed' : ''}`}>
                            {m.system === 'screenshot'
                              ? <>📷 {selectedFriend?.name} vừa chụp màn hình cuộc trò chuyện này</>
                              : m.status === 'failed'
                                ? <>📷 Bạn vừa chụp màn hình, nhưng {selectedFriend?.name} đang offline nên chưa được báo</>
                                : <>📷 Bạn vừa chụp màn hình, {selectedFriend?.name} đã được báo</>}
                          </div>
                        )
                      }
                      if (item.kind === 'msg') {
                        const m = item.m
                        const qt = quoteOf(m.content)
                        return (
                          <div key={item.key} className={`msg${m.mine ? ' mine' : ''}${selecting ? ' picking' : ''}`}>
                            {selecting && m.content && <input type="checkbox" className="pick" aria-label="Chọn tin nhắn" checked={pickedIds.includes(m.id)} onChange={() => togglePick(m.id)} />}
                            <div
                              className="msg-bubble"
                              onContextMenu={(e) => { e.preventDefault(); openMenu(m, e.currentTarget) }}
                              onTouchStart={(e) => pressStart(m, e)}
                              onTouchEnd={pressEnd}
                              onTouchMove={pressEnd}
                              onTouchCancel={pressEnd}
                            >
                              {isPinned(m.id) && <span className="pin-mark" title="Đã ghim">📌</span>}
                              {m.fromName && !m.mine && <div className="msg-sender">{m.fromName}</div>}
                              {qt.quote && <div className="quote">{qt.quote}</div>}
                              {m.content && <span>{qt.body}</span>}
                              {m.attachment && <MessageAttachment att={m.attachment} blob={m.attachment.blob} />}
                            </div>
                            {m.mine && m.status === 'failed' ? (
                              <div className="msg-state msg-failed">
                                {chat().reasonText(m.reason)}
                                <AppButton variant="ghost" size="sm" onClick={() => retryMessage(m)}>Gửi lại</AppButton>
                              </div>
                            ) : m.mine && m.status !== 'delivered' ? (
                              <div className="msg-state">{m.status === 'sending' ? 'Đang gửi...' : 'Đã gửi, chờ xác nhận...'}</div>
                            ) : null}
                          </div>
                        )
                      }
                      const c = item.c
                      return (
                        <div key={item.key} className={`call-line${isMissedCall(c) || c.status === 'failed' ? ' missed' : ''}`}>
                          <AppIcon name="phone" />
                          <span>{callLine(c)}</span>
                          {canCall && (isMissedCall(c) || c.status === 'rejected' || c.status === 'failed') && (
                            <AppButton variant="ghost" size="sm" disabled={callStatus !== 'idle' || callAcquiring} onClick={() => selectedFriend && useCallStore.getState().startCall(selectedFriend)}>Gọi lại</AppButton>
                          )}
                        </div>
                      )
                    })}
                  </div>
                )}
              </div>
              {attachment && <AttachmentPreview file={attachment} onRemove={() => setAttachment(null)} />}
              {selecting && (
                <div className="selbar">
                  <span>Đã chọn {pickedIds.length}</span>
                  <button type="button" className="tb-link" onClick={() => setPickedIds(pickable.map((t: any) => t.m.id))}>Chọn tất cả</button>
                  <button type="button" className="tb-link" onClick={() => setPickedIds([])}>Bỏ chọn</button>
                  <button type="button" className="tb-link" onClick={cancelPick}>Hủy</button>
                </div>
              )}
              {replyTo && (
                <div className="reply-bar">
                  <span>↪ Trả lời: {quoteText(replyTo)}</span>
                  <button type="button" className="tb-link" aria-label="Bỏ trả lời" onClick={() => setReplyTo(null)}>✕</button>
                </div>
              )}
              <div className="send-tools">
                <button type="button" className={`calc-btn${selecting && pickedIds.length ? ' ready' : ''}`} onClick={onAction}>{actionLabel}</button>
              </div>
              <form className="send-row" onSubmit={sendMessage}>
                <ChatAttachButtons icon="paperclip" disabled={sending} onPick={(f) => { setAttachment(f); setMessagesError('') }} onError={setMessagesError} />
                <input ref={msgInput} value={newMessage} onChange={(e) => setNewMessage(e.target.value)} type="text" placeholder="Nhập tin nhắn..." autoComplete="off" />
                <AppButton variant="primary" type="submit" disabled={sending || (!newMessage.trim() && !attachment)}>Gửi</AppButton>
              </form>
            </>
          )}
        </div>
      </div>

      {groupSettingsOpen && selectedGroup && (
        <div className="group-overlay" onClick={(e) => e.target === e.currentTarget && setGroupSettingsOpen(false)}>
          <div className="card group-sheet" role="dialog" aria-label="Cài đặt nhóm">
            <div className="set-head">
              <span className="avatar big avatar-group">👥</span>
              <strong>{selectedGroup.name}</strong>
            </div>
            {isGroupCreator && <label className="set-field">Tên nhóm<input value={groupNameDraft} onChange={(e) => setGroupNameDraft(e.target.value)} type="text" maxLength={60} /></label>}
            <strong>{selectedGroup.members.length} thành viên</strong>
            <ul className="group-members">
              {selectedGroup.members.map((m: any) => (
                <li key={m.id}>
                  {chat().memberName(selectedGroup, m.id)}{m.id === selectedGroup.creatorId && <span className="search-hint"> · người tạo</span>}
                  {isGroupCreator && m.id !== selectedGroup.creatorId && (
                    <button type="button" className="tb-link danger" aria-label={`Xoá ${chat().memberName(selectedGroup, m.id)} khỏi nhóm`} onClick={() => removeMember(m)}>Xoá</button>
                  )}
                </li>
              ))}
            </ul>
            {isGroupCreator && (
              <>
                <button type="button" className="tb-link" onClick={() => setAddOpen(!addOpen)}>{addOpen ? 'Đóng danh sách' : 'Thêm thành viên'}</button>
                {addOpen && (
                  <ul className="group-members">
                    {addCandidates.map((f) => (
                      <li key={f.id}><label><input type="checkbox" checked={addPicked.includes(f.id)} onChange={() => setAddPicked((cur) => (cur.includes(f.id) ? cur.filter((x) => x !== f.id) : [...cur, f.id]))} /> {displayName(f)}</label></li>
                    ))}
                    {!addCandidates.length && <li className="search-hint">Không còn bạn bè nào (đã bật mã hoá 2 đầu) để thêm.</li>}
                    {addCandidates.length > 0 && <li><button type="button" className="tb-link strong" disabled={!addPicked.length} onClick={addMembers}>Thêm {addPicked.length || ''}</button></li>}
                  </ul>
                )}
              </>
            )}
            {groupManageError && <div className="alert alert-error">{groupManageError}</div>}
            <div className="set-tools">
              <button type="button" className="tb-link" onClick={() => { setRetentionOpen(!retentionOpen); setGroupSettingsOpen(false) }}>Cài đặt tự xoá</button>
              {retentionRule && <button type="button" className="tb-link" onClick={() => { retentionPanel.current?.cancel(); setGroupSettingsOpen(false) }}>Tắt tự xoá</button>}
              <button type="button" className="tb-link danger" onClick={leaveSelectedGroup}>Rời nhóm</button>
            </div>
            <div className="group-actions">
              <button type="button" className="tb-link" onClick={() => setGroupSettingsOpen(false)}>Đóng</button>
              {isGroupCreator && <button type="button" className="tb-link strong" onClick={saveGroupName}>Lưu</button>}
            </div>
          </div>
        </div>
      )}

      {settingsOpen && selectedFriend && (
        <div className="group-overlay" onClick={(e) => e.target === e.currentTarget && setSettingsOpen(false)}>
          <div className="card group-sheet" role="dialog" aria-label="Cài đặt cuộc trò chuyện">
            <div className="set-head">
              <span className="avatar big">{initial(aliasDraft.trim() || selectedFriend.name)}</span>
              <strong>{aliasDraft.trim() || selectedFriend.name}</strong>
            </div>
            <label className="set-field">Tên hiển thị<input value={aliasDraft} onChange={(e) => setAliasDraft(e.target.value)} type="text" placeholder={selectedFriend.name} maxLength={40} /></label>
            <p className="search-sub">Chỉ đổi cách hiển thị trên máy này, người kia không thấy.</p>
            <div className="set-tools">
              {peerInfo && <button type="button" className="tb-link" onClick={() => { setShowSecurity(!showSecurity); setSettingsOpen(false) }}>Mã bảo mật</button>}
              {!selectedFriend.isAdmin && <button type="button" className="tb-link" onClick={() => { setRetentionOpen(!retentionOpen); setSettingsOpen(false) }}>Cài đặt tự xoá</button>}
              {retentionRule && <button type="button" className="tb-link" onClick={() => { retentionPanel.current?.cancel(); setSettingsOpen(false) }}>Tắt tự xoá</button>}
              <button type="button" className="tb-link danger" onClick={() => { setSettingsOpen(false); removeFriend(selectedFriend) }}>Xoá khỏi bạn bè</button>
            </div>
            <div className="group-actions">
              <button type="button" className="tb-link" onClick={() => setSettingsOpen(false)}>Đóng</button>
              <button type="button" className="tb-link strong" onClick={saveSettings}>Lưu</button>
            </div>
          </div>
        </div>
      )}

      {/* menu nhấn giữ tin nhắn */}
      {menu && (
        <div className="msg-menu-overlay" onClick={() => setMenu(null)} onContextMenu={(e) => { e.preventDefault(); setMenu(null) }}>
          <div className="card msg-menu" role="menu" style={{ left: menu.x, top: menu.y }} onClick={(e) => e.stopPropagation()}>
            <button type="button" role="menuitem" className="tb-link" onClick={() => { setReplyTo(menu.m); setMenu(null); focusInput() }}>Trả lời</button>
            {menu.m.content && <button type="button" role="menuitem" className="tb-link" onClick={menuCopy}>Sao chép</button>}
            <button type="button" role="menuitem" className="tb-link" onClick={() => { togglePin(menu.m.id); setMenu(null) }}>{isPinned(menu.m.id) ? 'Bỏ ghim' : 'Ghim'}</button>
            <button type="button" role="menuitem" className="tb-link" onClick={() => { setForwardOf(menu.m); setMenu(null) }}>Chuyển tiếp</button>
            <button type="button" role="menuitem" className="tb-link danger" onClick={menuDelete}>Xoá</button>
            {menu.m.content && <button type="button" role="menuitem" className="tb-link" onClick={() => { const m = menu.m; setMenu(null); setSelecting(true); setPickedIds((cur) => (cur.includes(m.id) ? cur : [...cur, m.id])) }}>Chọn</button>}
          </div>
        </div>
      )}

      {/* chuyển tiếp: not to Admin (support is a separate plaintext channel) */}
      {forwardOf && (
        <div className="group-overlay" onClick={(e) => e.target === e.currentTarget && setForwardOf(null)}>
          <div className="card group-sheet" role="dialog" aria-label="Chuyển tiếp">
            <strong>Chuyển tiếp tới</strong>
            <ul className="group-members">
              {friends.filter((x) => !x.isAdmin).map((f) => <li key={f.id}><button type="button" className="tb-link new-opt" onClick={() => doForward(f)}>{displayName(f)}</button></li>)}
              {!friends.length && <li className="search-hint">Chưa có bạn bè.</li>}
            </ul>
            <div className="group-actions"><button type="button" className="tb-link" onClick={() => setForwardOf(null)}>Đóng</button></div>
          </div>
        </div>
      )}

      <ChatDecodeDialog open={decodeOpen} messages={decodeMessages} betTypes={decodeTypes} kindSymbols={decodeSymbols} onClose={() => setDecodeOpen(false)} onUse={useDecoded} onCalc={(text, date, customer) => { setCalcText(text); setCalcDate(date); setCalcCustomer(customer); setDecodeOpen(false); setCalcOpen(true) }} />
      <ChatCalcDialog open={calcOpen} text={calcText} date={calcDate} customerId={calcCustomer} friends={friends.filter((f) => !f.isAdmin)} onClose={() => setCalcOpen(false)} onBack={() => { setCalcOpen(false); setDecodeOpen(true) }} />

      <PasswordPromptDialog
        open={archiveAsk}
        title="Tin nhắn lưu trữ"
        description="Nhập mật khẩu để xem các cuộc trò chuyện đã lưu trữ."
        onClose={() => setArchiveAsk(false)}
        onVerified={() => { setArchiveAsk(false); setTab('chats'); setShowArchived(true) }}
      />
      {showTop && !selectedId && (
        <button type="button" className="to-top" aria-label="Lên đầu danh sách" title="Lên đầu danh sách" onClick={scrollToTop}>↑</button>
      )}

      {newOpen && (
        <div className="group-overlay" onClick={(e) => e.target === e.currentTarget && setNewOpen(false)}>
          <div className="card group-sheet" role="dialog" aria-label="Tạo mới">
            <strong>Tạo mới</strong>
            <button type="button" className="tb-link new-opt" onClick={() => pickNew('message')}>Tin nhắn mới</button>
            <button type="button" className="tb-link new-opt" onClick={() => pickNew('group')}>Nhóm mới</button>
            <button type="button" className="tb-link new-opt" onClick={() => pickNew('contact')}>Danh bạ mới</button>
            <div className="group-actions"><button type="button" className="tb-link" onClick={() => setNewOpen(false)}>Đóng</button></div>
          </div>
        </div>
      )}

      {newMsgOpen && (
        <div className="group-overlay" onClick={(e) => e.target === e.currentTarget && setNewMsgOpen(false)}>
          <div className="card group-sheet" role="dialog" aria-label="Tin nhắn mới">
            <strong>Tin nhắn mới</strong>
            <ul className="group-members">
              {contactList.map((f) => <li key={f.id}><button type="button" className="tb-link new-opt" onClick={() => startChat(f)}>{displayName(f)}</button></li>)}
              {!friends.length && <li className="search-hint">Chưa có bạn bè. Chọn Danh bạ mới để tìm người và kết bạn.</li>}
            </ul>
            <div className="group-actions"><button type="button" className="tb-link" onClick={() => setNewMsgOpen(false)}>Đóng</button></div>
          </div>
        </div>
      )}

      {groupOpen && (
        <div className="group-overlay" onClick={(e) => e.target === e.currentTarget && setGroupOpen(false)}>
          <div className="card group-sheet" role="dialog" aria-label="Tạo nhóm">
            <strong>Tạo nhóm</strong>
            <input value={groupName} onChange={(e) => setGroupName(e.target.value)} type="text" placeholder="Tên nhóm" maxLength={60} />
            <ul className="group-members">
              {groupCandidates.map((f) => (
                <li key={f.id}><label><input type="checkbox" checked={groupMembers.includes(f.id)} disabled={groupBusy} onChange={() => setGroupMembers((cur) => (cur.includes(f.id) ? cur.filter((x) => x !== f.id) : [...cur, f.id]))} /> {displayName(f)}</label></li>
              ))}
              {!groupCandidates.length && <li className="search-hint">Chưa có bạn bè nào dùng được để thêm vào nhóm.</li>}
            </ul>
            <p className="search-sub">Chọn ít nhất 2 bạn bè ({groupMembers.length} đã chọn). Nhóm chỉ nằm trên máy của các thành viên, tin nhắn mã hoá 2 đầu, máy chủ không lưu. Bạn chỉ gửi được cho thành viên là bạn bè của bạn.</p>
            {groupError && <div className="alert alert-error">{groupError}</div>}
            <div className="group-actions">
              <AppButton variant="ghost" size="sm" onClick={() => setGroupOpen(false)}>Đóng</AppButton>
              <AppButton variant="primary" size="sm" disabled={!canCreateGroup} onClick={createGroup}>{groupBusy ? 'Đang tạo...' : 'Tạo nhóm'}</AppButton>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
