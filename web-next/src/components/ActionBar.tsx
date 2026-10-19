import './ActionBar.css'

/*
  Action-button row of a screen / dialog / form. Every screen uses the SAME layout and order:
      [ destructive button (Xoá...) ]  ··· note ···  [ Huỷ ]  [ Main action ]
  - start     left: secondary / dangerous button (Xoá, Đặt lại mặc định)
  - note      small text in the middle (e.g. "3 mục riêng", "Đã lưu")
  - children  right: Huỷ then the main button, ALWAYS rightmost
  sticky  stick to the bottom of the scroll area / screen (long tables: Lưu, Huỷ never scroll away)
  stack   on narrow screens (<= 520px) stack vertically, main button on top, full width
  align   'end' | 'between' (default) | 'start'
*/
export default function ActionBar({
  sticky = false,
  stack = true,
  align = 'between',
  start,
  note,
  children,
}: {
  sticky?: boolean
  stack?: boolean
  align?: 'end' | 'between' | 'start'
  start?: React.ReactNode
  note?: React.ReactNode
  children?: React.ReactNode
}) {
  return (
    <div className={`action-bar align-${align}${sticky ? ' sticky' : ''}${stack ? ' stack' : ''}`} role="group">
      {start && <div className="ab-start">{start}</div>}
      {note && <div className="ab-note">{note}</div>}
      {children && <div className="ab-end">{children}</div>}
    </div>
  )
}
