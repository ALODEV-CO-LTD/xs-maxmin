'use client'
import ScoringConfigEditor from './ScoringConfigEditor'

// Cấu hình tính điểm mặc định (cả tài khoản). Trang riêng (menu "Cấu hình tính điểm"); `embedded` = cùng bảng đó trong hộp
// thoại mở từ Khách hàng. Bảng nằm ở ScoringConfigEditor.
export default function ScoringSettings({ embedded = false, onSaved }: { embedded?: boolean; onSaved?: () => void }) {
  return (
    <div className={embedded ? 'settings-embedded' : 'page'}>
      {!embedded && <h1 className="page-title">Cấu hình tính điểm</h1>}
      <ScoringConfigEditor scope="default" onSaved={() => onSaved?.()} />
    </div>
  )
}
