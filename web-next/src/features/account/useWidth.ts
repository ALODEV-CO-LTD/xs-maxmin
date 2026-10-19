'use client'
import { useEffect, useState } from 'react'

// Pixel width of an element (ResizeObserver), so SVG charts keep their label size on a 360px phone. Returns a callback
// ref (the element may mount later than the component) and the width.
export function useWidth<T extends HTMLElement>(initial: number, min: number) {
  const [el, setEl] = useState<T | null>(null)
  const [w, setW] = useState(initial)
  useEffect(() => {
    if (!el || typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(([e]) => setW(Math.max(min, Math.round(e.contentRect.width))))
    ro.observe(el)
    return () => ro.disconnect()
  }, [el, min])
  return [setEl, w] as const
}
