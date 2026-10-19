'use client'
import './ScreenWatermark.css'
import { useEffect, useRef, useState } from 'react'
import { useAuthStore } from '@/lib/authStore'
import { usePolicyStore } from '@/lib/policyStore'

// Viewer watermark (A09 / K33). A web page cannot block or detect screenshots, so every screen carries a faint, tiled
// mark with who is looking and when. A leaked screenshot then shows whose account it came from and the minute it was
// taken. It never blocks clicks (pointer-events: none), follows the admin's on/off switch (lib/policyStore.js) and
// puts itself back if the element is removed or restyled from the browser tools. That is a deterrent, not protection:
// only an app can really stop screenshots.
const pad = (n: number) => String(n).padStart(2, '0')
const esc = (s: string) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c] as string)

// Tile: name · username on one line, minute + id tail on the next, rotated.
export function watermarkTile(u: { name?: string; username?: string; id?: string } | null, d: Date, dark: boolean) {
  if (!u) return ''
  const when = `${pad(d.getHours())}:${pad(d.getMinutes())} ${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`
  const who = `${u.name || ''} · ${u.username || ''}`.slice(0, 40)
  const tail = String(u.id || '').slice(-4)
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="380" height="210">` +
    `<g transform="rotate(-24 190 105)" fill="${dark ? 'rgba(255,255,255,0.15)' : 'rgba(30,41,59,0.20)'}" font-family="system-ui,sans-serif" font-size="15" font-weight="600" text-anchor="middle">` +
    `<text x="190" y="98">${esc(who)}</text><text x="190" y="120" font-size="13" font-weight="500">${esc(when)} · ${esc(tail)}</text></g></svg>`
  return `url("data:image/svg+xml;utf8,${encodeURIComponent(svg)}")`
}

export function watermarkStyle(tile: string) {
  return (
    `position:fixed!important;inset:0!important;z-index:2147483000!important;pointer-events:none!important;display:block!important;` +
    `visibility:visible!important;opacity:1!important;background-image:${tile}!important;background-repeat:repeat!important;`
  )
}

const readDark = (mq: MediaQueryList) => {
  const t = document.documentElement.getAttribute('data-theme')
  return t ? t === 'dark' : mq.matches
}

export default function ScreenWatermark() {
  const user = useAuthStore((s) => s.user)
  const enabled = usePolicyStore((s) => s.watermarkEnabled)
  const shown = enabled && !!user
  const el = useRef<HTMLDivElement>(null)
  const [now, setNow] = useState(() => new Date())
  const [dark, setDark] = useState(false)

  // The mark must stay readable on a white page and on a dark one: dark ink on light themes, light ink on dark ones
  // (follows <html data-theme> and the OS setting).
  useEffect(() => {
    const mq = window.matchMedia('(prefers-color-scheme: dark)')
    const onTheme = () => setDark(readDark(mq))
    onTheme()
    const themeObserver = new MutationObserver(onTheme)
    themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] })
    mq.addEventListener('change', onTheme)
    const tick = setInterval(() => setNow(new Date()), 30000)
    return () => {
      themeObserver.disconnect()
      mq.removeEventListener('change', onTheme)
      clearInterval(tick)
    }
  }, [])

  const style = watermarkStyle(watermarkTile(user, now, dark))

  // The style is written as an attribute (React's style prop cannot carry !important). Removed from the page, or its
  // style tampered with: restore.
  useEffect(() => {
    if (!shown) return
    el.current?.setAttribute('style', style)
    const guard = () => {
      const node = el.current
      if (!node) return
      // React cannot re-render into a node somebody detached, so put the very same element back.
      if (!node.isConnected) document.body.appendChild(node)
      if (node.getAttribute('style') !== style) node.setAttribute('style', style)
    }
    const observer = new MutationObserver(guard)
    observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['style', 'class', 'hidden'] })
    return () => observer.disconnect()
  }, [shown, style])

  if (!shown) return null
  return <div ref={el} className="screen-watermark" aria-hidden="true" />
}

