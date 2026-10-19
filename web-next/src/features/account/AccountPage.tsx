'use client'
import './Account.css'
import { useEffect, useRef, useState } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { useAuthStore } from '@/lib/authStore'
import { showConfirm } from '@/lib/confirm'
import { teardownSession } from '@/lib/session'
import AccountStats from './AccountStats'
import DataTab from './DataTab'
import DevicesTab from './DevicesTab'
import PackagesPanel from './PackagesPanel'
import ProfileTab from './ProfileTab'
import { initialTab, nextTabKey, tabsFor } from './accountLogic'

// /account - Tài khoản: tabs Thống kê, Hồ sơ, Thiết bị & riêng tư, Gói & Thanh toán, Dữ liệu (?tab=<key>; the old
// ?tab=security opens Hồ sơ). Admins get no Thống kê / Gói & Thanh toán tab. The Hồ sơ / Thiết bị / Dữ liệu panels stay
// mounted when hidden (v-show in the Vue version); Gói & Thống kê reload every time they open.
// API: GET /me (see the tabs for the rest)
export default function AccountPage() {
  const router = useRouter()
  const search = useSearchParams()
  const isAdmin = useAuthStore((s) => s.role === 'admin')
  const fetchMe = useAuthStore((s) => s.fetchMe)
  const tabs = tabsFor(isAdmin)
  const [tab, setTab] = useState(() => initialTab(tabs, search.get('tab')))
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState('')
  const started = useRef(false)

  // The tab bar scrolls sideways on phones: keep the open tab in view (e.g. after a link to ?tab=packages).
  const showActive = () => document.getElementById(`acct-tab-${tab}`)?.scrollIntoView({ inline: 'center', block: 'nearest' })
  useEffect(() => {
    const t = setTimeout(showActive, 0)
    return () => clearTimeout(t)
  }, [tab, loading]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    const t = setTimeout(showActive, 600) // after the profile finished loading and the tabs rendered
    return () => clearTimeout(t)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  // a link to ?tab=... while this page is already open
  const queryTab = search.get('tab')
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (queryTab && tabs.some((t) => t.key === queryTab)) setTab(queryTab)
  }, [queryTab]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (started.current) return
    started.current = true
    fetchMe()
      .catch((err: Error) => setLoadError(err.message || 'Không tải được thông tin tài khoản'))
      .finally(() => setLoading(false))
  }, [fetchMe])

  function selectTab(key: string) {
    setTab(key)
    const q = new URLSearchParams(search.toString())
    q.set('tab', key)
    router.replace(`/account?${q.toString()}`, { scroll: false })
  }
  function onTabKey(e: React.KeyboardEvent) {
    const key = nextTabKey(tabs, tab, e.key)
    if (key === null) return
    e.preventDefault()
    selectTab(key)
    document.getElementById(`acct-tab-${key}`)?.focus()
  }

  // Logout lives here on phones/tablets (the header button is hidden below 860px).
  async function logoutNow() {
    if (!(await showConfirm({ title: 'Đăng xuất', message: 'Bạn có chắc muốn đăng xuất?', confirmText: 'Đăng xuất' }))) return
    teardownSession() // ends the call / chat too
    useAuthStore.getState().logout()
    router.push('/login')
  }

  const panel = (key: string) => ({ id: `acct-panel-${key}`, role: 'tabpanel', 'aria-labelledby': `acct-tab-${key}`, className: 'acct-panel', hidden: tab !== key })

  return (
    <div className="page acct-page">
      <h1 className="page-title">Tài khoản</h1>
      <p className="page-subtitle">Thông tin cá nhân và bảo mật.</p>

      {loading ? (
        <div className="card">Đang tải...</div>
      ) : loadError ? (
        <div className="alert alert-error">{loadError}</div>
      ) : (
        <>
          <div className="acct-tabs" role="tablist" aria-label="Mục tài khoản" onKeyDown={onTabKey}>
            {tabs.map((t) => (
              <button
                key={t.key}
                id={`acct-tab-${t.key}`}
                type="button"
                role="tab"
                className={`acct-tab${tab === t.key ? ' active' : ''}`}
                aria-selected={tab === t.key}
                aria-controls={`acct-panel-${t.key}`}
                tabIndex={tab === t.key ? 0 : -1}
                onClick={() => selectTab(t.key)}
              >
                {t.label}
              </button>
            ))}
          </div>

          <div {...panel('profile')}><ProfileTab onLogout={logoutNow} /></div>
          <div {...panel('devices')}><DevicesTab /></div>
          {tab === 'packages' && <div {...panel('packages')} className=""><PackagesPanel /></div>}
          {tab === 'stats' && <div {...panel('stats')} className=""><AccountStats /></div>}
          <div {...panel('data')}><DataTab /></div>
        </>
      )}
    </div>
  )
}
