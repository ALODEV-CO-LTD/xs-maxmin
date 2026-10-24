'use client'
import './StatsView.css'
import { useCallback, useEffect, useState } from 'react'
import { api } from '@/lib/api'
import { loadPackageLabels, usePackageLabel } from '@/lib/packageLabels'
import StatsChart from './StatsChart'
import { RANGES, seriesPoints } from './chartMath'
import { errMsg } from './common'

interface Stats {
  totalSubscribers: number
  activeSubscribers: number
  expiredSubscribers: number
  byPackage: Record<string, number>
  canRevenue?: boolean
  series?: { date: string; revenue?: number; newUsers: number }[]
}

const CURRENT: Record<string, string> = { day: 'Hôm nay', week: 'Tuần này', month: 'Tháng này', year: 'Năm nay' }
const PREVIOUS: Record<string, string> = { day: 'hôm qua', week: 'tuần trước', month: 'tháng trước', year: 'năm trước' }
const nf = (n: number) => n.toLocaleString('vi-VN')

// The current period (today / this week / ...) against the one before it, like Tổng quan of a customer.
function PeriodFigure({ name, values, unit, money }: { name: string; values: number[]; unit: string; money?: boolean }) {
  const cur = values.length ? values[values.length - 1] : 0
  const prev = values.length > 1 ? values[values.length - 2] : 0
  const fmt = (n: number) => nf(n) + (money ? ' đ' : '')
  const delta = cur - prev
  const pct = prev ? Math.round((delta / prev) * 1000) / 10 : null
  return (
    <div className="period-fig">
      <span className="period-name">{name} · {CURRENT[unit]}</span>
      <strong className="period-value">{fmt(cur)}</strong>
      {cur === 0 && prev === 0 ? null : prev === 0 ? (
        <span className="period-note">Chưa có số liệu {PREVIOUS[unit]}</span>
      ) : (
        <span className={`period-note ${delta > 0 ? 'up' : delta < 0 ? 'down' : ''}`}>
          {delta >= 0 ? '▲ +' : '▼ −'}{fmt(Math.abs(delta))} ({pct! >= 0 ? '+' : '−'}{Math.abs(pct!).toString().replace('.', ',')}%) so với {PREVIOUS[unit]}
        </span>
      )}
    </div>
  )
}

function PackageRow({ code, count }: { code: string; count: number }) {
  const label = usePackageLabel(code)
  return (
    <tr>
      <td>{label}</td>
      <td className="col-num">{count}</td>
    </tr>
  )
}

// /admin/stats - subscriber counts + revenue / new-account charts. API: GET /admin/stats?range=day|week|month|year
export default function StatsView() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [stats, setStats] = useState<Stats | null>(null)
  const [range, setRange] = useState('day')

  const load = useCallback(async (r: string, silent = false) => {
    if (!silent) setLoading(true)
    setError('')
    try {
      setStats(await api.get(`/admin/stats?range=${r}`))
    } catch (err) {
      setError(errMsg(err, 'Không thể tải thống kê'))
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    loadPackageLabels(true)
    load('day')
  }, [load])

  const pick = (r: string) => {
    setRange(r)
    load(r, true)
  }
  const span = RANGES.find((r) => r.key === range)?.span || ''

  return (
    <div className="adm-stats">
      <div className="page">
        <h1 className="page-title">Tổng quan</h1>
        <p className="page-subtitle">Tổng quan số lượng khách hàng theo trạng thái và gói dịch vụ</p>

        {error && <div className="alert alert-error">{error}</div>}
        {loading && <div>Đang tải...</div>}

        {!loading && stats && (
          <>
            <div className="tile-grid">
              <div className="card tile">
                <div className="tile-value">{stats.totalSubscribers}</div>
                <div className="tile-label">Tổng khách hàng</div>
              </div>
              <div className="card tile tile-active">
                <div className="tile-value">{stats.activeSubscribers}</div>
                <div className="tile-label">Đang hoạt động</div>
              </div>
              <div className="card tile tile-expired">
                <div className="tile-value">{stats.expiredSubscribers}</div>
                <div className="tile-label">Đã hết hạn</div>
              </div>
            </div>

            <div className="chart-head">
              <h2 className="section-title chart-title">Thu nhập và người dùng mới</h2>
              <div className="range-tabs" role="tablist" aria-label="Khoảng thời gian">
                {RANGES.map((r) => (
                  <button key={r.key} type="button" role="tab" className={`range-btn${range === r.key ? ' active' : ''}`} aria-selected={range === r.key} onClick={() => pick(r.key)}>
                    {r.label}
                  </button>
                ))}
              </div>
            </div>
            {stats.canRevenue && <PeriodFigure name="Thu nhập" values={(stats.series || []).map((p) => p.revenue || 0)} unit={range} money />}
            <PeriodFigure name="Người dùng mới" values={(stats.series || []).map((p) => p.newUsers || 0)} unit={range} />
            <p className="chart-span">Biểu đồ {span}</p>
            <div className="chart-grid">
              {stats.canRevenue && <StatsChart points={seriesPoints(stats.series, 'revenue')} kind="bar" color="var(--primary)" label="Thu nhập" money unit={range} />}
              <StatsChart points={seriesPoints(stats.series, 'newUsers')} kind="line" color="var(--success)" label="Người dùng mới" unit={range} />
            </div>

            <h2 className="section-title">Theo gói dịch vụ</h2>
            <div className="card table-card">
              <table className="table stats-table">
                <thead>
                  <tr>
                    <th>Gói</th>
                    <th className="col-num">Số lượng</th>
                  </tr>
                </thead>
                <tbody>
                  {Object.entries(stats.byPackage || {}).map(([k, n]) => (
                    <PackageRow key={k} code={k} count={n} />
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
