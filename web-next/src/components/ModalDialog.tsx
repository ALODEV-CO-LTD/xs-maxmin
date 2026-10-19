'use client'
import './ModalDialog.css'
import { useEffect, useId, useRef } from 'react'
import { createPortal } from 'react-dom'

// Generic centred dialog shell (same look as ConfirmDialog): overlay, title + optional description, scrolling body,
// footer. Esc or a click on the backdrop calls `onClose`; focus goes to the first [data-autofocus] (else first field)
// on open and returns to the opener on close.
export interface ModalDialogProps {
  open?: boolean
  title?: string
  description?: string
  wide?: boolean // about 600px
  xwide?: boolean // very wide (about 960px): big forms such as Cấu hình tính điểm
  closeButton?: boolean // the X in the corner (Esc and a click outside also close)
  back?: boolean // big screens: the same ← back button as Khách hàng > chi tiết, instead of the X
  onClose?: () => void
  footer?: React.ReactNode
  children?: React.ReactNode
}

export default function ModalDialog({ open = false, title = '', description = '', wide, xwide, closeButton = true, back, onClose, footer, children }: ModalDialogProps) {
  const box = useRef<HTMLDivElement>(null)
  const titleId = useId()
  useEffect(() => {
    if (!open) return
    const lastFocus = document.activeElement as HTMLElement | null
    const el = (box.current?.querySelector('[data-autofocus]') || box.current?.querySelector('input:not([type=hidden]), select, textarea, button')) as HTMLElement | null
    el?.focus()
    return () => {
      if (lastFocus && typeof lastFocus.focus === 'function') lastFocus.focus()
    }
  }, [open])
  if (!open || typeof document === 'undefined') return null

  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.preventDefault()
      e.stopPropagation()
      onClose?.()
    }
  }
  return createPortal(
    <div className="md-overlay" onMouseDown={(e) => e.target === e.currentTarget && onClose?.()} onKeyDown={onKey}>
      <div ref={box} className={`md-box${wide ? ' md-wide' : ''}${xwide ? ' md-xwide' : ''}`} role="dialog" aria-modal="true" aria-labelledby={titleId}>
        <div className={`md-head${back ? ' md-head-back' : ''}`}>
          {back && (
            <button type="button" className="md-back" aria-label="Quay lại" title="Quay lại" onClick={onClose}>
              <svg viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                <path d="M19 12H5M12 5l-7 7 7 7" />
              </svg>
            </button>
          )}
          <h2 id={titleId} className="md-title">{title}</h2>
          {closeButton && !back && (
            <button type="button" className="md-close" aria-label="Đóng" title="Đóng" onClick={onClose}>
              <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" aria-hidden="true">
                <path d="M6 6l12 12M18 6L6 18" />
              </svg>
            </button>
          )}
        </div>
        {description && <p className="md-desc">{description}</p>}
        <div className="md-body">{children}</div>
        {footer && <div className="md-actions">{footer}</div>}
      </div>
    </div>,
    document.body,
  )
}
