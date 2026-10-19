'use client'
import './MessageToast.css'
import AppIcon from './AppIcon'
import { useNotifyStore } from '@/lib/notifyStore'

// Pop-up for a new message (friend chat or Phản hồi), mounted once in AppShell. Tapping it opens the conversation.
// Driven by lib/notifyStore.js.
export default function MessageToast() {
  const toasts = useNotifyStore((s) => s.toasts)
  const open = useNotifyStore((s) => s.open)
  return (
    <div className="toast-stack" aria-live="polite">
      {toasts.map((t: { id: string; title: string; body: string; to: string }) => (
        <button key={t.id} type="button" className="msg-toast" onClick={() => open(t)}>
          <span className="toast-icon"><AppIcon name="message-circle-more" /></span>
          <span className="toast-text">
            <strong>{t.title}</strong>
            <span>{t.body}</span>
          </span>
        </button>
      ))}
    </div>
  )
}
