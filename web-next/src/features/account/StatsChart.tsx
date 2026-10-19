'use client'
import './Stats.css'
import { useState } from 'react'
import { useWidth } from './useWidth'
import { chartLabels, fullValue, longDate, niceMax, shortValue } from './accountLogic'

// One time-series chart (SVG, no library). `points` = [{ date, value }], `kind` = 'bar' | 'line'.
// The viewBox follows the container's pixel width so labels keep their true size. (Port of StatsChart.vue.)
export interface StatsChartProps {
  points: { date: string; value: number }[]
  kind?: 'bar' | 'line'
  color?: string
  label: string
  money?: boolean
  unit?: string // day | week | month | year: how the bucket keys read in the tooltip (week keys are the Monday)
}

export default function StatsChart({ points, kind = 'bar', color = 'var(--primary)', label, money = false, unit = 'day' }: StatsChartProps) {
  const [wrapRef, W] = useWidth<HTMLDivElement>(720, 280)
  const [hover, setHover] = useState(-1)
  const H = Math.round(Math.min(300, Math.max(200, W * 0.26)))
  const PAD = { l: money ? 56 : 36, r: 12, t: 12, b: 28 }
  const plotW = W - PAD.l - PAD.r
  const plotH = H - PAD.t - PAD.b
  const m = niceMax(Math.max(0, ...points.map((d) => d.value)))
  const max = money ? m : Math.max(4, m)
  const step = plotW / Math.max(1, points.length)
  const xAt = (i: number) => PAD.l + step * (i + 0.5)
  const yAt = (v: number) => PAD.t + plotH - (v / max) * plotH
  const barW = Math.max(2, Math.min(28, step * 0.6))
  const total = points.reduce((a, d) => a + d.value, 0)
  const tipLeft = hover < 0 || !points[hover] ? null : `${Math.min(Math.max((xAt(hover) / W) * 100, 14), 86)}%`

  return (
    <div className="card sch">
      <div className="sch-head">
        <span className="sch-label">
          <i className={kind === 'bar' ? 'sch-sw-bar' : 'sch-sw-line'} style={{ background: color }}></i>
          {label}
        </span>
        <strong className="sch-total">{fullValue(total, money)}</strong>
      </div>
      <div ref={wrapRef} className="sch-wrap" onMouseLeave={() => setHover(-1)}>
        <svg viewBox={`0 0 ${W} ${H}`} width={W} height={H} role="img" aria-label={label}>
          {[1, 2, 3, 4, 5].map((t) => {
            const y = PAD.t + (plotH / 4) * (t - 1)
            return (
              <g key={t}>
                <line x1={PAD.l} x2={W - PAD.r} y1={y} y2={y} className="sch-grid" />
                <text x={PAD.l - 8} y={y + 4} className="sch-tick" textAnchor="end">{shortValue((max / 4) * (5 - t), money)}</text>
              </g>
            )
          })}
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
          {chartLabels(points, plotW).map((l) => (
            <text key={'x' + l.i} x={xAt(l.i)} y={H - 8} className="sch-tick" textAnchor="middle">{l.text}</text>
          ))}
          {points.map((d, i) => (
            <rect
              key={'h' + d.date}
              x={PAD.l + step * i}
              y={PAD.t}
              width={step}
              height={plotH}
              fill="transparent"
              onMouseEnter={() => setHover(i)}
              onTouchStart={() => setHover(i)}
            />
          ))}
        </svg>
        {tipLeft && (
          <div className="sch-tip" style={{ left: tipLeft }}>
            <strong>{longDate(points[hover].date, unit)}</strong>
            <div>{label}: {fullValue(points[hover].value, money)}</div>
          </div>
        )}
      </div>
    </div>
  )
}
