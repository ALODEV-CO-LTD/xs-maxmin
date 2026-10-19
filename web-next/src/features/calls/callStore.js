// Voice-only calling between friends (port of stores/call.js; zustand instead of Pinia). WebRTC media goes peer to peer;
// this store also owns the signaling WebSocket (/api/ws/calls) and the small control protocol: call-invite / call-accept /
// call-reject / call-end / offer / answer / ice (backend/routes/api/ws/calls.dart is the authority on the shapes).
//
// One global call at a time. <CallOverlay /> renders whatever `status` is, mounted once in the app shell so an incoming
// call can be answered from any page. ICE servers come from GET /api/calls/ice-servers (STUN always, TURN when the
// server has one).
//
// The socket also carries chat frames: e2ee-* go to the chat store through ./transport (no import between the two),
// new-message / friend-request / friend-accepted / payment-decided go to the notify store.
import { create } from 'zustand'
import { api } from '@/lib/api'
import { useAuthStore } from '@/lib/authStore'
import { askNotificationPermission } from '@/lib/callSounds'
import { useNotifyStore } from '@/lib/notifyStore'
import { createVoiceChanger, loadVoiceFx, saveVoiceFx } from '@/lib/voiceFx'
import { bindSocket, transport } from './transport'

const STUN_SERVERS = [{ urls: 'stun:stun.l.google.com:19302' }]
const ICE_CACHE_MS = 10 * 60 * 1000
const RECONNECT_GRACE_MS = 20000 // how long a dropped connection may try to recover (ICE restart) before the call ends
const MAX_ICE_RESTARTS = 2
const RING_TIMEOUT_MS = 30000
const MEDIA_PROMPT_TIMEOUT_MS = 60000 // an ignored mic prompt never settles on its own
const MEDIA_SETUP_TIMEOUT_MS = 25000 // ICE path must come up this long after the answer

let iceCache = { servers: STUN_SERVERS, at: 0 }
async function loadIceServers() {
  if (Date.now() - iceCache.at < ICE_CACHE_MS) return iceCache.servers
  try {
    const res = await api.get('/calls/ice-servers')
    if (Array.isArray(res.iceServers) && res.iceServers.length) iceCache = { servers: res.iceServers, at: Date.now() }
  } catch {
    /* keep STUN: a call can still work without TURN */
  }
  return iceCache.servers
}

// Plain-language text for each way getUserMedia can fail; null when unrecognised.
export function mediaErrorMessage(err) {
  const device = 'micro'
  switch (err?.name) {
    case 'NotAllowedError':
    case 'SecurityError':
      return `Chưa được cấp quyền dùng ${device}. Bấm biểu tượng ổ khoá cạnh thanh địa chỉ, chọn cho phép ${device} rồi gọi lại.`
    case 'NotFoundError':
    case 'OverconstrainedError':
      return `Không tìm thấy ${device} trên thiết bị này.`
    case 'NotReadableError':
    case 'AbortError':
      return `Không mở được ${device}, có thể ứng dụng khác đang dùng.`
    case 'NotSupportedError':
      return 'Trình duyệt này không hỗ trợ gọi. Hãy mở trang bằng HTTPS bằng Chrome, Safari hoặc Edge bản mới.'
    default:
      return null
  }
}

// getUserMedia with a timeout; a stream that arrives after the timeout is stopped, not leaked (it would keep recording).
function acquireMedia() {
  if (!navigator.mediaDevices?.getUserMedia) {
    const e = new Error('mediaDevices unavailable')
    e.name = 'NotSupportedError'
    return Promise.reject(e)
  }
  return new Promise((resolve, reject) => {
    let settled = false
    const timer = setTimeout(() => {
      settled = true
      const e = new Error('permission prompt timed out')
      e.name = 'NotAllowedError'
      reject(e)
    }, MEDIA_PROMPT_TIMEOUT_MS)
    navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true } }).then(
      (stream) => {
        clearTimeout(timer)
        if (settled) {
          stream.getTracks().forEach((t) => t.stop())
          return
        }
        settled = true
        resolve(stream)
      },
      (err) => {
        clearTimeout(timer)
        if (!settled) {
          settled = true
          reject(err)
        }
      },
    )
  })
}

function wsUrl(token) {
  const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  return `${proto}//${window.location.host}/api/ws/calls?token=${encodeURIComponent(token)}`
}

// Not reactive: handles that only this module touches.
let socket = null
let pc = null
let localStream = null
let voice = null
let pendingCandidates = []
let ringTimer = null
let monitorTimer = null
let failTimer = null
let reconnectTimer = null
let isCaller = false
let restartCount = 0

export const useCallStore = create((set, get) => {
  const send = (message) => {
    if (socket && get().socketReady) socket.send(JSON.stringify(message))
  }
  const sendTo = (to, extra) => send({ to, ...extra })
  bindSocket(send, () => !!socket && get().socketReady)

  const clearRingTimeout = () => {
    if (ringTimer) clearTimeout(ringTimer)
    ringTimer = null
  }
  const armRingTimeout = () => {
    clearRingTimeout()
    ringTimer = setTimeout(() => {
      const { status, peer } = get()
      if (status === 'incoming' || status === 'outgoing') {
        set({ error: status === 'incoming' ? `Bạn nhỡ cuộc gọi từ ${peer?.name || 'người dùng'}` : 'Không có phản hồi' })
        if (peer) sendTo(peer.id, { type: 'call-end' })
        cleanup()
      }
    }, RING_TIMEOUT_MS)
  }

  const stopMonitor = () => {
    if (monitorTimer) clearInterval(monitorTimer)
    monitorTimer = null
    set({ health: { level: 'info', text: '' } })
  }

  // Ends the call and frees everything. `error` is left as is so the overlay can show why it ended.
  function cleanup() {
    const wasInCall = get().status !== 'idle'
    clearRingTimeout()
    if (failTimer) clearTimeout(failTimer)
    failTimer = null
    restartCount = 0
    stopMonitor()
    pc?.close()
    pc = null
    voice?.stop()
    voice = null
    localStream?.getTracks().forEach((t) => t.stop())
    localStream = null
    pendingCandidates = []
    set((s) => ({
      ringing: false,
      reconnecting: false,
      remoteStream: null,
      status: 'idle',
      peer: null,
      muted: false,
      startedAt: null,
      endedTick: wasInCall ? s.endedTick + 1 : s.endedTick,
    }))
  }

  // Ends the call because *we* hit a problem and tells the other side too (our socket is still open, so the server's
  // disconnect handling would never do it).
  function failCall(message, reason) {
    set({ error: message })
    const { peer, status } = get()
    if (peer && status !== 'idle') sendTo(peer.id, { type: 'call-end', ...(reason ? { reason } : {}) })
    cleanup()
  }

  async function flushPendingCandidates() {
    const queued = pendingCandidates.splice(0)
    for (const c of queued) {
      try {
        await pc.addIceCandidate(c)
      } catch {
        /* ignore */
      }
    }
  }

  async function onRemoteIce(candidate) {
    if (!pc || !pc.remoteDescription) {
      pendingCandidates.push(candidate)
      return
    }
    try {
      await pc.addIceCandidate(candidate)
    } catch {
      /* ignore malformed / late candidates */
    }
  }

  // Every 2 s while connected: is the ICE path up, does our mic produce sound, do packets arrive?
  function startMonitor() {
    stopMonitor()
    const conn = pc
    if (!conn) return
    const began = Date.now()
    let lastRecv = 0
    let stalled = 0
    let flowed = false
    set({ health: { level: 'info', text: 'Đang thiết lập đường truyền âm thanh…' } })
    monitorTimer = setInterval(async () => {
      if (pc !== conn || get().status !== 'connected') return
      const ice = conn.iceConnectionState
      const up = ice === 'connected' || ice === 'completed'
      const elapsed = Date.now() - began
      if (!up) {
        if (elapsed > MEDIA_SETUP_TIMEOUT_MS) {
          failCall('Không thiết lập được đường truyền âm thanh giữa hai thiết bị (mạng đang chặn kết nối trực tiếp). Thử lại bằng mạng khác, ví dụ Wi-Fi thay cho 4G.', 'failed')
          return
        }
        set({
          health: elapsed > 8000
            ? { level: 'warn', text: 'Đường truyền âm thanh chưa thông, có thể mạng đang chặn. Đang thử thêm…' }
            : { level: 'info', text: 'Đang thiết lập đường truyền âm thanh…' },
        })
        return
      }
      let recv = 0
      try {
        const stats = await conn.getStats()
        stats.forEach((r) => {
          if (r.type === 'inbound-rtp' && r.kind === 'audio') recv = r.bytesReceived || 0
        })
      } catch {
        /* stats unavailable: fall back to the ICE state alone */
      }
      if (recv > lastRecv) {
        flowed = true
        stalled = 0
      } else stalled++
      lastRecv = recv
      const mic = localStream?.getAudioTracks()[0]
      if (!get().muted && (!mic || mic.readyState !== 'live' || mic.muted)) {
        set({ health: { level: 'warn', text: 'Micro của bạn không thu được tiếng. Kiểm tra micro đã bật chưa hoặc có ứng dụng khác đang dùng.' } })
      } else if (stalled >= 3) {
        set({ health: { level: 'warn', text: flowed ? 'Mất tín hiệu âm thanh từ đối phương.' : 'Chưa nhận được âm thanh từ đối phương. Nhờ họ kiểm tra micro.' } })
      } else {
        set({ health: { level: 'ok', text: 'Âm thanh đã thông' } })
      }
    }, 2000)
  }

  // Only the original caller creates the restart offer (avoids both sides offering at once); either side gives up
  // after RECONNECT_GRACE_MS if the path never comes back.
  async function tryIceRestart(conn) {
    if (pc !== conn || get().status !== 'connected') return
    if (!failTimer) {
      failTimer = setTimeout(() => {
        failTimer = null
        if (pc === conn && conn.connectionState !== 'connected') failCall('Mất kết nối mạng giữa hai thiết bị, cuộc gọi đã kết thúc.', 'failed')
      }, RECONNECT_GRACE_MS)
    }
    if (!isCaller || restartCount >= MAX_ICE_RESTARTS) return
    restartCount++
    try {
      const offer = await conn.createOffer({ iceRestart: true })
      await conn.setLocalDescription(offer)
      sendTo(get().peer.id, { type: 'offer', sdp: offer })
    } catch {
      /* the grace timer ends the call if nothing recovers */
    }
  }

  // Builds the RTCPeerConnection around the local stream already acquired in startCall / acceptCall.
  async function setupPeerConnection() {
    if (!localStream) throw new Error('Chưa có micro để bắt đầu cuộc gọi')
    const iceServers = await loadIceServers()
    if (!localStream) throw new Error('Cuộc gọi đã kết thúc')
    const conn = new RTCPeerConnection({ iceServers })
    // The call sends the voice-changer's output (the raw mic when the effect is off), so it can be toggled mid-call.
    voice = createVoiceChanger(localStream, get().voiceFx)
    set({ voiceFxSupported: voice.supported })
    for (const track of voice.stream.getTracks()) conn.addTrack(track, voice.stream)
    conn.onicecandidate = (e) => {
      const { peer } = get()
      if (e.candidate && peer) sendTo(peer.id, { type: 'ice', candidate: e.candidate.toJSON() })
    }
    conn.ontrack = (e) => set({ remoteStream: e.streams[0] })
    conn.onconnectionstatechange = () => {
      if (pc !== conn || get().status !== 'connected') return
      const state = conn.connectionState
      if (state === 'connected') {
        set({ reconnecting: false })
        if (failTimer) clearTimeout(failTimer)
        failTimer = null
      } else if (state === 'disconnected' || state === 'failed') {
        // Network switched or blipped: try an ICE restart for a while before giving up, like a phone call.
        set({ reconnecting: true })
        tryIceRestart(conn)
      } else if (state === 'closed') cleanup()
    }
    pc = conn
  }

  async function startAsCaller() {
    try {
      await setupPeerConnection()
      const offer = await pc.createOffer()
      await pc.setLocalDescription(offer)
      sendTo(get().peer.id, { type: 'offer', sdp: offer })
    } catch (err) {
      failCall(err.message || 'Không thể bắt đầu cuộc gọi')
    }
  }

  async function onOffer(sdp) {
    try {
      if (!localStream) return // call already ended / never accepted
      if (pc && get().status === 'connected') {
        // The caller restarted ICE: answer on the same connection.
        await pc.setRemoteDescription(sdp)
        await flushPendingCandidates()
        const reanswer = await pc.createAnswer()
        await pc.setLocalDescription(reanswer)
        sendTo(get().peer.id, { type: 'answer', sdp: reanswer })
        return
      }
      await setupPeerConnection()
      await pc.setRemoteDescription(sdp)
      await flushPendingCandidates()
      const answer = await pc.createAnswer()
      await pc.setLocalDescription(answer)
      sendTo(get().peer.id, { type: 'answer', sdp: answer })
      set({ status: 'connected', startedAt: Date.now() })
      startMonitor()
    } catch (err) {
      failCall(err.message || 'Không thể kết nối cuộc gọi')
    }
  }

  async function onAnswer(sdp) {
    if (!pc) return // call ended while the answer was in flight
    try {
      await pc.setRemoteDescription(sdp)
      await flushPendingCandidates()
      if (get().status === 'connected') return // answer to an ICE restart: keep the timer
      set({ status: 'connected', startedAt: Date.now() })
      startMonitor()
    } catch (err) {
      failCall(err.message || 'Không thể kết nối cuộc gọi')
    }
  }

  function handleMessage(raw) {
    let msg
    try {
      msg = JSON.parse(raw)
    } catch {
      return
    }
    const s = get()
    const peerIs = (id) => s.peer?.id === id
    switch (msg.type) {
      case 'call-invite':
        // Already on a call / ringing / mid permission prompt: behave like a busy line.
        if (s.status !== 'idle' || s.acquiring) {
          sendTo(msg.from, { type: 'call-reject', reason: 'busy' })
          return
        }
        set({ peer: { id: msg.from, name: msg.fromName || 'Người dùng' }, status: 'incoming' })
        armRingTimeout()
        break
      case 'e2ee-msg':
      case 'e2ee-ack':
      case 'e2ee-undelivered':
        transport.deliverToChat(msg)
        break
      case 'new-message':
        useNotifyStore.getState().receive(msg, { isAdmin: useAuthStore.getState().role === 'admin' })
        break
      case 'friend-request':
        useNotifyStore.getState().friendRequestReceived(msg)
        break
      case 'friend-accepted':
        useNotifyStore.getState().friendAcceptedByPeer(msg)
        break
      case 'payment-decided':
        useNotifyStore.getState().paymentDecided(msg)
        useAuthStore.getState().fetchMe().catch(() => {})
        break
      case 'call-ringing':
        if (s.status === 'outgoing' && peerIs(msg.from)) set({ ringing: true })
        break
      case 'call-accept':
        if (s.status === 'outgoing' && peerIs(msg.from)) {
          clearRingTimeout()
          startAsCaller()
        }
        break
      case 'call-reject':
        if (peerIs(msg.from)) {
          set({ error: msg.reason === 'busy' ? 'Người này đang bận' : 'Cuộc gọi bị từ chối' })
          cleanup()
        }
        break
      case 'call-unavailable':
        if (peerIs(msg.from)) {
          set({ error: 'Người này hiện không trực tuyến' })
          cleanup()
        }
        break
      case 'call-end':
        if (peerIs(msg.from)) {
          if (s.status === 'incoming') set({ error: `Bạn nhỡ cuộc gọi từ ${s.peer.name}` })
          // `reason: 'disconnected'` is synthesized by the server when the other tab closed / lost network.
          if (msg.reason === 'disconnected') set({ error: 'Đối phương bị mất kết nối, cuộc gọi đã kết thúc' })
          else if (msg.reason === 'media-error') set({ error: 'Đối phương không bật được micro nên không nghe máy được' })
          else if (msg.reason === 'failed') set({ error: 'Không thể kết nối trực tiếp giữa hai thiết bị (mạng đang chặn). Thử lại bằng mạng khác.' })
          cleanup()
        }
        break
      case 'offer':
        if (peerIs(msg.from)) onOffer(msg.sdp)
        break
      case 'answer':
        if (peerIs(msg.from)) onAnswer(msg.sdp)
        break
      case 'ice':
        if (peerIs(msg.from) && msg.candidate) onRemoteIce(msg.candidate)
        break
      case 'call-error':
        set({ error: msg.error || 'Lỗi cuộc gọi' })
        if (s.status !== 'idle') cleanup()
        break
    }
  }

  return {
    socketReady: false,
    status: 'idle', // 'idle' | 'outgoing' | 'incoming' | 'connecting' | 'connected'
    acquiring: false, // the mic permission prompt of a call we are about to place is open (status is still idle)
    peer: null, // { id, name }
    muted: false,
    voiceFx: loadVoiceFx(), // "Méo giọng", remembered on this device
    voiceFxSupported: true,
    ringing: false, // the callee's phone is ringing
    reconnecting: false, // a connected call lost its network path and tries to recover
    endedTick: 0, // bumps whenever a call ends so call history reloads
    error: '',
    startedAt: null,
    remoteStream: null,
    health: { level: 'info', text: '' },

    // Called once when the signed-in shell mounts (and again after login): the socket stays live so an incoming call or
    // a chat frame can arrive on any page.
    connect() {
      if (socket) return
      const token = useAuthStore.getState().token
      if (!token) return
      const ws = new WebSocket(wsUrl(token))
      ws.onopen = () => {
        set({ socketReady: true })
        loadIceServers()
        useNotifyStore.getState().refresh() // messages may have arrived while the socket was down
      }
      ws.onclose = (event) => {
        if (socket === ws) socket = null
        set({ socketReady: false })
        // A dead signaling channel cannot carry a call: end it instead of leaving "Đang gọi..." forever.
        if (get().status !== 'idle') {
          set((s) => ({ error: s.error || 'Mất kết nối, cuộc gọi đã kết thúc' }))
          cleanup()
        }
        // 4401: the server revoked this session. Drop it instead of reconnecting in a loop.
        if (event && event.code === 4401) {
          useAuthStore.getState().clear()
          return
        }
        if (useAuthStore.getState().token && !closing) {
          clearTimeout(reconnectTimer)
          reconnectTimer = setTimeout(() => get().connect(), 3000)
        }
      }
      ws.onerror = () => {} // onclose follows
      ws.onmessage = (event) => handleMessage(event.data)
      socket = ws
    },

    disconnect() {
      closing = true
      clearTimeout(reconnectTimer)
      get().endCall()
      const ws = socket
      socket = null
      ws?.close()
      set({ socketReady: false })
      closing = false
    },

    // The mic permission prompt is raised here, straight from the click that starts the call and before anything is
    // sent: browsers (iOS Safari) only show it from a user gesture, and the other phone must not ring for a call we
    // then cannot take.
    async startCall(friend) {
      const s = get()
      if (s.status !== 'idle' || s.acquiring) return
      set({ error: '' })
      // Same rule as the server: calls are customer to customer only.
      if (useAuthStore.getState().role === 'admin' || friend.isAdmin) {
        set({ error: 'Chỉ khách hàng gọi được cho nhau, không gọi cho Admin. Hãy nhắn tin để được hỗ trợ.' })
        return
      }
      if (!s.socketReady) {
        set({ error: 'Chưa kết nối tới máy chủ cuộc gọi, vui lòng thử lại sau vài giây.' })
        return
      }
      set({ acquiring: true })
      askNotificationPermission()
      loadIceServers()
      let stream
      try {
        stream = await acquireMedia()
      } catch (err) {
        set({ error: mediaErrorMessage(err) || err.message || 'Không bật được micro' })
        return
      } finally {
        set({ acquiring: false })
      }
      // The socket can drop while the prompt is open: do not start a call on top of that or leave the mic running.
      if (get().status !== 'idle' || !get().socketReady) {
        stream.getTracks().forEach((t) => t.stop())
        if (!get().socketReady) set({ error: 'Mất kết nối tới máy chủ cuộc gọi, vui lòng thử lại.' })
        return
      }
      localStream = stream
      isCaller = true
      set({ peer: { id: friend.id, name: friend.name }, ringing: false, status: 'outgoing' })
      sendTo(friend.id, { type: 'call-invite', fromName: useAuthStore.getState().user?.name || 'Người dùng' })
      armRingTimeout()
    },

    // Same reasoning: ask for the mic from the "Nghe máy" click and only tell the caller to go on once we have it.
    async acceptCall() {
      const { status, peer } = get()
      if (status !== 'incoming' || !peer) return
      const peerId = peer.id
      clearRingTimeout()
      isCaller = false
      askNotificationPermission()
      loadIceServers()
      set({ status: 'connecting' }) // shown while the permission prompt is open
      let stream
      try {
        stream = await acquireMedia()
      } catch (err) {
        if (get().peer?.id === peerId) failCall(mediaErrorMessage(err) || err.message || 'Không bật được micro', 'media-error')
        return
      }
      // The caller may have hung up while the prompt was open.
      if (get().status !== 'connecting' || get().peer?.id !== peerId) {
        stream.getTracks().forEach((t) => t.stop())
        return
      }
      localStream = stream
      sendTo(peerId, { type: 'call-accept' }) // the connection is made when the caller's `offer` arrives
    },

    rejectCall() {
      const { status, peer } = get()
      if (status !== 'incoming' || !peer) return
      sendTo(peer.id, { type: 'call-reject' })
      cleanup()
    },

    toggleVoiceFx() {
      const on = !get().voiceFx
      set({ voiceFx: on })
      saveVoiceFx(on)
      voice?.setEnabled(on)
    },

    toggleMute() {
      if (!localStream) return
      const muted = !get().muted
      set({ muted })
      for (const track of localStream.getAudioTracks()) track.enabled = !muted
    },

    endCall() {
      const { peer, status } = get()
      if (peer && status !== 'idle') sendTo(peer.id, { type: 'call-end' })
      cleanup()
    },

    clearError() {
      set({ error: '' })
    },
  }
})
let closing = false

export const inCall = () => useCallStore.getState().status !== 'idle'
