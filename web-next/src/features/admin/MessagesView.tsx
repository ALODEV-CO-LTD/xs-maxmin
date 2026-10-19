'use client'
import './MessagesView.css'
import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import { api } from '@/lib/api'
import { navigate } from '@/lib/hooks'
import { loadPackageLabels, packageLabel } from '@/lib/packageLabels'
import { useNotifyStore } from '@/lib/notifyStore'
import AdminChatPane from './AdminChatPane'
import { errMsg } from './common'
import { avatarLetter, awaitingCountOf, filterConversations, shortTime, threadSubtitle, unreadBadge } from './messagesLogic'

interface Conversation {
  userId: string
  userName: string
  username: string
  packageType?: string
  packageExpiresAt?: string
  awaitingReply?: boolean
  lastMessage: string
  lastMessageAt: string
}

// /admin/messages - admin inbox: customers left, selected thread right (?user=<id>). Under 860px one column at a time.
// API: GET /admin/messages -> { conversations }
export default function MessagesView() {
  const selectedId = useSearchParams().get('user') || ''
  const unread = useNotifyStore((s) => s.unread)
  const incomingTick = useNotifyStore((s) => s.incomingTick)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [conversations, setConversations] = useState<Conversation[]>([])
  const [query, setQuery] = useState('')
  const [onlyAwaiting, setOnlyAwaiting] = useState(false)

  const load = useCallback(async (quiet = false) => {
    if (!quiet) setLoading(true)
    setError('')
    try {
      setConversations((await api.get('/admin/messages')).conversations)
    } catch (err) {
      setError(errMsg(err, 'Không thể tải danh sách phản hồi'))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadPackageLabels(true)
    load()
    // Safety net when the push channel is blocked.
    const t = setInterval(() => {
      if (!document.hidden) load(true)
    }, 15000)
    return () => clearInterval(t)
  }, [load])

  // A customer just wrote to Admin: refresh the list.
  useEffect(() => {
    if (incomingTick && useNotifyStore.getState().lastIncoming?.source === 'support') load(true)
  }, [incomingTick, load])

  const selected = conversations.find((c) => c.userId === selectedId) || null
  const filtered = filterConversations(conversations, query, onlyAwaiting)
  const awaiting = awaitingCountOf(conversations)
  const subtitle = threadSubtitle(selected, packageLabel)
  const open = (id: string) => id !== selectedId && navigate(`/admin/messages?user=${encodeURIComponent(id)}`)

  return (
    <div className="adm-inbox">
      <div className="inbox-wrap">
        <div className={`inbox${selectedId ? ' has-selection' : ''}`}>
          <aside className="list-col" aria-label="Danh sách khách hàng">
            <header className="list-head">
              <h1 className="list-title">Phản hồi khách hàng</h1>
              <input value={query} onChange={(e) => setQuery(e.target.value)} type="search" className="search" placeholder="Tìm tên hoặc tên đăng nhập" aria-label="Tìm khách hàng" />
              <div className="tabs" role="tablist">
                <button type="button" role="tab" className={`tab${!onlyAwaiting ? ' on' : ''}`} aria-selected={!onlyAwaiting} onClick={() => setOnlyAwaiting(false)}>
                  Tất cả <span className="count">{conversations.length}</span>
                </button>
                <button type="button" role="tab" className={`tab${onlyAwaiting ? ' on' : ''}`} aria-selected={onlyAwaiting} onClick={() => setOnlyAwaiting(true)}>
                  Chưa trả lời {awaiting > 0 && <span className="count count-warn">{awaiting}</span>}
                </button>
              </div>
            </header>

            <div className="list" role="list">
              {error && <div className="alert alert-error">{error}</div>}
              {loading ? (
                <p className="hint">Đang tải...</p>
              ) : conversations.length === 0 ? (
                <p className="hint">Chưa có ai nhắn tin cho bạn</p>
              ) : (
                filtered.length === 0 && <p className="hint">Không có cuộc trò chuyện phù hợp</p>
              )}
              {filtered.map((c) => {
                const n = unread[`support:${c.userId}`] || 0
                return (
                  <button key={c.userId} type="button" className={`conv${c.userId === selectedId ? ' active' : ''}`} role="listitem" onClick={() => open(c.userId)}>
                    <span className="avatar">{avatarLetter(c.userName)}</span>
                    <span className="conv-body">
                      <span className="conv-top">
                        <strong className="conv-name">{c.userName}</strong>
                        <span className="conv-time">{shortTime(c.lastMessageAt)}</span>
                      </span>
                      <span className="conv-last">
                        <span className="conv-text">{c.lastMessage}</span>
                        {n > 0 ? (
                          <span className="unread-badge" aria-label="Tin chưa đọc">{unreadBadge(n)}</span>
                        ) : (
                          c.awaitingReply && <span className="dot" title="Chưa trả lời" aria-label="Chưa trả lời" />
                        )}
                      </span>
                    </span>
                  </button>
                )
              })}
            </div>
          </aside>

          <section className="chat-col" aria-label="Cuộc trò chuyện">
            {selectedId ? (
              <>
                <header className="chat-head">
                  <button type="button" className="back" aria-label="Quay lại danh sách" onClick={() => navigate('/admin/messages')}>‹</button>
                  <span className="avatar">{avatarLetter(selected?.userName || '')}</span>
                  <div className="who">
                    <strong className="who-name">{selected?.userName || 'Khách hàng'}</strong>
                    {subtitle && <span className="who-sub">{subtitle}</span>}
                  </div>
                </header>
                <AdminChatPane key={selectedId} userId={selectedId} onSent={() => load(true)} />
              </>
            ) : (
              <div className="placeholder">Chọn một khách hàng ở bên trái để xem và trả lời tin nhắn</div>
            )}
          </section>
        </div>
      </div>
    </div>
  )
}
