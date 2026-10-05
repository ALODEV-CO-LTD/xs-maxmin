// Voice-only calling between friends (video was removed, K31) - WebRTC peer-to-peer media, with
// this store owning the signaling WebSocket (/ws/calls) and the small
// control-message protocol: call-invite / call-accept / call-reject /
// call-end / offer / answer / ice (see backend/routes/ws/calls.dart for
// the authoritative message shapes - this file mirrors them exactly).
//
// Single global call at a time, singleton state - CallOverlay.vue renders
// whatever this store's `status` is, mounted once at the app root so an
// incoming call can be answered from any page, not just the Bạn bè tab.
//
// ICE servers come from GET /api/calls/ice-servers: STUN always, plus a TURN
// relay when the server is configured with one (XOSO_TURN_*). STUN alone
// works on most home/office connections but fails across strict NATs (some
// mobile carriers, locked-down offices); TURN is what fixes those.
import { defineStore } from 'pinia'
import { api } from '../api'
import { useAuthStore } from './auth'
import { askNotificationPermission } from '../callSounds'
import { useNotifyStore } from './notify'

const STUN_SERVERS = [{ urls: 'stun:stun.l.google.com:19302' }]
const ICE_CACHE_MS = 10 * 60 * 1000
// How long a dropped connection may try to recover (ICE restart) before the
// call is ended.
const RECONNECT_GRACE_MS = 20000
const MAX_ICE_RESTARTS = 2

let iceCache = { servers: STUN_SERVERS, at: 0 }
async function loadIceServers() {
  if (Date.now() - iceCache.at < ICE_CACHE_MS) return iceCache.servers
  try {
    const res = await api.get('/calls/ice-servers')
    if (Array.isArray(res.iceServers) && res.iceServers.length) iceCache = { servers: res.iceServers, at: Date.now() }
  } catch {
    /* keep whatever we had (STUN) - a call can still work without TURN */
  }
  return iceCache.servers
}
const RING_TIMEOUT_MS = 30000
// How long to wait on the browser's own mic permission prompt before
// giving up - a prompt the user ignores never settles on its own.
const MEDIA_PROMPT_TIMEOUT_MS = 60000
// How long to wait for the ICE path to come up after the answer before
// giving up on the call (a restrictive NAT never gets there).
const MEDIA_SETUP_TIMEOUT_MS = 25000

// Plain-language text for each way getUserMedia can fail, so a denied or
// missing microphone explains itself (and how to fix it) instead of
// surfacing the browser's raw "Permission denied". Returns null for
// anything unrecognised so the caller can fall back to its own message.
function mediaErrorMessage(err) {
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

// getUserMedia with a timeout, and with a stream that arrives *after* the
// timeout (user finally clicked Allow) stopped instead of leaked - a leaked
// stream would leave the microphone silently recording with no call.
function acquireMedia() {
  if (!navigator.mediaDevices?.getUserMedia) {
    const e = new Error('mediaDevices unavailable')
    e.name = 'NotSupportedError' // missing on non-HTTPS pages and very old browsers
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
    // Voice-tuned capture: echo cancellation, noise suppression and automatic
    // gain are what make a call usable on a phone speaker.
    navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
    }).then(
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
  // Under /api so it shares the same dev-server proxy and production nginx
  // location as every other request - a separate /ws path didn't reliably
  // get its upgrade forwarded by Vite's dev proxy.
  return `${proto}//${window.location.host}/api/ws/calls?token=${encodeURIComponent(token)}`
}

export const useCallStore = defineStore('call', {
  state: () => ({
    socket: null,
    socketReady: false,
    // 'idle' | 'outgoing' | 'incoming' | 'connecting' | 'connected'
    status: 'idle',
    // True while the browser's mic permission prompt is open for a
    // call we're about to place - status is still 'idle' then, so the call
    // buttons need this to stay disabled and avoid a second prompt.
    acquiring: false,
    peer: null, // { id, name }
    muted: false,
    // True once the callee's phone is ringing ("Đang đổ chuông" instead of "Đang gọi").
    ringing: false,
    // True while a connected call lost its network path and is trying to recover.
    reconnecting: false,
    // Bumped every time a call ends, so views that show call history can reload.
    endedTick: 0,
    error: '',
    startedAt: null,
    pc: null,
    localStream: null,
    remoteStream: null,
    // Live read-out of whether audio is actually flowing, shown in the call
    // card. 'connected' status only means the signaling handshake finished -
    // it says nothing about whether media got through (NAT, mic, speaker).
    health: { level: 'info', text: '' }, // level: 'info' | 'ok' | 'warn'
    _pendingCandidates: [],
    _ringTimer: null,
    _monitorTimer: null,
    _isCaller: false,
    _restartCount: 0,
    _failTimer: null,
  }),

  actions: {
    // Called once from AppShell.vue on mount (and again after login) so
    // the socket is live whenever there's a logged-in session - an
    // incoming call can arrive while the user is anywhere in the app.
    connect() {
      if (this.socket) return
      const auth = useAuthStore()
      if (!auth.token) return
      const socket = new WebSocket(wsUrl(auth.token))
      socket.onopen = () => {
        this.socketReady = true
        loadIceServers()
      }
      socket.onclose = () => {
        this.socketReady = false
        this.socket = null
        // A dead signaling channel can't carry a call anyway - end
        // whatever was in progress (same as a dropped phone call) instead
        // of leaving the UI stuck on "Đang gọi..."/"Đang kết nối..." forever
        // with no way to reach the other side.
        if (this.status !== 'idle') {
          this.error = this.error || 'Mất kết nối, cuộc gọi đã kết thúc'
          this._cleanup()
        }
        // Reconnect after a short delay as long as the session is still
        // logged in - covers the dev server restarting, a brief network
        // blip, the server-side ping timeout above firing, etc.
        if (useAuthStore().token) {
          setTimeout(() => this.connect(), 3000)
        }
      }
      socket.onerror = () => {
        /* onclose fires right after; handled there */
      }
      socket.onmessage = (event) => this._handleMessage(event.data)
      this.socket = socket
    },

    disconnect() {
      this.endCall()
      this.socket?.close()
      this.socket = null
      this.socketReady = false
    },

    _send(message) {
      if (this.socket && this.socketReady) {
        this.socket.send(JSON.stringify(message))
      }
    },

    _handleMessage(raw) {
      let msg
      try {
        msg = JSON.parse(raw)
      } catch {
        return
      }
      switch (msg.type) {
        case 'call-invite':
          // Already on a call/ringing (or mid permission prompt for one we
          // are placing) - behave like a busy line.
          if (this.status !== 'idle' || this.acquiring) {
            this._sendTo(msg.from, { type: 'call-reject', reason: 'busy' })
            return
          }
          this.peer = { id: msg.from, name: msg.fromName || 'Người dùng' }
          this.status = 'incoming'
          this._armRingTimeout()
          break
        case 'new-message':
          useNotifyStore().receive(msg, { isAdmin: useAuthStore().isAdmin })
          break
        case 'call-ringing':
          if (this.status === 'outgoing' && msg.from === this.peer?.id) this.ringing = true
          break
        case 'call-accept':
          if (this.status === 'outgoing' && msg.from === this.peer?.id) {
            this._clearRingTimeout()
            this._startAsCaller()
          }
          break
        case 'call-reject':
          if (this.peer?.id === msg.from) {
            this.error = msg.reason === 'busy' ? 'Người này đang bận' : 'Cuộc gọi bị từ chối'
            this._cleanup()
          }
          break
        case 'call-unavailable':
          if (this.peer?.id === msg.from) {
            this.error = 'Người này hiện không trực tuyến'
            this._cleanup()
          }
          break
        case 'call-end':
          if (this.peer?.id === msg.from) {
            if (this.status === 'incoming') this.error = `Bạn nhỡ cuộc gọi từ ${this.peer.name}`
            // `reason: 'disconnected'` means the server itself synthesized
            // this - the other side's tab closed/crashed/lost network
            // before they could send a real call-end (see
            // backend/routes/api/ws/calls.dart) - worth telling the user
            // why the call just vanished instead of leaving it silent.
            if (msg.reason === 'disconnected') this.error = 'Đối phương bị mất kết nối, cuộc gọi đã kết thúc'
            else if (msg.reason === 'media-error') this.error = 'Đối phương không bật được micro nên không nghe máy được'
            else if (msg.reason === 'failed') this.error = 'Không thể kết nối trực tiếp giữa hai thiết bị (mạng đang chặn). Thử lại bằng mạng khác.'
            this._cleanup()
          }
          break
        case 'offer':
          if (this.peer?.id === msg.from) this._onOffer(msg.sdp)
          break
        case 'answer':
          if (this.peer?.id === msg.from) this._onAnswer(msg.sdp)
          break
        case 'ice':
          if (this.peer?.id === msg.from && msg.candidate) this._onRemoteIce(msg.candidate)
          break
        case 'call-error':
          this.error = msg.error || 'Lỗi cuộc gọi'
          if (this.status !== 'idle') this._cleanup()
          break
      }
    },

    _sendTo(to, extra) {
      this._send({ to, ...extra })
    },

    _armRingTimeout() {
      this._clearRingTimeout()
      this._ringTimer = setTimeout(() => {
        if (this.status === 'incoming' || this.status === 'outgoing') {
          this.error = this.status === 'incoming' ? `Bạn nhỡ cuộc gọi từ ${this.peer?.name || 'người dùng'}` : 'Không có phản hồi'
          if (this.peer) this._sendTo(this.peer.id, { type: 'call-end' })
          this._cleanup()
        }
      }, RING_TIMEOUT_MS)
    },
    _clearRingTimeout() {
      if (this._ringTimer) clearTimeout(this._ringTimer)
      this._ringTimer = null
    },

    // ---- Outgoing call ----------------------------------------------
    // The mic permission prompt is raised here, straight from the
    // click that starts the call, *before* anything is sent - not later when
    // the signaling socket delivers the other side's answer. Two reasons:
    // browsers (Safari/iOS especially) are strict about only showing the
    // prompt from a user gesture, and failing early means the other person's
    // phone is never made to ring for a call we then can't take.
    async startCall(friend) {
      if (this.status !== 'idle' || this.acquiring) return
      this.error = ''
      // Same rule the server enforces (see backend/routes/api/ws/calls.dart):
      // calls are customer-to-customer only, never to or from Admin.
      if (useAuthStore().isAdmin || friend.isAdmin) {
        this.error = 'Chỉ khách hàng gọi được cho nhau, không gọi cho Admin. Hãy nhắn tin để được hỗ trợ.'
        return
      }
      if (!this.socketReady) {
        this.error = 'Chưa kết nối tới máy chủ cuộc gọi, vui lòng thử lại sau vài giây.'
        return
      }
      this.acquiring = true
      askNotificationPermission()
      loadIceServers()
      let stream
      try {
        stream = await acquireMedia()
      } catch (err) {
        this.error = mediaErrorMessage(err) || err.message || 'Không bật được micro'
        return
      } finally {
        this.acquiring = false
      }
      // The socket can drop, or (not possible today but cheap to guard) the
      // state can move on, while the prompt was open - don't start a call
      // on top of that and don't leave the microphone running.
      if (this.status !== 'idle' || !this.socketReady) {
        stream.getTracks().forEach((t) => t.stop())
        if (!this.socketReady) this.error = 'Mất kết nối tới máy chủ cuộc gọi, vui lòng thử lại.'
        return
      }
      this.localStream = stream
      this.peer = { id: friend.id, name: friend.name }
      this._isCaller = true
      this.ringing = false
      this.status = 'outgoing'
      const auth = useAuthStore()
      this._sendTo(friend.id, { type: 'call-invite', fromName: auth.user?.name || 'Người dùng' })
      this._armRingTimeout()
    },

    async _startAsCaller() {
      try {
        await this._setupPeerConnection()
        const offer = await this.pc.createOffer()
        await this.pc.setLocalDescription(offer)
        this._sendTo(this.peer.id, { type: 'offer', sdp: offer })
      } catch (err) {
        this._failCall(err.message || 'Không thể bắt đầu cuộc gọi')
      }
    },

    // ---- Incoming call -------------------------------------------------
    // Same reasoning as startCall: ask for the mic from the "Nghe máy"
    // click and only tell the caller to proceed once we actually have it.
    // If the user denies it we tell the caller too - otherwise they'd sit on
    // "Đang gọi…" with no ring timeout left (it's cleared on accept) and no
    // way to know the other side gave up.
    async acceptCall() {
      if (this.status !== 'incoming' || !this.peer) return
      const peerId = this.peer.id
      this._clearRingTimeout()
      this._isCaller = false
      askNotificationPermission()
      loadIceServers()
      this.status = 'connecting' // shown while the permission prompt is open
      let stream
      try {
        stream = await acquireMedia()
      } catch (err) {
        if (this.peer?.id === peerId) {
          this._failCall(mediaErrorMessage(err) || err.message || 'Không bật được micro', 'media-error')
        }
        return
      }
      // The caller may have hung up (call-end) while the prompt was open.
      if (this.status !== 'connecting' || this.peer?.id !== peerId) {
        stream.getTracks().forEach((t) => t.stop())
        return
      }
      this.localStream = stream
      // Actual connection is established once the caller's `offer` arrives
      // (handled in _onOffer) - this tells the caller to proceed.
      this._sendTo(peerId, { type: 'call-accept' })
    },

    rejectCall() {
      if (this.status !== 'incoming' || !this.peer) return
      this._sendTo(this.peer.id, { type: 'call-reject' })
      this._cleanup()
    },

    async _onOffer(sdp) {
      try {
        if (!this.localStream) return // call already ended / never accepted
        if (this.pc && this.status === 'connected') {
          // The caller restarted ICE after the network path dropped: answer on
          // the same connection instead of building a new one.
          await this.pc.setRemoteDescription(sdp)
          await this._flushPendingCandidates()
          const reanswer = await this.pc.createAnswer()
          await this.pc.setLocalDescription(reanswer)
          this._sendTo(this.peer.id, { type: 'answer', sdp: reanswer })
          return
        }
        await this._setupPeerConnection()
        await this.pc.setRemoteDescription(sdp)
        await this._flushPendingCandidates()
        const answer = await this.pc.createAnswer()
        await this.pc.setLocalDescription(answer)
        this._sendTo(this.peer.id, { type: 'answer', sdp: answer })
        this.status = 'connected'
        this.startedAt = Date.now()
        this._startMonitor()
      } catch (err) {
        this._failCall(err.message || 'Không thể kết nối cuộc gọi')
      }
    },

    async _onAnswer(sdp) {
      if (!this.pc) return // call ended while the answer was in flight
      try {
        await this.pc.setRemoteDescription(sdp)
        await this._flushPendingCandidates()
        // Answer to an ICE restart: the call is already running, keep its timer.
        if (this.status === 'connected') return
        this.status = 'connected'
        this.startedAt = Date.now()
        this._startMonitor()
      } catch (err) {
        this._failCall(err.message || 'Không thể kết nối cuộc gọi')
      }
    },

    async _onRemoteIce(candidate) {
      if (!this.pc || !this.pc.remoteDescription) {
        this._pendingCandidates.push(candidate)
        return
      }
      try {
        await this.pc.addIceCandidate(candidate)
      } catch {
        /* ignore malformed/late candidates */
      }
    },

    async _flushPendingCandidates() {
      const queued = this._pendingCandidates.splice(0)
      for (const c of queued) {
        try {
          await this.pc.addIceCandidate(c)
        } catch {
          /* ignore */
        }
      }
    },

    // Builds the RTCPeerConnection around the local stream already acquired
    // in startCall/acceptCall (see the note above startCall).
    async _setupPeerConnection() {
      if (!this.localStream) throw new Error('Chưa có micro để bắt đầu cuộc gọi')
      const iceServers = await loadIceServers()
      if (!this.localStream) throw new Error('Cuộc gọi đã kết thúc')
      const pc = new RTCPeerConnection({ iceServers })
      for (const track of this.localStream.getTracks()) {
        pc.addTrack(track, this.localStream)
      }
      pc.onicecandidate = (e) => {
        if (e.candidate && this.peer) {
          this._sendTo(this.peer.id, { type: 'ice', candidate: e.candidate.toJSON() })
        }
      }
      pc.ontrack = (e) => {
        this.remoteStream = e.streams[0]
      }
      pc.onconnectionstatechange = () => {
        if (this.pc !== pc || this.status !== 'connected') return
        const state = pc.connectionState
        if (state === 'connected') {
          // Back (or up for the first time): stop the recovery countdown.
          this.reconnecting = false
          if (this._failTimer) clearTimeout(this._failTimer)
          this._failTimer = null
        } else if (state === 'disconnected' || state === 'failed') {
          // Network switched (Wi-Fi <-> 4G) or blipped. Try to recover for a
          // while with an ICE restart before giving up, like a phone call
          // that "reconnects" instead of dropping.
          this.reconnecting = true
          this._tryIceRestart(pc)
        } else if (state === 'closed') {
          this._cleanup()
        }
      }
      this.pc = pc
    },

    // Only the original caller creates the restart offer (avoids both sides
    // offering at once); the callee just waits and answers. Either side gives
    // up after RECONNECT_GRACE_MS if the path never comes back.
    async _tryIceRestart(pc) {
      if (this.pc !== pc || this.status !== 'connected') return
      if (!this._failTimer) {
        this._failTimer = setTimeout(() => {
          this._failTimer = null
          if (this.pc === pc && pc.connectionState !== 'connected') {
            this._failCall('Mất kết nối mạng giữa hai thiết bị, cuộc gọi đã kết thúc.', 'failed')
          }
        }, RECONNECT_GRACE_MS)
      }
      if (!this._isCaller || this._restartCount >= MAX_ICE_RESTARTS) return
      this._restartCount++
      try {
        const offer = await pc.createOffer({ iceRestart: true })
        await pc.setLocalDescription(offer)
        this._sendTo(this.peer.id, { type: 'offer', sdp: offer })
      } catch {
        /* the grace timer above ends the call if nothing recovers */
      }
    },

    // Every 2s while connected: is the ICE path up, is our mic producing sound,
    // are packets arriving from the other side? Turns "call connected but
    // nobody can hear anything" into a message saying which part is wrong, and
    // hangs up (telling the peer) if the network path never comes up at all.
    _startMonitor() {
      this._stopMonitor()
      const pc = this.pc
      if (!pc) return
      const began = Date.now()
      let lastRecv = 0
      let stalled = 0
      let flowed = false
      this.health = { level: 'info', text: 'Đang thiết lập đường truyền âm thanh…' }
      this._monitorTimer = setInterval(async () => {
        if (this.pc !== pc || this.status !== 'connected') return
        const ice = pc.iceConnectionState
        const up = ice === 'connected' || ice === 'completed'
        const elapsed = Date.now() - began
        if (!up) {
          if (elapsed > MEDIA_SETUP_TIMEOUT_MS) {
            this._failCall(
              'Không thiết lập được đường truyền âm thanh giữa hai thiết bị (mạng đang chặn kết nối trực tiếp). Thử lại bằng mạng khác, ví dụ Wi-Fi thay cho 4G.',
              'failed',
            )
            return
          }
          this.health = elapsed > 8000
            ? { level: 'warn', text: 'Đường truyền âm thanh chưa thông, có thể mạng đang chặn. Đang thử thêm…' }
            : { level: 'info', text: 'Đang thiết lập đường truyền âm thanh…' }
          return
        }
        let recv = 0
        try {
          const stats = await pc.getStats()
          stats.forEach((r) => {
            if (r.type === 'inbound-rtp' && r.kind === 'audio') recv = r.bytesReceived || 0
          })
        } catch {
          /* stats unavailable - fall back to the ICE state alone */
        }
        if (recv > lastRecv) {
          flowed = true
          stalled = 0
        } else {
          stalled++
        }
        lastRecv = recv
        const mic = this.localStream?.getAudioTracks()[0]
        if (!this.muted && (!mic || mic.readyState !== 'live' || mic.muted)) {
          this.health = { level: 'warn', text: 'Micro của bạn không thu được tiếng. Kiểm tra micro đã bật chưa hoặc có ứng dụng khác đang dùng.' }
        } else if (stalled >= 3) {
          this.health = {
            level: 'warn',
            text: flowed ? 'Mất tín hiệu âm thanh từ đối phương.' : 'Chưa nhận được âm thanh từ đối phương. Nhờ họ kiểm tra micro.',
          }
        } else {
          this.health = { level: 'ok', text: 'Âm thanh đã thông' }
        }
      }, 2000)
    },

    _stopMonitor() {
      if (this._monitorTimer) clearInterval(this._monitorTimer)
      this._monitorTimer = null
      this.health = { level: 'info', text: '' }
    },

    // Ends the call because *we* hit a problem, and - unlike _cleanup()
    // alone - tells the other side. Without that the peer is left on
    // "Đang gọi…"/"Đang kết nối…" indefinitely (a failure here never reaches
    // the server's disconnect handling since our socket is still open).
    _failCall(message, reason) {
      this.error = message
      if (this.peer && this.status !== 'idle') {
        this._sendTo(this.peer.id, { type: 'call-end', ...(reason ? { reason } : {}) })
      }
      this._cleanup()
    },

    toggleMute() {
      if (!this.localStream) return
      this.muted = !this.muted
      for (const track of this.localStream.getAudioTracks()) track.enabled = !this.muted
    },

    endCall() {
      if (this.peer && this.status !== 'idle') {
        this._sendTo(this.peer.id, { type: 'call-end' })
      }
      this._cleanup()
    },

    _cleanup() {
      const wasInCall = this.status !== 'idle'
      this._clearRingTimeout()
      if (this._failTimer) clearTimeout(this._failTimer)
      this._failTimer = null
      this.ringing = false
      this.reconnecting = false
      this._restartCount = 0
      this._stopMonitor()
      this.pc?.close()
      this.pc = null
      this.localStream?.getTracks().forEach((t) => t.stop())
      this.localStream = null
      this.remoteStream = null
      this.status = 'idle'
      this.peer = null
      this.muted = false
      this.startedAt = null
      this._pendingCandidates = []
      if (wasInCall) this.endedTick++
      // Leave `error` as-is briefly so the UI can show why the call ended;
      // CallOverlay clears it the next time a call starts.
    },

    clearError() {
      this.error = ''
    },
  },
})
