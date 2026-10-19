'use client'
// Nhập số (port of views/EntriesView.vue, new version: only "Điểm vào" is typed, the day is always today).
import './entries.css'
import Link from 'next/link'
import { useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppSelect from '@/components/AppSelect'
import AppIcon from '@/components/AppIcon'
import ModalDialog from '@/components/ModalDialog'
import MaskedValue from '@/components/MaskedValue'
import { betTypeLabel } from '@/lib/betTypes'
import { isRegionCode, regionOf, stationLabel, stationName, stationOptions } from '@/lib/lotteryStations'
import { useEntries } from './useEntries'
import QuickEntryBox from './QuickEntryBox'
import { entryCount, emptyListText, fmtPoints, formatNumber, totalsOf, viDate } from './logic'

/* eslint-disable @typescript-eslint/no-explicit-any */
const stationShort = (code: string) => (isRegionCode(code) ? regionOf(code).name : stationName(code))

export default function EntriesScreen() {
  const c: any = useEntries()
  const [rowErrors, setRowErrors] = useState<Record<string, string>>({})
  const [deletingId, setDeletingId] = useState<string | null>(null)
  const [deletingAll, setDeletingAll] = useState(false)
  const [deleteAllError, setDeleteAllError] = useState('')
  const [editing, setEditing] = useState<any>(null)
  const firstNumber = useRef<HTMLInputElement>(null)
  const totals = totalsOf(c.ofCustomer)

  // picking a customer puts the cursor in the first "Số" box (preventScroll keeps the page still on phones)
  useEffect(() => {
    if (c.customerName) firstNumber.current?.focus({ preventScroll: true })
  }, [c.customerName])

  const noPackage = c.user && c.user.package?.isActive === false

  return (
    <div className="page en-page">
      <h1 className="page-title">Nhập số</h1>
      {noPackage && <div className="alert alert-warning">Gói của bạn đã hết hạn. Vui lòng gia hạn ở mục Gói dịch vụ để tiếp tục nhập số liệu.</div>}
      {c.fromCache && <div className="alert alert-warning">Đang offline: hiển thị số liệu đã lưu trên máy. Số liệu bạn nhập sẽ được gửi lên khi có mạng.</div>}
      {c.notice && (
        <div className="alert alert-success en-notice">
          <span>{c.notice}</span>
          <AppButton variant="ghost" size="sm" onClick={() => c.setNotice('')}>Đóng</AppButton>
        </div>
      )}

      <div className="en-layout">
        <aside className="en-rail" aria-label="Khách hàng">
          <div className="en-rail-title">Khách hàng</div>
          {c.customers.length === 0 ? (
            <p className="en-rail-empty">Chưa có khách hàng nào.</p>
          ) : (
            <>
              <AppSelect className="en-rail-select" value={c.customerName} onChange={c.setCustomerName} aria-label="Khách hàng">
                <option value="">-- Chọn khách hàng --</option>
                {c.customers.map((x: any) => <option key={x.id} value={x.name}>{x.name} ({entryCount(c.entries, x.name)})</option>)}
              </AppSelect>
              <ul className="en-rail-list">
                {c.customers.map((x: any) => (
                  <li key={x.id}>
                    <button type="button" className={`en-rail-item${x.name === c.customerName ? ' active' : ''}`} aria-pressed={x.name === c.customerName} onClick={() => c.setCustomerName(x.name)}>
                      <span className="en-rail-name">{x.name}</span>
                      <span className="en-rail-count"><MaskedValue text={entryCount(c.entries, x.name)} /></span>
                    </button>
                  </li>
                ))}
              </ul>
            </>
          )}
          <Link href="/customers?from=entries" className="en-rail-add">+ Thêm khách hàng mới</Link>
        </aside>

        <div className="en-main">
          {c.customerName && (
            <form
              className="card en-form"
              onSubmit={(e) => {
                e.preventDefault()
                c.submit()
              }}
            >
              <h3>Thêm số liệu mới</h3>
              {c.formError && <div className="alert alert-error">{c.formError}</div>}

              <div className="en-top">
                <div className="field">
                  <label htmlFor="en-station">Đài</label>
                  <AppSelect id="en-station" value={c.station} onChange={c.setStation} aria-label="Đài xổ số">
                    {stationOptions(c.date).map((o: any) => <option key={o.value} value={o.value}>{o.label}</option>)}
                  </AppSelect>
                </div>
                <div className="field">
                  <label>Ngày</label>
                  {/* always the day the numbers are entered; it cannot be changed */}
                  <div className="en-date">{viDate(c.date)}</div>
                </div>
              </div>

              <QuickEntryBox c={c} />

              <div className="en-rows">
                <div className="en-head"><span>Hạng mục</span><span>Số</span><span>Điểm vào</span><span /></div>
                <div className="en-row-list">
                  {c.rows.map((row: any, i: number) => (
                    <div key={row.uid} className="en-row">
                      <AppSelect value={row.type} onChange={(v: string) => c.patchRow(row.uid, { type: v })} aria-label={`Hạng mục dòng ${i + 1}`}>
                        {(c.betTypes.includes(row.type) ? c.betTypes : [...c.betTypes, row.type]).map((t: string) => <option key={t} value={t}>{betTypeLabel(t)}</option>)}
                      </AppSelect>
                      <input ref={i === 0 ? firstNumber : undefined} type="text" className="en-input en-number" placeholder="Số, vd: 12" aria-label={`Số dòng ${i + 1}`} value={row.value} onChange={(e) => c.patchRow(row.uid, { value: e.target.value })} />
                      <input type="text" inputMode="decimal" className="en-input" placeholder="Điểm vào" aria-label={`Điểm vào dòng ${i + 1}`} value={row.score} onChange={(e) => c.patchRow(row.uid, { score: e.target.value })} />
                      <button type="button" className="btn btn-ghost btn-sm en-remove" aria-label="Xoá dòng" disabled={c.rows.length === 1 && !row.value && !row.score} onClick={() => c.removeRow(row.uid)}>
                        <AppIcon name="x" />
                      </button>
                    </div>
                  ))}
                </div>
                <button type="button" className="btn btn-ghost btn-sm en-add" onClick={c.addRow}>+ Thêm số</button>
              </div>

              <div className="field">
                <label htmlFor="en-note">Ghi chú</label>
                <textarea id="en-note" rows={2} placeholder="Tuỳ chọn" value={c.note} onChange={(e) => c.setNote(e.target.value)} />
              </div>

              {deleteAllError && <div className="alert alert-error">{deleteAllError}</div>}
              {c.addedMsg && <div className="alert alert-success" role="status">{c.addedMsg}</div>}
              <div className="en-form-actions">
                <AppButton variant="primary" type="submit" disabled={c.submitting || !c.canAdd}>{c.submitting ? 'Đang thêm...' : 'Thêm số liệu'}</AppButton>
                <AppButton
                  variant="danger"
                  disabled={deletingAll || c.ofCustomer.length === 0}
                  onClick={async () => {
                    setDeletingAll(true)
                    setDeleteAllError(await c.deleteAll())
                    setDeletingAll(false)
                  }}
                >{deletingAll ? 'Đang xoá...' : 'Xoá tất cả số liệu'}</AppButton>
              </div>
            </form>
          )}

          <section className="card en-list-card">
            <h3 className="en-list-title">Danh sách số liệu{c.customerName ? `: ${c.customerName}` : ''}</h3>
            {c.loading ? (
              <div className="en-empty">Đang tải...</div>
            ) : c.loadError ? (
              <div className="alert alert-error">{c.loadError}</div>
            ) : !c.customerName ? (
              <div className="en-empty">Chọn khách hàng để xem và nhập số liệu.</div>
            ) : c.shown.length === 0 ? (
              <div className="en-empty">{emptyListText({ customerName: c.customerName, entries: c.entries, date: c.date })}</div>
            ) : (
              <div className="en-table-wrap">
                <table className="table en-table">
                  <thead>
                    <tr><th>Ngày</th><th>Hạng mục</th><th>Số</th><th>Điểm vào</th><th>Điểm ra</th><th>Ghi chú</th><th>Sửa</th><th>Xoá</th></tr>
                  </thead>
                  <tbody>
                    {c.shown.map((e: any) => (
                      <EntryRow
                        key={e.id}
                        e={e}
                        error={rowErrors[e.id]}
                        deleting={deletingId === e.id}
                        onEdit={() => setEditing(e)}
                        onDelete={async () => {
                          setDeletingId(e.id)
                          const err = await c.deleteEntry(e)
                          setRowErrors((m) => ({ ...m, [e.id]: err }))
                          setDeletingId(null)
                        }}
                      />
                    ))}
                  </tbody>
                </table>
              </div>
            )}
            {!c.loading && !c.loadError && c.customerName && (
              <div className="en-stats">
                <h3>Thống kê: {c.customerName}</h3>
                <p className="en-hint">Tính trên <MaskedValue text={c.ofCustomer.length} /> số liệu của khách hàng đang chọn (điểm vào/ra để trống được tính là 0).</p>
                <div className="en-calc-grid">
                  <div className="card en-calc"><div className="en-calc-label">Tổng điểm vào</div><div className="en-calc-value en-in"><MaskedValue text={formatNumber(totals.vao)} /></div></div>
                  <div className="card en-calc"><div className="en-calc-label">Tổng điểm ra</div><div className="en-calc-value en-out"><MaskedValue text={formatNumber(totals.ra)} /></div></div>
                  <div className="card en-calc"><div className="en-calc-label">Chênh lệch (vào − ra)</div><div className={`en-calc-value ${totals.chenhLech >= 0 ? 'en-in' : 'en-out'}`}><MaskedValue text={formatNumber(totals.chenhLech)} /></div></div>
                </div>
              </div>
            )}
          </section>
        </div>
      </div>

      {editing && <EditDialog entry={editing} onClose={() => setEditing(null)} onSave={(f: any) => c.saveEdit(editing, f)} />}
    </div>
  )
}

function EntryRow({ e, error, deleting, onEdit, onDelete }: any) {
  return (
    <>
      <tr>
        <td>{viDate(e.entryDate)}{e.pending && <span className="chip en-pending">Chờ đồng bộ</span>}</td>
        <td>
          {betTypeLabel(e.betType || 'de')}
          {e.station && e.station !== 'mb' && <span className="chip en-station" title={stationLabel(e.station)}>{stationShort(e.station)}</span>}
        </td>
        <td className="en-cell-num"><MaskedValue text={e.value} /></td>
        <td className="en-cell-pts"><MaskedValue text={fmtPoints(e.score)} /></td>
        <td className="en-cell-pts"><MaskedValue text={fmtPoints(e.result)} /></td>
        <td className="en-cell-note"><MaskedValue text={e.note || '-'} /></td>
        <td><AppButton variant="secondary" size="sm" onClick={onEdit}>Sửa</AppButton></td>
        <td><AppButton variant="danger" size="sm" disabled={deleting} onClick={onDelete}>{deleting ? 'Đang xoá...' : 'Xoá'}</AppButton></td>
      </tr>
      {error && <tr className="en-row-error"><td colSpan={8}><div className="alert alert-error">{error}</div></td></tr>}
    </>
  )
}

/** "Chỉnh sửa số liệu": customer / hạng mục / ngày are read-only info; số, điểm vào and ghi chú can change. */
function EditDialog({ entry, onClose, onSave }: any) {
  const [value, setValue] = useState(entry.value || '')
  const [score, setScore] = useState(entry.score || '')
  const [note, setNote] = useState(entry.note || '')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  async function save() {
    setBusy(true)
    setError('')
    const err = await onSave({ value, score, note })
    setBusy(false)
    if (err) setError(err)
    else onClose()
  }
  return (
    <ModalDialog
      open
      title="Chỉnh sửa số liệu"
      onClose={() => !busy && onClose()}
      footer={
        <>
          <AppButton variant="ghost" disabled={busy} onClick={onClose}>Huỷ</AppButton>
          <AppButton variant="primary" loading={busy} onClick={save}>{busy ? 'Đang lưu...' : 'Lưu thay đổi'}</AppButton>
        </>
      }
    >
      <form className="en-edit" onSubmit={(ev) => { ev.preventDefault(); save() }}>
        <div className="en-edit-info">
          <span className="en-edit-name">{entry.customerName}</span>
          <span className="chip">{betTypeLabel(entry.betType || 'de')}</span>
          <span className="chip">{viDate(entry.entryDate)}</span>
        </div>
        {error && <div className="alert alert-error">{error}</div>}
        <div className="field"><label htmlFor="em-value">Số liệu</label><input id="em-value" data-autofocus type="text" value={value} disabled={busy} onChange={(e) => setValue(e.target.value)} /></div>
        <div className="field"><label htmlFor="em-score">Điểm vào</label><input id="em-score" type="text" inputMode="decimal" value={score} disabled={busy} onChange={(e) => setScore(e.target.value)} /></div>
        {entry.result && <p className="en-hint">Điểm ra: <MaskedValue text={entry.result} /> (sửa ở trang Nhập kết quả)</p>}
        <div className="field"><label htmlFor="em-note">Ghi chú</label><textarea id="em-note" rows={3} value={note} disabled={busy} onChange={(e) => setNote(e.target.value)} /></div>
      </form>
    </ModalDialog>
  )
}
