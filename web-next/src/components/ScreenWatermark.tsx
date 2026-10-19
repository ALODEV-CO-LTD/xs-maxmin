'use client'
import './ScreenWatermark.css'
import { useEffect, useRef, useState } from 'react'
import { useAuthStore } from '@/lib/authStore'
import { usePolicyStore } from '@/lib/policyStore'
import { watermarkStyle, watermarkTile } from '@/lib/watermark'

// Viewer watermark (A09 / K33). A web page cannot block or detect screenshots, so every screen carries a faint, tiled
// mark with who is looking and when. A leaked screenshot then shows whose account it came from and the minute it was
// taken. It never blocks clicks (pointer-events: none), follows the admin's on/off switch (lib/policyStore.js) and
// puts itself back if the element is removed or restyled from the browser tools. That is a deterrent, not protection:
// only an app can really stop screenshots.
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

