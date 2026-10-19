'use client'
import './CallOverlay.css'
import { useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppIcon from '@/components/AppIcon'
import { notifyIncoming, playEndTone, startRingback, startRingtone, stopNotify, stopSounds } from '@/lib/callSounds'
import { useCallStore } from './callStore'

// Global call UI, mounted once in the app shell so an incoming call can be answered anywhere. A view over the call
// store; all WebRTC / signaling lives there.
export default function CallOverlay() {
  const status = useCallStore((s) => s.status)
  const peer = useCallStore((s) => s.peer)
  const ringing = useCallStore((s) => s.ringing)
  const error = useCallStore((s) => s.error)
  const muted = useCallStore((s) => s.muted)
  const voiceFx = useCallStore((s) => s.voiceFx)
  const voiceFxSupported = useCallStore((s) => s.voiceFxSupported)
  const reconnecting = useCallStore((s) => s.reconnecting)
  const health = useCallStore((s) => s.health)
  const remoteStream = useCallStore((s) => s.remoteStream)
  const startedAt = useCallStore((s) => s.startedAt)
  const call = useCallStore.getState

  const audioEl = useRef<HTMLAudioElement>(null)
  // True when the browser refused to start the remote audio by itself (iOS Safari unless play() runs in a tap): a
  // button turns a silent call into one tap.
  const [speakerBlocked, setSpeakerBlocked] = useState(false)
  const [elapsed, setElapsed] = useState(0)
  const initial = peer?.name?.[0] || '?'

  // The remote stream arrives (ontrack) while the call is still connecting, but <audio> only exists once connected:
  // re-attach whenever either changes.
  useEffect(() => {
    const el = audioEl.current
    if (!el) return
    if (el.srcObject !== (remoteStream || null)) el.srcObject = remoteStream || null
    if (remoteStream && el.play) {
      el.play().then(
        () => setSpeakerBlocked(false),
        (err) => { if (err?.name === 'NotAllowedError') setSpeakerBlocked(true) },
      )
    }
  }, [remoteStream, status])

  useEffect(() => {
    if (status !== 'connected') return
    // eslint-disable-next-line react-hooks/set-state-in-effect -- the timer restarts with every connected call
    setElapsed(0)
    const t = setInterval(() => setElapsed(startedAt ? Math.floor((Date.now() - startedAt) / 1000) : 0), 1000)
    return () => clearInterval(t)
  }, [status, startedAt])
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- the blocked-speaker hint belongs to one call
    if (status === 'idle') setSpeakerBlocked(false)
  }, [status])

  // Sounds: ring while incoming, ringback for the caller once the other phone rings, a short tone when a call ends.
  const prevStatus = useRef('idle')
  useEffect(() => {
    const prev = prevStatus.current
    prevStatus.current = status
    stopSounds()
    if (status !== 'incoming') stopNotify()
    if (status === 'incoming') {
      startRingtone()
      notifyIncoming(peer?.name || 'Người dùng')
    } else if (status === 'outgoing' && ringing) startRingback()
    else if (status === 'idle' && prev !== 'idle') playEndTone()
  }, [status, ringing, peer?.name])
  useEffect(() => () => { stopSounds(); stopNotify() }, [])

  // A call that ends on an error goes straight to 'idle' and would hide the overlay with the explanation: keep an
  // error-only card until it is dismissed or times out (long enough to read how to allow the microphone).
  useEffect(() => {
    if (!error) return
    const t = setTimeout(() => call().clearError(), 10000)
    return () => clearTimeout(t)
  }, [error, call])

  const showErrorOnly = status === 'idle' && !!error
  if (status === 'idle' && !showErrorOnly) return null
  const mm = String(Math.floor(elapsed / 60)).padStart(2, '0')
  const ss = String(elapsed % 60).padStart(2, '0')

  return (
    <div className="call-overlay">
      <div className={`call-card${showErrorOnly ? ' error-only' : ''}`}>
        {error && <div className="call-error">{error}</div>}

        {status === 'outgoing' && (
          <>
            <div className="call-avatar">{initial}</div>
            <div className="call-name">{peer?.name}</div>
            <div className="call-sub">{ringing ? 'Đang đổ chuông...' : 'Đang gọi...'}</div>
            <button className="btn btn-danger btn-round" onClick={() => call().endCall()}><AppIcon name="x" /> Huỷ</button>
          </>
        )}

        {status === 'incoming' && (
          <>
            <div className="call-avatar">{initial}</div>
            <div className="call-name">{peer?.name}</div>
            <div className="call-sub">Cuộc gọi thoại đến...</div>
            <div className="call-actions">
              <button className="btn btn-danger btn-round" onClick={() => call().rejectCall()}><AppIcon name="x" /> Từ chối</button>
              <button className="btn btn-primary btn-round" onClick={() => call().acceptCall()}><AppIcon name="check" /> Nghe máy</button>
            </div>
          </>
        )}

        {status === 'connecting' && (
          <>
            <div className="call-avatar">{initial}</div>
            <div className="call-name">{peer?.name}</div>
            <div className="call-sub">Đang kết nối...</div>
          </>
        )}

        {status === 'connected' && (
          <>
            <div className="call-name">{peer?.name}</div>
            <div className="call-sub">{mm}:{ss}</div>
            {reconnecting && <div className="call-health warn">Mất kết nối mạng, đang kết nối lại…</div>}
            {health.text && <div className={`call-health ${health.level}`}>{health.text}</div>}
            {speakerBlocked && (
              <AppButton variant="primary" size="sm" icon="volume-2" onClick={() => audioEl.current?.play().then(() => setSpeakerBlocked(false), () => {})}>
                Bấm để bật loa
              </AppButton>
            )}
            <div className="video-area">
              <audio ref={audioEl} autoPlay></audio>
              <div className="call-avatar big">{initial}</div>
            </div>
            <div className="call-actions">
              <button className={`btn btn-ghost btn-round${muted ? ' active' : ''}`} onClick={() => call().toggleMute()}>
                <AppIcon name={muted ? 'mic-off' : 'mic'} />
              </button>
              {voiceFxSupported && (
                <button
                  className={`btn btn-ghost${voiceFx ? ' active' : ''}`}
                  aria-pressed={voiceFx}
                  title="Làm méo giọng nói của bạn để người kia nghe không đúng giọng thật"
                  onClick={() => call().toggleVoiceFx()}
                >
                  Méo giọng: {voiceFx ? 'Bật' : 'Tắt'}
                </button>
              )}
              <button className="btn btn-danger btn-round" onClick={() => call().endCall()}><AppIcon name="x" /> Kết thúc</button>
            </div>
          </>
        )}

        {status === 'idle' && <button className="btn btn-primary btn-round" onClick={() => call().clearError()}>Đóng</button>}
      </div>
    </div>
  )
}
