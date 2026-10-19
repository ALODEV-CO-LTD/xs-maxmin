'use client'
import './Stats.css'
import { useEffect, useMemo, useState } from 'react'
import MaskedValue from '@/components/MaskedValue'
import { api } from '@/lib/api'
import { cachedGet, loadAllEntries } from '@/lib/offline'
import { DEFAULT_RATES } from '@/lib/scoringConfig'
import { loadStations } from '@/lib/lotteryStations'
import { moneyByDate, moneyTotals, pseudoEntries } from '@/lib/statsMoney'
import { buildSeries, compactNumber, rangeTotals } from '@/lib/statsSeries'
import { useMasked } from '@/lib/maskStore'
import { useWidth } from './useWidth'
import { BAR_H, BAR_PAD, STAT_METRICS, STAT_UNITS, barPlot, barTone, deltaOf, fmtNum, signed, statTone, tipLeftPct } from './accountLogic'
import { loadMoney } from './statsLoad'

// Thống kê tab of Tài khoản: roster size, number of plays, money sent / won and profit (same money as Tính điểm).
// One card: metric (Tiền gửi / Tiền trúng / Lợi nhuận) + period (Ngày / Tuần / Tháng / Năm), a summary strip for the
// visible range (vs the previous range), the bar chart and the fixed totals. Aggregation: lib/statsSeries.js.
// API: GET /me/customers, GET /me/entries (all pages, cached offline), GET /me/scoring-settings, GET /lottery-results
type Money = { byDate: Record<string, any>; customers: number; plays: number } // eslint-disable-line @typescript-eslint/no-explicit-any

export default function AccountStats() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [money, setMoney] = useState<Money>({ byDate: {}, customers: 0, plays: 0 })
  const [unit, setUnit] = useState('day')
  const [metric, setMetric] = useState('profit')
  const [hover, setHover] = useState(-1)
  const [still, setStill] = useState(false)
  const masked = useMasked()
  const [wrapRef, W] = useWidth<HTMLDivElement>(640, 240)

  useEffect(() => {
    setStill(!!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches)
    let alive = true
    loadMoney({ api, cachedGet, loadAllEntries, loadStations, DEFAULT_RATES, moneyByDate })
      .then((m) => alive && setMoney(m))
      .catch((err) => alive && setError(err.message || 'Không tải được thống kê'))
      .finally(() => alive && setLoading(false))
    return () => {
      alive = false
    }
  }, [])

  const unitInfo = STAT_UNITS.find((u) => u.key === unit)!
  const metricInfo = STAT_METRICS.find((m) => m.key === metric)!
  const entries = useMemo(() => pseudoEntries(money.byDate, metric), [money, metric])
  const series = useMemo(() => buildSeries(entries, { unit, metric }), [entries, unit, metric])
  const totals = useMemo(() => rangeTotals(entries, { unit, metric }), [entries, unit, metric])
  const { delta, pct } = deltaOf(totals)
  const plot = useMemo(() => barPlot(series, metric, W), [series, metric, W])
  const hovered = plot.bars[hover] || null
  const stats = { customers: money.customers, plays: money.plays, ...moneyTotals(money.byDate) }
  const tone = (n: number) => statTone(metric, n)
  const cls = (t: string) => (t ? 'st-' + t : '')
  const H = BAR_H
  const PAD = BAR_PAD

  if (loading) return <div><div className="card">Đang tải...</div></div>
  if (error) return <div><div className="alert alert-error">{error}</div></div>

  return (
    <div>
      <p className="page-subtitle">Tổng hợp trên toàn bộ số liệu của bạn (tiền quy đổi như tab Tính điểm; ngày chưa có kết quả xổ số chưa tính vào lợi nhuận).</p>

      <section className="card st-card" aria-label="Thống kê">
        <div className="st-controls">
          <div className="st-ctl">
            <span id="seg-m" className="st-ctl-label">Chỉ số</span>
            <div className="st-seg" role="radiogroup" aria-labelledby="seg-m">
              {STAT_METRICS.map((m) => (
                <label key={m.key} className="st-seg-opt">
                  <input type="radio" name="stats-metric" value={m.key} checked={metric === m.key} onChange={() => setMetric(m.key)} />
                  <span>{m.label}</span>
                </label>
              ))}
            </div>
          </div>
          <div className="st-ctl">
            <span id="seg-u" className="st-ctl-label">Kỳ</span>
            <div className="st-seg" role="radiogroup" aria-labelledby="seg-u">
              {STAT_UNITS.map((u) => (
                <label key={u.key} className="st-seg-opt">
                  <input type="radio" name="stats-unit" value={u.key} checked={unit === u.key} onChange={() => setUnit(u.key)} />
                  <span>{u.label}</span>
                </label>
              ))}
            </div>
          </div>
        </div>

        <div className="st-summary" aria-live="polite">
          <div className="st-sum-main">
            <span className="st-sum-label">{metricInfo.label} · {unitInfo.range}</span>
            <strong className={`st-sum-value ${cls(tone(totals.current))}`}>
              <MaskedValue text={(metric === 'profit' ? signed(totals.current) : fmtNum(totals.current)) + ' đ'} />
            </strong>
          </div>
          {delta !== null && (
            <div className="st-sum-prev">
              So với {unitInfo.prev}:{' '}
              <b className={cls(tone(delta))}>
                <MaskedValue text={signed(delta) + ' đ' + (pct !== null ? ` (${pct > 0 ? '+' : ''}${pct}%)` : '')} />
              </b>
            </div>
          )}
        </div>

        {masked ? (
          <p className="st-chart-masked">Biểu đồ đang ẩn. Bấm Hiện số liệu để xem.</p>
        ) : (
          <div ref={wrapRef} className="st-chart-wrap" onMouseLeave={() => setHover(-1)}>
            <svg
              className="st-chart"
              viewBox={`0 0 ${W} ${H}`}
              width={W}
              height={H}
              role="img"
              aria-label={`Biểu đồ cột ${metricInfo.label.toLowerCase()} theo ${unitInfo.label.toLowerCase()}, ${unitInfo.range}`}
            >
              {plot.ticks.map((t) => (
                <g key={t.v}>
                  <line x1={PAD.l} x2={W - PAD.r} y1={t.y} y2={t.y} className="st-grid" />
                  <text x={PAD.l - 6} y={t.y + 4} className="st-axis" textAnchor="end">{compactNumber(t.v)}</text>
                </g>
              ))}
              <line x1={PAD.l} x2={W - PAD.r} y1={plot.zeroY} y2={plot.zeroY} className="st-zero" />
              {plot.bars.map((b, i) => (
                <g key={b.key}>
                  <rect x={b.x} y={b.y} width={b.w} height={b.h} rx={2} className={['st-bar', 'st-bar-' + barTone(metric, b.value), hover >= 0 && hover !== i ? 'st-dim' : '', still ? 'still' : ''].filter(Boolean).join(' ')} />
                  {plot.shown.has(i) && (
                    <text x={Math.min(Math.max(b.cx, PAD.l + 14), W - PAD.r - 14)} y={H - 8} className="st-axis" textAnchor="middle">{b.label}</text>
                  )}
                </g>
              ))}
              {plot.bars.map((b, i) => (
                <rect key={'h' + b.key} x={b.hx} y={PAD.t} width={b.hw} height={H - PAD.t - PAD.b} className="st-hit" onPointerEnter={() => setHover(i)} onPointerDown={() => setHover(i)} />
              ))}
            </svg>
            {hovered && (
              <div className="st-tip" style={{ left: tipLeftPct(hovered.cx, W) }} role="status">
                <strong>{hovered.full}</strong>
                <div>{metricInfo.label}: <b className={cls(tone(hovered.value))}>{fmtNum(hovered.value)}</b></div>
              </div>
            )}
            <table className="st-sr-only">
              <caption>{metricInfo.label} theo {unitInfo.label.toLowerCase()}, {unitInfo.range}</caption>
              <tbody>
                {series.map((p) => (
                  <tr key={p.key}><th scope="row">{p.full}</th><td>{fmtNum(p.value)}</td></tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        <dl className="st-facts">
          <div className="st-fact"><dt>Số lượng khách hàng</dt><dd><MaskedValue text={fmtNum(stats.customers)} /></dd></div>
          <div className="st-fact"><dt>Số lượt chơi</dt><dd><MaskedValue text={fmtNum(stats.plays)} /></dd></div>
          <div className="st-fact"><dt>Tổng tiền khách gửi</dt><dd><MaskedValue text={fmtNum(stats.sent) + ' đ'} /></dd></div>
          <div className="st-fact"><dt>Tổng tiền khách trúng</dt><dd><MaskedValue text={fmtNum(stats.won) + ' đ'} /></dd></div>
          <div className="st-fact st-fact-wide"><dt>Lợi nhuận toàn bộ</dt><dd className={stats.profit >= 0 ? 'st-pos' : 'st-neg'}><MaskedValue text={signed(stats.profit) + ' đ'} /></dd></div>
          {stats.pendingLots > 0 && (
            <div className="st-fact st-fact-wide"><dt>Chưa có kết quả xổ số (chưa tính lợi nhuận)</dt><dd><MaskedValue text={fmtNum(stats.pendingLots) + ' lô · ' + fmtNum(stats.pending) + ' đ'} /></dd></div>
          )}
        </dl>
      </section>
    </div>
  )
}
