<!--
  Global call UI - mounted once in AppShell.vue so an incoming call can be
  answered from anywhere in the app, not just the Bạn bè tab. Purely a view
  over useCallStore's state; all WebRTC/signaling logic lives there.
-->
<script setup>
import AppIcon from './AppIcon.vue'
import { computed, ref, watch, onBeforeUnmount } from 'vue'
import { useCallStore } from '../stores/call'

const call = useCallStore()

const localVideoEl = ref(null)
const remoteVideoEl = ref(null)
const remoteAudioEl = ref(null)

// Attach each stream to its element whenever *either* one changes. The
// remote stream arrives (pc.ontrack) while the call is still 'outgoing' /
// 'connecting', but the <audio>/<video> elements only exist once the status
// is 'connected' - so watching the stream alone attached it to nothing and
// the call was silent. Watching the element refs too re-attaches the moment
// they mount. flush:'post' so the refs are already filled in.
// True when the browser refused to start the remote audio on its own. iOS
// Safari does this unless play() runs inside a tap, and the call connects a
// while after the last tap - so the call is "connected" but silent. Showing a
// button turns that into one tap instead of a dead call.
const speakerBlocked = ref(false)
function attach(el, stream) {
  if (!el) return
  if (el.srcObject !== (stream || null)) el.srcObject = stream || null
  // autoplay normally handles this, but an explicit play() recovers from a
  // browser that paused the element.
  if (stream && el.play) {
    el.play().then(
      () => { speakerBlocked.value = false },
      (err) => { if (err?.name === 'NotAllowedError') speakerBlocked.value = true },
    )
  }
}
function enableSpeaker() {
  const els = [remoteAudioEl.value, remoteVideoEl.value].filter(Boolean)
  Promise.all(els.map((el) => el.play())).then(
    () => { speakerBlocked.value = false },
    () => {},
  )
}
watch(
  [() => call.localStream, localVideoEl],
  ([stream, el]) => attach(el, stream),
  { flush: 'post' },
)
watch(
  [() => call.remoteStream, remoteVideoEl, remoteAudioEl],
  ([stream, videoEl, audioEl]) => {
    attach(videoEl, stream)
    attach(audioEl, stream)
  },
  { flush: 'post' },
)

const elapsed = ref(0)
let timer = null
watch(
  () => call.status,
  (status) => {
    clearInterval(timer)
    if (status === 'connected') {
      elapsed.value = 0
      timer = setInterval(() => {
        elapsed.value = call.startedAt ? Math.floor((Date.now() - call.startedAt) / 1000) : 0
      }, 1000)
    }
  },
)
watch(
  () => call.status,
  (st) => { if (st === 'idle') speakerBlocked.value = false },
)
onBeforeUnmount(() => clearInterval(timer))

const durationLabel = computed(() => {
  const m = String(Math.floor(elapsed.value / 60)).padStart(2, '0')
  const s = String(elapsed.value % 60).padStart(2, '0')
  return `${m}:${s}`
})

const visible = computed(() => call.status !== 'idle')
// A call that ends because something went wrong (mic denied, peer dropped,
// busy line...) goes straight back to 'idle', which on its own would hide
// this whole overlay - taking the explanation with it. Keep a small
// error-only card up until it's dismissed or times out.
const showErrorOnly = computed(() => call.status === 'idle' && !!call.error)

let errorTimer = null
watch(
  () => call.error,
  (err) => {
    clearTimeout(errorTimer)
    if (!err) return
    // Long enough to read the "how to allow the microphone" instructions.
    errorTimer = setTimeout(() => call.clearError(), 10000)
  },
)
</script>

<template>
  <div v-if="visible || showErrorOnly" class="call-overlay">
    <div class="call-card" :class="{ 'error-only': showErrorOnly }">
      <div v-if="call.error" class="call-error">{{ call.error }}</div>

      <template v-if="call.status === 'outgoing'">
        <div class="call-avatar">{{ call.peer?.name?.[0] || '?' }}</div>
        <div class="call-name">{{ call.peer?.name }}</div>
        <div class="call-sub">Đang gọi...</div>
        <button class="btn btn-danger btn-round" @click="call.endCall()"><AppIcon name="x" /> Huỷ</button>
      </template>

      <template v-else-if="call.status === 'incoming'">
        <div class="call-avatar">{{ call.peer?.name?.[0] || '?' }}</div>
        <div class="call-name">{{ call.peer?.name }}</div>
        <div class="call-sub">{{ call.video ? 'Cuộc gọi video đến...' : 'Cuộc gọi thoại đến...' }}</div>
        <div class="call-actions">
          <button class="btn btn-danger btn-round" @click="call.rejectCall()"><AppIcon name="x" /> Từ chối</button>
          <button class="btn btn-primary btn-round" @click="call.acceptCall()"><AppIcon name="check" /> Nghe máy</button>
        </div>
      </template>

      <template v-else-if="call.status === 'connecting'">
        <div class="call-avatar">{{ call.peer?.name?.[0] || '?' }}</div>
        <div class="call-name">{{ call.peer?.name }}</div>
        <div class="call-sub">Đang kết nối...</div>
      </template>

      <template v-else-if="call.status === 'connected'">
        <div class="call-name">{{ call.peer?.name }}</div>
        <div class="call-sub">{{ durationLabel }}</div>
        <div v-if="call.health.text" class="call-health" :class="call.health.level">{{ call.health.text }}</div>
        <button v-if="speakerBlocked" class="btn btn-primary btn-sm" @click="enableSpeaker"><AppIcon name="volume-2" /> Bấm để bật loa</button>

        <div class="video-area" :class="{ 'has-video': call.video }">
          <video v-if="call.video" ref="remoteVideoEl" class="remote-video" autoplay playsinline></video>
          <audio v-else ref="remoteAudioEl" autoplay></audio>
          <video v-if="call.video" ref="localVideoEl" class="local-video" autoplay playsinline muted></video>
          <div v-if="!call.video" class="call-avatar big">{{ call.peer?.name?.[0] || '?' }}</div>
        </div>

        <div class="call-actions">
          <button class="btn btn-ghost btn-round" :class="{ active: call.muted }" @click="call.toggleMute()">
            <AppIcon :name="call.muted ? 'mic-off' : 'mic'" />
          </button>
          <button class="btn btn-ghost btn-round" :class="{ active: call.video }" @click="call.toggleVideo()">
            <AppIcon name="video" />
          </button>
          <button class="btn btn-danger btn-round" @click="call.endCall()"><AppIcon name="x" /> Kết thúc</button>
        </div>
      </template>

      <template v-else>
        <button class="btn btn-primary btn-round" @click="call.clearError()">Đóng</button>
      </template>
    </div>
  </div>
</template>

<style scoped>
.call-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 200;
  padding: 16px;
}
.call-card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: var(--radius-lg, 16px);
  padding: 28px 24px;
  width: 100%;
  max-width: 360px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  text-align: center;
}
.call-error {
  color: var(--danger-text);
  font-size: 13px;
  margin-bottom: 4px;
}
.call-card.error-only .call-error {
  font-size: 15px;
  line-height: 1.5;
  margin-bottom: 12px;
}
.call-avatar {
  width: 72px;
  height: 72px;
  border-radius: 50%;
  background: var(--accent-soft);
  color: var(--accent-strong);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 28px;
  font-weight: 700;
}
.call-avatar.big {
  width: 96px;
  height: 96px;
  font-size: 36px;
}
.call-name {
  font-size: 18px;
  font-weight: 700;
  color: var(--text);
}
.call-sub {
  font-size: 13px;
  color: var(--muted);
  margin-bottom: 10px;
}
.call-health {
  font-size: 12px;
  line-height: 1.4;
  padding: 4px 10px;
  border-radius: 999px;
  background: var(--surface-2);
  color: var(--muted);
}
.call-health.ok {
  color: var(--accent-strong);
  background: var(--accent-soft);
}
.call-health.warn {
  color: var(--danger-text);
}
.call-actions {
  display: flex;
  gap: 14px;
  margin-top: 12px;
}
.btn-round {
  width: auto;
  min-width: 44px;
  height: 44px;
  border-radius: 999px;
  padding: 0 18px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 16px;
}
.btn-ghost.active {
  background: var(--accent-soft);
  color: var(--accent-strong);
}
.video-area {
  position: relative;
  width: 100%;
  min-height: 160px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--surface-2);
  border-radius: var(--radius-md);
  overflow: hidden;
}
.video-area.has-video {
  min-height: 220px;
}
.remote-video {
  width: 100%;
  height: 220px;
  object-fit: cover;
  background: #000;
}
.local-video {
  position: absolute;
  bottom: 8px;
  right: 8px;
  width: 80px;
  height: 60px;
  object-fit: cover;
  border-radius: var(--radius-sm);
  border: 2px solid var(--card);
  background: #000;
}
</style>
