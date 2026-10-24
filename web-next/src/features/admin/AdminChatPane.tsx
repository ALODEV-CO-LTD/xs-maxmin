'use client'
import './AdminChatPane.css'
import { useCallback, useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AttachmentPreview from '@/components/AttachmentPreview'
import ChatAttachButtons from '@/components/ChatAttachButtons'
import MessageAttachment, { type Att } from '@/components/MessageAttachment'
import { api } from '@/lib/api'
import { fileToPayload } from '@/lib/attachments'
import { showConfirm } from '@/lib/confirm'
import { useNotifyStore } from '@/lib/notifyStore'
import { errMsg } from './common'
import { timeLabel, withDayDividers } from './messagesLogic'

interface Msg {
  id: string
  sender: 'user' | 'admin'
  content: string
  createdAt: string
  attachment?: Att
  deleted?: boolean
}

// One customer's support thread inside the admin inbox. Oldest on top, composer pinned.
// API: GET /admin/messages/:userId, POST /admin/messages/:userId { content, attachment? }
// The parent mounts it with key=userId, so switching customer remounts it.
export default function AdminChatPane({ userId, onSent }: { userId: string; onSent?: () => void }) {
  const incomingTick = useNotifyStore((s) => s.incomingTick)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [messages, setMessages] = useState<Msg[]>([])
  const [draft, setDraft] = useState('')
  const [sending, setSending] = useState(false)
  const [attachment, setAttachment] = useState<File | null>(null)
  const [sendError, setSendError] = useState('')
  const thread = useRef<HTMLDivElement>(null)
  const wantEnd = useRef(false)
  const count = useRef(0)

  useEffect(() => {
    if (wantEnd.current && thread.current) {
      thread.current.scrollTop = thread.current.scrollHeight
      wantEnd.current = false
    }
  })

  const load = useCallback(
    async (quiet = false) => {
      if (!quiet) setLoading(true)
      setError('')
      try {
        const res = await api.get(`/admin/messages/${userId}`)
        const grew = res.messages.length !== count.current
        count.current = res.messages.length
        setMessages(res.messages)
        if (!quiet || grew) wantEnd.current = true
      } catch (err) {
        setError(errMsg(err, 'Không thể tải cuộc trò chuyện'))
      } finally {
        setLoading(false)
      }
    },
    [userId],
  )

  useEffect(() => {
    useNotifyStore.getState().clear(`support:${userId}`)
    load()
    // Safety net when the push channel is blocked: refresh quietly every 8 s while visible.
    const t = setInterval(() => {
      if (!document.hidden) load(true)
    }, 8000)
    return () => clearInterval(t)
  }, [userId, load])

  // A customer just wrote to Admin (pushed over the WebSocket): reload this thread if it is theirs.
  const first = useRef(true)
  useEffect(() => {
    if (first.current) {
      first.current = false
      return
    }
    const m = useNotifyStore.getState().lastIncoming
    if (m?.source === 'support' && m.from === userId) {
      load(true)
      useNotifyStore.getState().clear(`support:${userId}`)
    }
  }, [incomingTick, userId, load])

  async function send(e: React.FormEvent) {
    e.preventDefault()
    const content = draft.trim()
    if (!content && !attachment) return
    setSending(true)
    setSendError('')
    try {
      const body: { content: string; attachment?: unknown } = { content }
      if (attachment) body.attachment = await fileToPayload(attachment)
      const msg = await api.post(`/admin/messages/${userId}`, body)
      count.current += 1
      setMessages((m) => [...m, msg])
      setDraft('')
      setAttachment(null)
      wantEnd.current = true
      onSent?.()
    } catch (err) {
      setSendError(errMsg(err, 'Không thể gửi tin nhắn'))
    } finally {
      setSending(false)
    }
  }

  // Admin may delete only ITS OWN replies: the message stays in the thread (for both sides) as "Tin nhắn đã bị xoá".
  async function removeOne(m: Msg) {
    if (!(await showConfirm({ title: 'Xoá tin nhắn', message: 'Xoá tin nhắn này? Khách hàng sẽ thấy "Tin nhắn đã bị xoá" ở vị trí này và không thể khôi phục nội dung.', confirmText: 'Xoá', danger: true }))) return
    try {
      await api.del(`/admin/messages/${userId}/${m.id}`)
      setMessages((list) => list.map((x) => (x.id === m.id ? { ...x, content: '', attachment: undefined, deleted: true } : x)))
      onSent?.()
    } catch (err) {
      setSendError(errMsg(err, 'Không xoá được tin nhắn'))
    }
  }

  return (
    <div className="adm-pane">
      <div className="pane">
        <div ref={thread} className="thread" role="log" aria-label="Tin nhắn, mới nhất ở dưới">
          {error && <div className="alert alert-error">{error}</div>}
          {loading ? <p className="empty">Đang tải...</p> : messages.length === 0 && <p className="empty">Chưa có tin nhắn nào</p>}
          {withDayDividers(messages).map((m) =>
            'divider' in m ? (
              <div key={m.id} className="day"><span>{m.label}</span></div>
            ) : (
              <div key={m.id} className={`msg ${m.sender === 'admin' ? 'msg-admin' : 'msg-user'}`}>
                <div className="msg-bubble">
                  {m.deleted ? <span className="msg-text"><i>Tin nhắn đã bị xoá</i></span> : m.content && <span className="msg-text">{m.content}</span>}
                  {!m.deleted && m.attachment && <MessageAttachment att={m.attachment} path={`/admin/messages/${userId}/attachment/${m.id}`} />}
                </div>
                <time className="msg-time">{timeLabel(m.createdAt)}</time>
                {m.sender === 'admin' && !m.deleted && <button type="button" className="msg-del" aria-label="Xoá tin nhắn" onClick={() => removeOne(m)}>Xoá</button>}
              </div>
            ),
          )}
        </div>

        <div className="composer">
          {sendError && <p className="alert alert-error">{sendError}</p>}
          {attachment && <AttachmentPreview file={attachment} onRemove={() => setAttachment(null)} />}
          <form className="reply-row" onSubmit={send}>
            <ChatAttachButtons disabled={sending} onPick={(f: File) => { setAttachment(f); setSendError('') }} onError={setSendError} />
            <input value={draft} onChange={(e) => setDraft(e.target.value)} type="text" placeholder="Nhập phản hồi..." disabled={sending} aria-label="Nội dung phản hồi" />
            <AppButton variant="primary" type="submit" disabled={sending || (!draft.trim() && !attachment)}>Gửi</AppButton>
          </form>
        </div>
      </div>
    </div>
  )
}
