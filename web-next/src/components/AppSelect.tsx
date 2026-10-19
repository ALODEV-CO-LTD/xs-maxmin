'use client'
import './AppSelect.css'
import { Children, Fragment, isValidElement, useEffect, useMemo, useRef, useState } from 'react'
import AppIcon from './AppIcon'

/*
  Themed dropdown that replaces the native <select>. The native popup is drawn by the OS: it covers the control it
  belongs to and ignores the app's Light/Dark theme. This one opens below (or above, when there is no room), never
  covers its trigger, and uses the theme tokens.

  Drop-in usage - keep the <option> children exactly as for <select>:
    <AppSelect value={x} onChange={setX} id="a" required className="my-class">
      <option value="">-- Chon --</option>
      {list.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
    </AppSelect>
  `className` / `style` land on the wrapper (set `height` there to resize); other attrs (id, aria-*) go to the trigger.
  onChange receives the option's value (not an event).
*/
type OptionDef = { value: unknown; label: string; disabled: boolean; hidden: boolean }

function textOf(node: React.ReactNode): string {
  if (node == null || typeof node === 'boolean') return ''
  if (typeof node === 'string' || typeof node === 'number') return String(node)
  if (Array.isArray(node)) return node.map(textOf).join('')
  if (isValidElement(node)) return textOf((node.props as { children?: React.ReactNode }).children)
  return ''
}
function collect(nodes: React.ReactNode, out: OptionDef[]): OptionDef[] {
  Children.forEach(nodes, (n) => {
    if (!isValidElement(n)) return
    const p = n.props as { children?: React.ReactNode; value?: unknown; disabled?: boolean; hidden?: boolean }
    if (n.type === Fragment) collect(p.children, out)
    else if (n.type === 'option') {
      const label = textOf(p.children).trim()
      out.push({ value: p.value !== undefined ? p.value : label, label, disabled: !!p.disabled, hidden: !!p.hidden })
    }
  })
  return out
}

type Props = Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'value' | 'onChange'> & {
  value?: unknown
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  onChange?: (value: any) => void
  required?: boolean
  children?: React.ReactNode
}

export default function AppSelect({ value = '', onChange, required = false, disabled = false, className, style, children, ...attrs }: Props) {
  const options = useMemo(() => collect(children, []), [children])
  const selected = options.find((o) => o.value === value)
  const label = selected?.label ?? ''
  const isPlaceholder = value === '' || value == null

  const [open, setOpen] = useState(false)
  const [menuStyle, setMenuStyle] = useState<React.CSSProperties>({})
  const [active, setActive] = useState(-1)
  const root = useRef<HTMLDivElement>(null)
  const trigger = useRef<HTMLButtonElement>(null)
  const list = useRef<HTMLUListElement>(null)

  const openMenu = () => {
    if (disabled || !root.current) return
    // fixed positioning so the menu is never clipped by an overflow:auto parent (e.g. tables)
    const r = root.current.getBoundingClientRect()
    const flip = window.innerHeight - r.bottom < 280 && r.top > 280
    setMenuStyle(
      flip
        ? { left: r.left, width: r.width, bottom: window.innerHeight - r.top + 4 }
        : { left: r.left, width: r.width, top: r.bottom + 4 },
    )
    setActive(Math.max(0, options.findIndex((o) => o.value === value)))
    setOpen(true)
  }
  const closeMenu = () => setOpen(false)

  // listeners exist only while the menu is open
  useEffect(() => {
    if (!open) return
    const onOutside = (e: MouseEvent) => {
      const t = e.target as Node
      if (root.current && !root.current.contains(t) && !(list.current && list.current.contains(t))) closeMenu()
    }
    const onScrollAway = (e: Event) => {
      if (list.current && list.current.contains(e.target as Node)) return
      closeMenu()
    }
    document.addEventListener('mousedown', onOutside)
    window.addEventListener('scroll', onScrollAway, true)
    window.addEventListener('resize', closeMenu)
    return () => {
      document.removeEventListener('mousedown', onOutside)
      window.removeEventListener('scroll', onScrollAway, true)
      window.removeEventListener('resize', closeMenu)
    }
  }, [open])

  useEffect(() => {
    if (open) list.current?.querySelector('[data-active="true"]')?.scrollIntoView({ block: 'nearest' })
  }, [open, active])

  const choose = (o: OptionDef) => {
    if (o.disabled) return
    onChange?.(o.value)
    closeMenu()
  }
  const move = (delta: number) => {
    const n = options.length
    if (!n) return
    let i = active
    for (let k = 0; k < n; k++) {
      i = (i + delta + n) % n
      if (!options[i].disabled) break
    }
    setActive(i)
  }
  const onKey = (e: React.KeyboardEvent) => {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      if (!open) openMenu()
      else move(e.key === 'ArrowDown' ? 1 : -1)
    } else if (e.key === 'Enter' || e.key === ' ') {
      if (open) {
        e.preventDefault()
        const o = options[active]
        if (o) choose(o)
      } else if (e.key === ' ') {
        e.preventDefault()
        openMenu()
      }
    } else if (e.key === 'Escape' && open) {
      e.preventDefault()
      closeMenu()
    } else if (e.key === 'Tab' && open) {
      closeMenu()
    }
  }

  return (
    <div ref={root} className={`app-select${className ? ' ' + className : ''}${open ? ' is-open' : ''}${disabled ? ' is-disabled' : ''}`} style={style}>
      <button
        {...attrs}
        ref={trigger}
        type="button"
        className="app-select-trigger"
        role="combobox"
        aria-haspopup="listbox"
        aria-expanded={open}
        aria-controls={undefined}
        disabled={disabled}
        onClick={() => (open ? closeMenu() : openMenu())}
        onKeyDown={onKey}
      >
        <span className={`app-select-label${isPlaceholder ? ' placeholder' : ''}`}>{label}</span>
        <AppIcon name="chevron-down" className="app-select-chevron" />
      </button>
      {/* keeps native `required` validation working on the enclosing form */}
      <input
        className="app-select-native"
        tabIndex={-1}
        aria-hidden="true"
        required={required}
        value={isPlaceholder ? '' : String(value)}
        onChange={() => {}}
        onFocus={() => trigger.current?.focus()}
      />
      {open && (
          <ul ref={list} className="app-select-menu" style={menuStyle} role="listbox">
            {options.map((o, i) =>
              o.hidden ? null : (
                <li
                  key={i}
                  role="option"
                  className={`app-select-option${o.value === value ? ' selected' : ''}${o.disabled ? ' disabled' : ''}`}
                  aria-selected={o.value === value}
                  data-active={i === active}
                  onMouseDown={(e) => {
                    e.preventDefault()
                    choose(o)
                  }}
                  onMouseMove={() => setActive(i)}
                >
                  <span>{o.label}</span>
                  {o.value === value && <AppIcon name="check" className="app-select-check" />}
                </li>
              ),
            )}
          </ul>
      )}
    </div>
  )
}
