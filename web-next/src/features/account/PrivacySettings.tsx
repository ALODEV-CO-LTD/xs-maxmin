'use client'
import './PrivacySettings.css'
import { usePrivacyStore } from '@/lib/privacyStore'
import { HIDE_OPTIONS, IDLE_OPTIONS } from './accountLogic'

// Tài khoản > Cài đặt quyền riêng tư (K34): auto-lock (K09/K40), lock/blur when the page is hidden (K32/S10). Stored in
// this browser only (lib/privacyStore.js). Note K33: a web page cannot block screenshots.
export default function PrivacySettings() {
  const autoLockMinutes = usePrivacyStore((s) => s.autoLockMinutes)
  const hideLockSeconds = usePrivacyStore((s) => s.hideLockSeconds)
  const blurOnHide = usePrivacyStore((s) => s.blurOnHide)
  const blurPolicy = usePrivacyStore((s) => s.blurPolicy)
  const save = usePrivacyStore((s) => s.saveSettings)
  return (
    <div className="card">
      <h3 style={{ marginTop: 0 }}>Cài đặt quyền riêng tư</h3>
      <p className="page-subtitle">Áp dụng cho trình duyệt này.</p>

      <div className="field">
        <label htmlFor="priv-idle">Tự động khoá khi không hoạt động</label>
        <select id="priv-idle" value={autoLockMinutes} onChange={(e) => save({ autoLockMinutes: Number(e.target.value) })}>
          {IDLE_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
      </div>

      <div className="field">
        <label htmlFor="priv-hide">Khoá khi chuyển tab / ẩn trang</label>
        <select id="priv-hide" value={hideLockSeconds} onChange={(e) => save({ hideLockSeconds: Number(e.target.value) })}>
          {HIDE_OPTIONS.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
        </select>
      </div>

      {blurPolicy && (
        <label className="priv-check">
          <input type="checkbox" checked={blurOnHide} onChange={(e) => save({ blurOnHide: e.target.checked })} />
          <span>Làm mờ nội dung khi trang bị ẩn hoặc mất focus</span>
        </label>
      )}

      <p className="priv-note">
        Khi khoá, bạn nhập lại mật khẩu (hoặc mật khẩu lớp hai) để xem dữ liệu; dữ liệu đang nhập được giữ lại. Lưu ý:
        trình duyệt không cho phép chặn hoàn toàn việc chụp màn hình hay xem trước ở màn hình đa nhiệm, nên làm mờ chỉ
        giúp giảm nội dung lộ ra.
      </p>
    </div>
  )
}
