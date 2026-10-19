import './AuthLayout.css'
import Link from 'next/link'
import ThemeToggle from './ThemeToggle'

// Shared full-height hero layout for the public auth pages (/login, /register). Puts a centered card on the themed
// page background, matching the design system in tokens.css.
export default function AuthLayout({
  subtitle = '',
  title = '',
  mode = '',
  showTabs = true,
  children,
}: {
  subtitle?: string
  title?: string
  mode?: 'login' | 'register' | ''
  showTabs?: boolean
  children?: React.ReactNode
}) {
  return (
    <div className="auth-page">
      <div className="auth-theme"><ThemeToggle /></div>
      <main className="auth-card">
        <header className="auth-brand">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img className="auth-logo" src="/img/logo-full.png" alt="MAMBA" width={655} height={400} />
          <h1 className="sr-only">MAMBA</h1>
          {subtitle && <p className="auth-subtitle">{subtitle}</p>}
        </header>
        {showTabs && (
          <nav className="auth-tabs" aria-label="Tài khoản">
            <Link href="/login" className={mode === 'login' ? 'active' : undefined} aria-current={mode === 'login' ? 'page' : undefined}>Đăng nhập</Link>
            <Link href="/register" className={mode === 'register' ? 'active' : undefined} aria-current={mode === 'register' ? 'page' : undefined}>Đăng ký</Link>
          </nav>
        )}
        {title && <h2 className="auth-title">{title}</h2>}
        {children}
      </main>
    </div>
  )
}
