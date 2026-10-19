// Ringtone / ringback / notification for voice calls. Everything is
// generated with Web Audio (no audio files to ship) and wrapped in try/catch:
// browsers refuse to make sound before the user has interacted with the
// page, and that must never break a call - it just means a silent ring.

let ctx = null
let timer = null
let titleTimer = null
let originalTitle = ''
let notification = null

function audioCtx() {
  if (!ctx) {
    const Ctor = window.AudioContext || window.webkitAudioContext
    if (!Ctor) return null
    ctx = new Ctor()
  }
  if (ctx.state === 'suspended') ctx.resume().catch(() => {})
  return ctx
}

// One tone: `freqs` played together for `dur` seconds, starting `delay` s from now.
function tone(freqs, dur, delay = 0, volume = 0.12) {
  const c = audioCtx()
  if (!c) return
  const start = c.currentTime + delay
  const gain = c.createGain()
  gain.gain.setValueAtTime(0, start)
  gain.gain.linearRampToValueAtTime(volume, start + 0.02)
  gain.gain.setValueAtTime(volume, start + dur - 0.03)
  gain.gain.linearRampToValueAtTime(0, start + dur)
  gain.connect(c.destination)
  for (const f of freqs) {
    const osc = c.createOscillator()
    osc.type = 'sine'
    osc.frequency.value = f
    osc.connect(gain)
    osc.start(start)
    osc.stop(start + dur + 0.02)
  }
}

function loop(playOnce, everyMs) {
  stopSounds()
  try {
    playOnce()
    timer = setInterval(() => {
      try {
        playOnce()
      } catch {
        /* ignore */
      }
    }, everyMs)
  } catch {
    /* no audio available */
  }
}

// Incoming call: two short double-beeps every 3 s, plus a buzz on phones.
export function startRingtone() {
  loop(() => {
    tone([440, 480], 0.4, 0)
    tone([440, 480], 0.4, 0.6)
    navigator.vibrate?.([400, 200, 400])
  }, 3000)
}

// Outgoing call, while the other phone rings: 1 s tone, 3 s pause.
export function startRingback() {
  loop(() => tone([425], 1, 0, 0.08), 4000)
}

export function stopSounds() {
  if (timer) clearInterval(timer)
  timer = null
  navigator.vibrate?.(0)
}

// Short beep when a call ends so the user notices it is over.
export function playEndTone() {
  try {
    tone([480], 0.15, 0, 0.1)
    tone([380], 0.25, 0.2, 0.1)
  } catch {
    /* ignore */
  }
}

// A desktop notification + flashing tab title while the tab is in the
// background, so an incoming call is not missed.
export function askNotificationPermission() {
  try {
    if ('Notification' in window && Notification.permission === 'default') Notification.requestPermission()
  } catch {
    /* ignore */
  }
}

export function notifyIncoming(name) {
  stopNotify()
  try {
    if (document.hidden && 'Notification' in window && Notification.permission === 'granted') {
      notification = new Notification('Cuộc gọi thoại đến', { body: name, tag: 'xoso-call', requireInteraction: true })
      notification.onclick = () => {
        window.focus()
        stopNotify()
      }
    }
    originalTitle = document.title
    let on = false
    titleTimer = setInterval(() => {
      on = !on
      document.title = on ? `📞 ${name} đang gọi` : originalTitle
    }, 1000)
  } catch {
    /* ignore */
  }
}

export function stopNotify() {
  if (titleTimer) clearInterval(titleTimer)
  titleTimer = null
  if (originalTitle) document.title = originalTitle
  originalTitle = ''
  try {
    notification?.close()
  } catch {
    /* ignore */
  }
  notification = null
}

// ---- New-message alert ----------------------------------------------------
// A short two-note "ping", and a desktop notification when the tab is in the
// background.
export function playMessageTone() {
  try {
    tone([880], 0.12, 0, 0.1)
    tone([1175], 0.18, 0.13, 0.1)
  } catch {
    /* ignore */
  }
}

export function notifyMessage(title, body, onClick) {
  try {
    if (document.hidden && 'Notification' in window && Notification.permission === 'granted') {
      const n = new Notification(title, { body, tag: 'xoso-message' })
      n.onclick = () => {
        window.focus()
        onClick?.()
        n.close()
      }
    }
  } catch {
    /* ignore */
  }
}
