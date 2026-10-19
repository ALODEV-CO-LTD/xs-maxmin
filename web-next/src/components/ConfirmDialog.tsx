'use client'
import './ConfirmDialog.css'
import { useEffect, useRef } from 'react'
import { createPortal } from 'react-dom'
import AppButton from './AppButton'
import { resolveConfirm, useConfirmStore } from '@/lib/confirm'

// Centred confirmation box driven by lib/confirm.js. Mounted once in AppShell.
export default function ConfirmDialog() {
  const { open, title, message, confirmText, cancelText, danger } = useConfirmStore()
  const cancelBtn = useRef<HTMLButtonElement>(null)
  const okBtn = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    if (!open) return
    const lastFocus = document.activeElement as HTMLElement | null
    // destructive actions focus "Huỷ" first so a stray Enter can't confirm them
    ;(danger ? cancelBtn : okBtn).current?.focus()
    return () => {
      if (lastFocus && typeof lastFocus.focus === 'function') lastFocus.focus()
    }
  }, [open, danger])
  if (!open || typeof document === 'undefined') return null

  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.preventDefault()
      resolveConfirm(false)
    } else if (e.key === 'Tab') {
      // keep focus inside the dialog
      const items = [cancelBtn.current, okBtn.current].filter(Boolean) as HTMLButtonElement[]
      const i = items.indexOf(document.activeElement as HTMLButtonElement)
      e.preventDefault()
      items[(i + (e.shiftKey ? -1 : 1) + items.length) % items.length]?.focus()
    }
  }
  return createPortal(
    <div className="cd-overlay" onMouseDown={(e) => e.target === e.currentTarget && resolveConfirm(false)} onKeyDown={onKey}>
      <div className="cd-box" role="alertdialog" aria-modal="true" aria-labelledby="cd-title" aria-describedby="cd-message">
        <h2 id="cd-title" className="cd-title">{title}</h2>
        <p id="cd-message" className="cd-message">{message}</p>
        <div className="cd-actions">
          <AppButton ref={cancelBtn} variant="ghost" onClick={() => resolveConfirm(false)}>{cancelText}</AppButton>
          <AppButton ref={okBtn} variant={danger ? 'danger' : 'primary'} onClick={() => resolveConfirm(true)}>{confirmText}</AppButton>
        </div>
      </div>
    </div>,
    document.body,
  )
}

