'use client'
import './SupportChat.css'
import { useCallback, useEffect, useRef, useState } from 'react'
import AppButton from './AppButton'
import AppIcon from './AppIcon'
import AttachmentPreview from './AttachmentPreview'
import ChatAttachButtons from './ChatAttachButtons'
import MessageAttachment, { type Att } from './MessageAttachment'
import { api } from '@/lib/api'
import { fileToPayload } from '@/lib/attachments'
import { supportUnreadOf, useNotifyStore } from '@/lib/notifyStore'

// Customer <-> Admin support chat as a small popover under the top-bar button (next to the light/dark switch).
// Replaces the old full "Phản hồi" page for customers; Admin still answers from the admin Messages screen (same thread,
// same API).
//
// API: GET /me/messages -> { messages: [{ id, sender: 'user'|'admin', content, createdAt, attachment? }] }
//      POST /me/messages { content, attachment? }
// Oldest message on top, newest at the bottom (like every chat), composer pinned at the bottom of the popover.
// The red badge on the button is the support unread count; opening the popover marks it read.
// notify.supportOpen lets other code (a message toast, the old /feedback link) open it.
interface Msg { id: string; sender: 'user' | 'admin'; content: string; createdAt: string; attachment?: Att }

export function timeLabel(iso: string) {
  const d = new Date(iso)
  return isNaN(d.getTime()) ? '' : d.toLocaleString('vi-VN', { hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit' })
}

export default function SupportChat() {
  const unread = useNotifyStore(supportUnreadOf)
  const incomingTick = useNotifyStore((s) => s.incomingTick)
  const supportOpen = useNotifyStore((s) => s.supportOpen)
  const [open, setOpen] = useState(false)
  const [messages, setMessages] = useState<Msg[]>([])
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState('')
  const [sendError, setSendError] = useState('')
  const [draft, setDraft] = useState('')
  const [sending, setSending] = useState(false)
  const [attachment, setAttachment] = useState<File | null>(null)

  const root = useRef<HTMLDivElement>(null)
  const input = useRef<HTMLInputElement>(null)
  const bodyEl = useRef<HTMLDivElement>(null)
  const timer = useRef<ReturnType<typeof setInterval> | null>(null)
  const count = useRef(0)
  const wantEnd = useRef(false)

  const scrollToEnd = () => {
    wantEnd.current = true
  }
  useEffect(() => {
    if (wantEnd.current && bodyEl.current) {
      bodyEl.current.scrollTop = bodyEl.current.scrollHeight
      wantEnd.current = false
    }
  })

  const load = useCallback(async (initial = false) => {
    if (initial) setLoading(true)
    try {
      const res = await api.get('/me/messages')
      const grew = res.messages.length !== count.current
      count.current = res.messages.length
      setMessages(res.messages)
      setLoadError('')
      if (initial || grew) scrollToEnd()
    } catch (err) {
      if (initial) setLoadError((err as Error).message || 'Không tải được tin nhắn')
    } finally {
      setLoading(false)
    }
  }, [])

  const stopTimer = () => {
    if (timer.current) clearInterval(timer.current)
    timer.current = null
  }
  const openChat = useCallback(() => {
    setOpen(true)
    useNotifyStore.setState({ supportOpen: false, supportVisible: true })
    useNotifyStore.getState().clear('support')
    load(count.current === 0)
    stopTimer()
    timer.current = setInterval(() => load(), 8000)
    scrollToEnd()
    setTimeout(() => input.current?.focus(), 0)
  }, [load])
  const closeChat = () => {
    setOpen(false)
    useNotifyStore.setState({ supportVisible: false })
    stopTimer()
  }

  async function send(e: React.FormEvent) {
    e.preventDefault()
    const content = draft.trim()
    if ((!content && !attachment) || sending) return
    setSending(true)
    setSendError('')
    try {
      const body: { content: string; attachment?: unknown } = { content }
      if (attachment) body.attachment = await fileToPayload(attachment)
      const msg = await api.post('/me/messages', body)
      count.current += 1
      setMessages((m) => [...m, msg])
      scrollToEnd()
      setDraft('')
      setAttachment(null)
    } catch (err) {
      setSendError((err as Error).message || 'Không gửi được tin nhắn')
    } finally {
      setSending(false)
    }
  }

  // Admin replied (WebSocket push): refresh at once while the popover is open.
  useEffect(() => {
    if (!open || useNotifyStore.getState().lastIncoming?.source !== 'support') return
    load()
    useNotifyStore.getState().clear('support')
  }, [incomingTick]) // eslint-disable-line react-hooks/exhaustive-deps
  // While the popover is open anything new counts as read at once (the 10 s unread refresh must not bring the badge back).
  useEffect(() => {
    if (open && unread > 0) useNotifyStore.getState().clear('support')
  }, [open, unread])
  // Something else (a message toast, the old /feedback link) asks the popover to open.
  useEffect(() => {
    if (supportOpen && !open) openChat()
  }, [supportOpen, open, openChat])

  useEffect(() => {
    const onDocDown = (e: MouseEvent) => {
      if (open && root.current && !root.current.contains(e.target as Node)) closeChat()
    }
    document.addEventListener('mousedown', onDocDown)
    return () => document.removeEventListener('mousedown', onDocDown)
  }, [open])
  useEffect(
    () => () => {
      useNotifyStore.setState({ supportVisible: false })
      stopTimer()
    },
    [],
  )

  return (
    <div ref={root} className="support" onKeyDown={(e) => e.key === 'Escape' && closeChat()}>
      <button
        type="button"
        className={`support-btn${open ? ' active' : ''}`}
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-label="Phản hồi cho Admin"
        title="Phản hồi cho Admin"
        onClick={() => (open ? closeChat() : openChat())}
      >
        <AppIcon name="message-square-more" />
        {unread > 0 && <span className="support-badge" aria-label="Tin nhắn chưa đọc">{unread > 9 ? '9+' : unread}</span>}
      </button>

      {open && (
        <section className="support-pop" role="dialog" aria-label="Phản hồi cho Admin">
          <header className="sp-head">
            <div>
              <strong>Hỗ trợ từ Admin</strong>
              <span>Gửi câu hỏi hoặc báo lỗi, Admin trả lời tại đây.</span>
            </div>
            <button type="button" className="sp-close" aria-label="Đóng" onClick={closeChat}><AppIcon name="x" /></button>
          </header>

          <div ref={bodyEl} className="sp-body">
            {loadError ? (
              <p className="sp-note sp-error">{loadError}</p>
            ) : loading ? (
              <p className="sp-note">Đang tải tin nhắn...</p>
            ) : messages.length === 0 ? (
              <p className="sp-note">Chưa có tin nhắn nào. Hãy gửi tin nhắn đầu tiên cho Admin.</p>
            ) : (
              <ul className="sp-list">
                {messages.map((m) => (
                  <li key={m.id} className={`sp-msg${m.sender === 'user' ? ' mine' : ''}`}>
                    <div className="sp-bubble">
                      {m.sender === 'admin' && <span className="sp-from">Admin</span>}
                      {m.content && <span className="sp-text">{m.content}</span>}
                      {m.attachment && <MessageAttachment att={m.attachment} path={`/me/messages/${m.id}/attachment`} />}
                    </div>
                    <time className="sp-time">{timeLabel(m.createdAt)}</time>
                  </li>
                ))}
              </ul>
            )}
          </div>

          <footer className="sp-foot">
            {sendError && <p className="sp-note sp-error">{sendError}</p>}
            {attachment && <AttachmentPreview file={attachment} onRemove={() => setAttachment(null)} />}
            <form className="sp-form" onSubmit={send}>
              <ChatAttachButtons disabled={sending} onPick={(f) => { setAttachment(f); setSendError('') }} onError={setSendError} />
              <input ref={input} value={draft} onChange={(e) => setDraft(e.target.value)} type="text" placeholder="Nhập tin nhắn..." maxLength={2000} aria-label="Nội dung tin nhắn" />
              <AppButton variant="primary" type="submit" disabled={sending || (!draft.trim() && !attachment)}>Gửi</AppButton>
            </form>
          </footer>
        </section>
      )}
    </div>
  )
}
