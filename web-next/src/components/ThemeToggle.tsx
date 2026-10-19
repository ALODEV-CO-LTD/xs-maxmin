'use client'
import './ThemeToggle.css'
import AppIcon from './AppIcon'
import { toggleTheme, useThemeStore } from '@/lib/theme'

// Sun/Moon switch between Light and Dark. State lives in lib/theme.js.
export default function ThemeToggle() {
  const isDark = useThemeStore((s) => s.theme === 'dark')
  const label = isDark ? 'Chuyển sang giao diện sáng' : 'Chuyển sang giao diện tối'
  return (
    <button type="button" className="theme-toggle" aria-label={label} title={label} onClick={toggleTheme}>
      <AppIcon name={isDark ? 'sun' : 'moon'} />
    </button>
  )
}
