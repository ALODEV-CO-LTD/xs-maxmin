'use client'
import './StatsChart.css'
import { useEffect, useRef, useState } from 'react'
import { axisMax, fullValue, labelIndexes, longDate, shortDate, shortValue } from './chartMath'

export interface ChartPoint {
  date: string
  value: number
}

// One time-series chart (SVG, no library). The viewBox follows the container's pixel width so labels keep their true size.
export default function StatsChart({ points, kind = 'bar', color = 'var(--primary)', label, money = false, unit = 'day' }: {
  points: ChartPoint[]
  kind?: 'bar' | 'line'
  color?: string
  label: string
  money?: boolean
  unit?: string
}) {
  const [W, setW] = useState(720)
  const [hover, setHover] = useState(-1)
  const wrap = useRef<HTMLDivElement>(null)
  useEffect(() => {
    const el = wrap.current
    if (!el || typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(([e]) => setW(Math.max(280, Math.round(e.contentRect.width))))
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const H = Math.round(Math.min(300, Math.max(200, W * 0.26)))
  const PAD = { l: money ? 56 : 36, r: 12, t: 12, b: 28 }
  const plotW = W - PAD.l - PAD.r
  const plotH = H - PAD.t - PAD.b
  const max = axisMax(points.map((d) => d.value), money)
  const step = plotW / Math.max(1, points.length)
  const xAt = (i: number) => PAD.l + step * (i + 0.5)
  const yAt = (v: number) => PAD.t + plotH - (v / max) * plotH
  const barW = Math.max(2, Math.min(28, step * 0.6))
  const total = points.reduce((a, d) => a + d.value, 0)
  const tipLeft = hover < 0 ? null : `${Math.min(Math.max((xAt(hover) / W) * 100, 14), 86)}%`
  const cur = hover >= 0 ? points[hover] : undefined

  return (
    <div className="adm-chart">
      <div className="card sc">
        <div className="sc-head">
          <span className="sc-label">
            <i className={`sw ${kind === 'bar' ? 'sw-bar' : 'sw-line'}`} style={{ background: color }} />
            {label}
          </span>
          <strong className="sc-total">{fullValue(total, money)}</strong>
        </div>
        <div ref={wrap} className="sc-wrap" onMouseLeave={() => setHover(-1)}>
          <svg viewBox={`0 0 ${W} ${H}`} width={W} height={H} role="img" aria-label={label}>
            {[1, 2, 3, 4, 5].map((t) => (
              <g key={t}>
                <line x1={PAD.l} x2={W - PAD.r} y1={PAD.t + (plotH / 4) * (t - 1)} y2={PAD.t + (plotH / 4) * (t - 1)} className="grid" />
                <text x={PAD.l - 8} y={PAD.t + (plotH / 4) * (t - 1) + 4} className="tick" textAnchor="end">
                  {shortValue((max / 4) * (5 - t), money)}
                </text>
              </g>
            ))}
            {kind === 'bar' ? (
              points.map((d, i) => (
                <rect
                  key={'b' + d.date}
                  x={xAt(i) - barW / 2}
                  y={yAt(d.value)}
                  width={barW}
                  height={Math.max(0, PAD.t + plotH - yAt(d.value))}
                  rx={3}
                  fill={color}
                  opacity={hover >= 0 && hover !== i ? 0.4 : 0.85}
                />
              ))
            ) : (
              <>
                <polyline points={points.map((d, i) => `${xAt(i)},${yAt(d.value)}`).join(' ')} fill="none" stroke={color} strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round" />
                {points.map((d, i) => (
                  <circle key={'p' + d.date} cx={xAt(i)} cy={yAt(d.value)} r={hover === i ? 5 : points.length > 40 ? 0 : 3} fill={color} />
                ))}
              </>
            )}
            {labelIndexes(points.length, plotW).map((i) => (
              <text key={'x' + i} x={xAt(i)} y={H - 8} className="tick" textAnchor="middle">
                {shortDate(points[i].date)}
              </text>
            ))}
            {points.map((d, i) => (
              <rect key={'h' + d.date} x={PAD.l + step * i} y={PAD.t} width={step} height={plotH} fill="transparent" onMouseEnter={() => setHover(i)} onTouchStart={() => setHover(i)} />
            ))}
          </svg>
          {tipLeft && cur && (
            <div className="tip" style={{ left: tipLeft }}>
              <strong>{longDate(cur.date, unit)}</strong>
              <div>
                {label}: {fullValue(cur.value, money)}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
