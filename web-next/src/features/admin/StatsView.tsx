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
        <h1 className="page-title">Thống kê</h1>
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
            <p className="chart-span">{span}</p>
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
