'use client'
import './AppDatePicker.css'
import { useEffect, useMemo, useRef, useState } from 'react'
import AppIcon from './AppIcon'

/*
  Themed date picker replacing <input type="date">. Same contract as the native input: `value` is an ISO "YYYY-MM-DD"
  string ('' when empty); onChange(value) fires after the user picks/clears a date. The field shows dd/mm/yyyy, like the
  native one did. `className` / `style` land on the wrapper (set width/height there); other attrs (id, aria-*) go to
  the trigger button.
*/
const WEEKDAYS = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN']
const MONTHS = Array.from({ length: 12 }, (_, i) => `Tháng ${i + 1}`)

const pad = (n: number) => String(n).padStart(2, '0')
const iso = (y: number, m: number, d: number) => `${y}-${pad(m + 1)}-${pad(d)}`
export function parseIso(v: string) {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(v || '')
  return m ? { y: +m[1], m: +m[2] - 1, d: +m[3] } : null
}
const today = () => {
  const t = new Date()
  return { y: t.getFullYear(), m: t.getMonth(), d: t.getDate() }
}

type Props = Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'value' | 'onChange'> & {
  value?: string
  onChange?: (value: string) => void
}

export default function AppDatePicker({ value = '', onChange, disabled = false, className, style, ...attrs }: Props) {
  const p0 = parseIso(value)
  const display = p0 ? `${pad(p0.d)}/${pad(p0.m + 1)}/${p0.y}` : ''

  const [open, setOpen] = useState(false)
  const [view, setView] = useState<'days' | 'months' | 'years'>('days')
  const [viewY, setViewY] = useState(0)
  const [viewM, setViewM] = useState(0)
  const [yearStart, setYearStart] = useState(0)
  const [cursor, setCursor] = useState(iso(2000, 0, 1)) // keyboard-focused day
  const [popStyle, setPopStyle] = useState<React.CSSProperties>({})
  const root = useRef<HTMLDivElement>(null)
  const pop = useRef<HTMLDivElement>(null)

  const cells = useMemo(() => {
    const first = new Date(viewY, viewM, 1)
    const offset = (first.getDay() + 6) % 7
    const out = []
    for (let i = 0; i < 42; i++) {
      const d = new Date(viewY, viewM, 1 - offset + i)
      out.push({ key: iso(d.getFullYear(), d.getMonth(), d.getDate()), day: d.getDate(), outside: d.getMonth() !== viewM })
    }
    return out
  }, [viewY, viewM])
  const years = Array.from({ length: 12 }, (_, i) => yearStart + i)
  const t0 = today()
  const todayKey = iso(t0.y, t0.m, t0.d)
  const title = view === 'days' ? `${MONTHS[viewM]} ${viewY}` : view === 'months' ? String(viewY) : `${years[0]} - ${years[11]}`

  const closePicker = () => setOpen(false)
  const openPicker = () => {
    if (disabled || !root.current) return
    const p = parseIso(value) || today()
    setViewY(p.y)
    setViewM(p.m)
    setYearStart(p.y - (p.y % 12))
    setCursor(iso(p.y, p.m, p.d))
    setView('days')
    // fixed positioning: never clipped by overflow parents, never off-screen
    const r = root.current.getBoundingClientRect()
    const w = Math.min(304, window.innerWidth - 16)
    const left = Math.max(8, Math.min(r.left, window.innerWidth - w - 8))
    const flip = window.innerHeight - r.bottom < 380 && r.top > 380
    setPopStyle(flip ? { left, width: w, bottom: window.innerHeight - r.top + 4 } : { left, width: w, top: r.bottom + 4 })
    setOpen(true)
  }

  useEffect(() => {
    if (!open) return
    const onOutside = (e: MouseEvent) => {
      const t = e.target as Node
      if (root.current && !root.current.contains(t) && !(pop.current && pop.current.contains(t))) closePicker()
    }
    const onScrollAway = (e: Event) => {
      if (pop.current && pop.current.contains(e.target as Node)) return
      closePicker()
    }
    document.addEventListener('mousedown', onOutside)
    window.addEventListener('scroll', onScrollAway, true)
    window.addEventListener('resize', closePicker)
    return () => {
      document.removeEventListener('mousedown', onOutside)
      window.removeEventListener('scroll', onScrollAway, true)
      window.removeEventListener('resize', closePicker)
    }
  }, [open])

  // keep keyboard focus on the cursor day (after opening and after each arrow key)
  useEffect(() => {
    if (open && view === 'days') (pop.current?.querySelector('[data-cursor="true"]') as HTMLElement | null)?.focus()
  }, [open, view, cursor, viewY, viewM])

  const focusTrigger = () => (root.current?.querySelector('.dp-trigger') as HTMLElement | null)?.focus()
  const commit = (v: string) => {
    onChange?.(v)
    closePicker()
    focusTrigger()
  }

  const shiftMonth = (delta: number) => {
    let m = viewM + delta
    let y = viewY
    while (m < 0) { m += 12; y-- }
    while (m > 11) { m -= 12; y++ }
    setViewM(m)
    setViewY(y)
  }
  const prev = () => (view === 'days' ? shiftMonth(-1) : view === 'months' ? setViewY(viewY - 1) : setYearStart(yearStart - 12))
  const next = () => (view === 'days' ? shiftMonth(1) : view === 'months' ? setViewY(viewY + 1) : setYearStart(yearStart + 12))
  const toggleView = () => {
    if (view === 'days') setView('months')
    else if (view === 'months') {
      setYearStart(viewY - (viewY % 12))
      setView('years')
    } else setView('days')
  }

  const moveCursor = (days: number, months = 0) => {
    const p = parseIso(cursor)!
    const d = new Date(p.y, p.m + months, p.d + days)
    setCursor(iso(d.getFullYear(), d.getMonth(), d.getDate()))
    setViewY(d.getFullYear())
    setViewM(d.getMonth())
  }
  const onPopKey = (e: React.KeyboardEvent) => {
    if (e.key === 'Escape') {
      e.preventDefault()
      closePicker()
      focusTrigger()
      return
    }
    if (view !== 'days' || !(e.target as HTMLElement).closest('.dp-day')) return
    const moves: Record<string, () => void> = {
      ArrowLeft: () => moveCursor(-1),
      ArrowRight: () => moveCursor(1),
      ArrowUp: () => moveCursor(-7),
      ArrowDown: () => moveCursor(7),
      PageUp: () => moveCursor(0, -1),
      PageDown: () => moveCursor(0, 1),
    }
    if (moves[e.key]) {
      e.preventDefault()
      moves[e.key]()
    }
  }

  return (
    <div ref={root} className={`app-date${className ? ' ' + className : ''}${open ? ' is-open' : ''}${disabled ? ' is-disabled' : ''}`} style={style}>
      <button
        {...attrs}
        type="button"
        className="dp-trigger"
        aria-haspopup="dialog"
        aria-expanded={open}
        disabled={disabled}
        onClick={() => (open ? closePicker() : openPicker())}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown' && !open) {
            e.preventDefault()
            openPicker()
          }
        }}
      >
        <span className={`dp-value${display ? '' : ' placeholder'}`}>{display || 'dd/mm/yyyy'}</span>
        <AppIcon name="calendar" className="dp-icon" />
      </button>

      {open && (
        <div ref={pop} className="dp-pop" style={popStyle} role="dialog" aria-label="Chọn ngày" onKeyDown={onPopKey}>
          <div className="dp-head">
            <button type="button" className="dp-nav" aria-label="Trước" onClick={prev}><AppIcon name="chevron-left" /></button>
            <button type="button" className="dp-title" onClick={toggleView}>{title}</button>
            <button type="button" className="dp-nav" aria-label="Sau" onClick={next}><AppIcon name="chevron-right" /></button>
          </div>

          {view === 'days' && (
            <div>
              <div className="dp-weekdays">{WEEKDAYS.map((w) => <span key={w}>{w}</span>)}</div>
              <div className="dp-days">
                {cells.map((c) => (
                  <button
                    key={c.key}
                    type="button"
                    className={`dp-day${c.outside ? ' outside' : ''}${c.key === value ? ' selected' : ''}${c.key === todayKey ? ' today' : ''}`}
                    data-cursor={c.key === cursor}
                    tabIndex={c.key === cursor ? 0 : -1}
                    aria-label={c.key}
                    aria-pressed={c.key === value}
                    onClick={() => commit(c.key)}
                  >
                    {c.day}
                  </button>
                ))}
              </div>
            </div>
          )}

          {view === 'months' && (
            <div className="dp-grid">
              {MONTHS.map((name, i) => (
                <button
                  key={name}
                  type="button"
                  className={`dp-cell${p0?.y === viewY && p0?.m === i ? ' selected' : ''}${t0.y === viewY && t0.m === i ? ' today' : ''}`}
                  onClick={() => { setViewM(i); setView('days') }}
                >
                  {name}
                </button>
              ))}
            </div>
          )}

          {view === 'years' && (
            <div className="dp-grid">
              {years.map((y) => (
                <button
                  key={y}
                  type="button"
                  className={`dp-cell${p0?.y === y ? ' selected' : ''}${t0.y === y ? ' today' : ''}`}
                  onClick={() => { setViewY(y); setView('months') }}
                >
                  {y}
                </button>
              ))}
            </div>
          )}

          <div className="dp-foot">
            <button type="button" className="dp-action" onClick={() => commit(todayKey)}>Hôm nay</button>
            <button type="button" className="dp-action" onClick={() => commit('')}>Xoá</button>
          </div>
        </div>
      )}
    </div>
  )
}
