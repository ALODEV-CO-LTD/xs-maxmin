// Voice distortion for calls ("làm méo tiếng"). The microphone stream is run
// through a small Web Audio graph and the PROCESSED track is what the call sends,
// so the other side only ever hears the distorted voice. Because the call always
// sends the processed track, the effect can be switched on and off in the middle
// of a call without renegotiating anything.
//
//   mic -> dry gain ---------------------------------------> out
//      \-> ring modulator (x sine) -> band-pass -> clip -> wet gain -> out
//
// The ring modulator shifts every frequency up and down by RING_HZ (a robotic,
// metallic voice that keeps the words understandable but not the speaker's
// natural timbre); band-pass + soft clipping add the "radio" roughness.
const RING_HZ = 70
const BAND = { low: 250, high: 3400 }
const RAMP_S = 0.05 // click-free crossfade when toggling

function clipCurve(amount = 12) {
  const n = 1024
  const curve = new Float32Array(n)
  for (let i = 0; i < n; i++) {
    const x = (i * 2) / n - 1
    curve[i] = Math.tanh(x * amount) / Math.tanh(amount)
  }
  return curve
}

// Returns { stream, setEnabled(on), stop() }. If Web Audio is unavailable the
// original stream is returned and the effect is simply not offered (`supported:false`).
export function createVoiceChanger(micStream, enabled = false) {
  const Ctx = globalThis.AudioContext || globalThis.webkitAudioContext
  if (!Ctx || !micStream.getAudioTracks().length) {
    return { stream: micStream, supported: false, setEnabled() {}, stop() {} }
  }
  try {
    const ctx = new Ctx()
    const source = ctx.createMediaStreamSource(micStream)
    const out = ctx.createMediaStreamDestination()

    const dry = ctx.createGain()
    const wet = ctx.createGain()

    const ring = ctx.createGain()
    ring.gain.value = 0 // the oscillator drives the gain: output = input x sine
    const osc = ctx.createOscillator()
    osc.frequency.value = RING_HZ
    osc.connect(ring.gain)
    osc.start()

    const hp = ctx.createBiquadFilter()
    hp.type = 'highpass'
    hp.frequency.value = BAND.low
    const lp = ctx.createBiquadFilter()
    lp.type = 'lowpass'
    lp.frequency.value = BAND.high
    const shaper = ctx.createWaveShaper()
    shaper.curve = clipCurve()
    const makeup = ctx.createGain()
    makeup.gain.value = 0.9

    source.connect(dry).connect(out)
    source.connect(ring).connect(hp).connect(lp).connect(shaper).connect(makeup).connect(wet).connect(out)

    const apply = (on) => {
      const t = ctx.currentTime
      dry.gain.cancelScheduledValues(t)
      wet.gain.cancelScheduledValues(t)
      dry.gain.linearRampToValueAtTime(on ? 0 : 1, t + RAMP_S)
      wet.gain.linearRampToValueAtTime(on ? 1 : 0, t + RAMP_S)
    }
    dry.gain.value = enabled ? 0 : 1
    wet.gain.value = enabled ? 1 : 0
    ctx.resume?.().catch(() => {})

    return {
      stream: out.stream,
      supported: true,
      setEnabled(on) {
        ctx.resume?.().catch(() => {})
        apply(on)
      },
      stop() {
        try {
          osc.stop()
        } catch {
          /* already stopped */
        }
        out.stream.getTracks().forEach((t) => t.stop())
        ctx.close?.().catch(() => {})
      },
    }
  } catch {
    return { stream: micStream, supported: false, setEnabled() {}, stop() {} }
  }
}

const KEY = 'xs_voice_fx'
export const loadVoiceFx = () => {
  try {
    return localStorage.getItem(KEY) === '1'
  } catch {
    return false
  }
}
export const saveVoiceFx = (on) => {
  try {
    localStorage.setItem(KEY, on ? '1' : '0')
  } catch {
    /* not remembered */
  }
}
