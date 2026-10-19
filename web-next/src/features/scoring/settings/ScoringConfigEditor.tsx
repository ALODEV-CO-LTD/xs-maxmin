'use client'
import './ScoringConfigEditor.css'
import { Fragment, useEffect, useMemo, useRef, useState } from 'react'
import ActionBar from '@/components/ActionBar'
import AppButton from '@/components/AppButton'
import { api, ApiError } from '@/lib/api'
import { showConfirm } from '@/lib/confirm'
import { DEFAULT_RATES, describeSource, prizeInfo } from '@/lib/scoringConfig'
import {
  REGIONS, REGION_NAMES, addRow, buildRows, emptyAddForm, fieldsOf, fmt, groupsOf, hasOwn, initialOf, isDirty, loadWork, newState,
  noteOf, notSet, openAddForm, prepareSave, removeMessage, removeRow, resetAllWork, resetRow, resetSrcPatch, restorable,
  regionHasOverride, savedNotice, srcCaption, srcOf, switchRegion, symbolText, tagOf, toggleOff,
} from './editorModel'

/* eslint-disable @typescript-eslint/no-explicit-any */
type Row = Record<string, any>
type St = { work: Record<string, any>; rows: Row[]; region: string }

// Bảng cấu hình tính điểm: mỗi dòng một cách đánh theo từng miền (Kiểu đánh | Ký hiệu | Giá tiền / 1 điểm | Giá trúng / 1 điểm).
// Dùng ở hai nơi (cùng props với bản Vue):
//   scope="default"   cấu hình mặc định của tài khoản (menu Cấu hình tính điểm)   GET/PUT /me/scoring-settings
//   scope="customer"  cấu hình riêng của một khách (Khách hàng > Cấu hình tính điểm): customer, accountRates
//                     PATCH /me/customers/:id { scoringRates }
// onSaved(map) sau khi lưu. Logic thuần ở editorModel.js.
export interface ScoringConfigEditorProps {
  scope?: 'default' | 'customer'
  customer?: { id: string; name: string; scoringRates?: Record<string, any> | null } | null
  accountRates?: Record<string, any>
  onSaved?: (map: any) => void
}

const EMPTY: Record<string, any> = {}

export default function ScoringConfigEditor({ scope = 'default', customer = null, accountRates = EMPTY, onSaved }: ScoringConfigEditorProps) {
  const isCustomer = scope === 'customer'
  const ctx = useMemo(() => ({ isCustomer, base: isCustomer ? accountRates : EMPTY, customerName: customer?.name ?? '' }), [isCustomer, accountRates, customer?.name])
  const ctxRef = useRef(ctx)
  ctxRef.current = ctx
  const customerRef = useRef(customer)
  customerRef.current = customer

  const [region, setRegion] = useState('mb')
  const [st, setSt] = useState<St>(() => newState(ctx, {}, 'mb'))
  const [initial, setInitial] = useState('{}')
  // Values and ký hiệu are shown as text; only after "Sửa" can they be changed.
  const [editing, setEditing] = useState(false)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [addForm, setAddForm] = useState(emptyAddForm())
  const stRef = useRef(st)
  stRef.current = st

  async function init() {
    const c = ctxRef.current
    setLoading(true)
    setError('')
    let work: Record<string, any> | null = null
    try {
      if (c.isCustomer) {
        work = loadWork(customerRef.current?.scoringRates || {})
      } else {
        const { rates } = await api.get('/me/scoring-settings')
        work = loadWork(rates && Object.keys(rates).length ? rates : DEFAULT_RATES)
      }
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Không tải được cấu hình')
    } finally {
      const prev = stRef.current
      const w = work ?? prev.work
      if (work) setInitial(initialOf(work))
      setSt(newState(c, w, prev.region))
      setLoading(false)
    }
  }
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- loads the settings on mount / when the customer changes
    void init()
  }, [customer?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  // the account-wide map changed (customer scope: the fallback): rebuild the rows
  const firstRates = useRef(true)
  useEffect(() => {
    if (firstRates.current) {
      firstRates.current = false
      return
    }
    // eslint-disable-next-line react-hooks/set-state-in-effect -- rows follow the fallback map
    if (!loading) setSt((s) => ({ ...s, rows: buildRows(ctx, s.work, s.region) }))
  }, [accountRates]) // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => setRegion(st.region), [st.region])

  const patchRow = (type: string, patch: Row) => setSt((s) => ({ ...s, rows: s.rows.map((r) => (r.type === type ? { ...r, ...patch } : r)) }))
  const groups = groupsOf(st.rows, editing)
  const colCount = isCustomer ? 6 : 5

  function onSwitchRegion(id: string) {
    const res = switchRegion(ctx, st, id)
    setError(res.error)
    if (!res.error) setSt(res.st)
  }
  async function onRemove(r: Row) {
    const ok = await showConfirm({ title: 'Xoá cách đánh', message: removeMessage(ctx, st.region, r), confirmText: 'Xoá', danger: true })
    if (!ok) return
    setSt((s) => removeRow(ctx, s, r))
  }
  function toggleTier(r: Row, t: string) {
    const i = r.srcTiers.indexOf(t)
    const tiers = [...r.srcTiers]
    if (i === -1) tiers.push(t)
    else tiers.splice(i, 1)
    patchRow(r.type, { srcTiers: tiers })
  }
  function onAddSubmit(e: React.FormEvent) {
    e.preventDefault()
    const res = addRow(ctx, st, addForm)
    setSt(res.st)
    if (res.closed) setAddForm((f) => ({ ...f, open: false, error: '' }))
    else setAddForm((f) => ({ ...f, error: res.error }))
  }

  async function save() {
    setError('')
    setNotice('')
    const prep = prepareSave(ctx, st)
    if (prep.error) {
      setError(prep.error)
      return
    }
    setSt((s) => ({ ...s, work: prep.work }))
    setSaving(true)
    try {
      let work: Record<string, any>
      if (isCustomer) {
        const map = prep.map as Record<string, any>
        const res = await api.patch(`/me/customers/${customer!.id}`, { scoringRates: Object.keys(map).length ? map : null })
        work = loadWork(res.scoringRates || {})
        setNotice(savedNotice(ctx, res.scoringRates))
        onSaved?.(res.scoringRates || null)
      } else {
        const res = await api.put('/me/scoring-settings', { rates: prep.map })
        work = loadWork(res.rates)
        setNotice(savedNotice(ctx, res.rates))
        onSaved?.(res.rates)
      }
      setInitial(initialOf(work))
      setSt(newState(ctx, work, st.region))
      setEditing(false)
    } catch (err) {
      setError(err instanceof ApiError ? (err.status === 0 ? 'Mất kết nối tới máy chủ, chưa lưu được.' : err.message) : 'Không lưu được cấu hình')
    } finally {
      setSaving(false)
    }
  }
  function cancelEdit() {
    setEditing(false)
    setError('')
    setNotice('')
    void init()
  }
  const dirty = isDirty(ctx, st, initial)

  if (loading) return <div className="sce"><div className="sce-note">Đang tải...</div></div>

  return (
    <div className="sce">
      {error && <div className="alert alert-error">{error}</div>}
      {notice && <div className="alert alert-success">{notice}</div>}

      <div className="sce-bar">
        <div className="sce-tabs" role="tablist" aria-label="Miền">
          {REGIONS.map((id) => (
            <button key={id} type="button" role="tab" className={`sce-tab${region === id ? ' on' : ''}`} aria-selected={region === id} onClick={() => onSwitchRegion(id)}>
              {REGION_NAMES[id as keyof typeof REGION_NAMES]}
              {regionHasOverride(ctx, st.work, id) && <span className="sce-dot" title="Có cấu hình riêng cho miền này" />}
            </button>
          ))}
        </div>
        {!editing ? (
          <AppButton variant="secondary" size="sm" onClick={() => { setEditing(true); setNotice('') }}>Sửa</AppButton>
        ) : (
          <span className="sce-muted">Đang sửa: thêm, sửa giá, xoá từng cách đánh rồi bấm Lưu</span>
        )}
      </div>

      <div className="sce-table-wrap">
        <table className="sce-table">
          <thead>
            <tr>
              {isCustomer && <th className="c-use">Dùng</th>}
              <th className="c-kind">Cách đánh</th>
              <th className="c-sym">Ký hiệu</th>
              <th className="c-num">Giá tiền / 1 điểm</th>
              <th className="c-num">Giá trúng / 1 điểm</th>
              <th className="c-act"></th>
            </tr>
          </thead>
          {groups.map((g) => (
            <tbody key={g.id}>
              <tr className="grp">
                <th colSpan={colCount} scope="colgroup">
                  <span className="grp-name">{g.label}<span className="sce-muted"> · {g.rows.length} cách đánh</span></span>
                  {editing && <button type="button" className="btn btn-ghost btn-sm grp-add" onClick={() => setAddForm(openAddForm(ctx, st, g.id))}>+ Thêm cách đánh</button>}
                </th>
              </tr>
              {editing && addForm.open && addForm.group === g.id && (
                <tr className="grp-form">
                  <td colSpan={colCount}>
                    <form className="sce-add" onSubmit={onAddSubmit}>
                      <strong>Thêm vào &quot;{g.label}&quot; ({REGION_NAMES[st.region as keyof typeof REGION_NAMES]})</strong>
                      {restorable(ctx, st, g.id).length > 0 && (
                        <label className="sce-pick">Chọn
                          <select value={addForm.pick} onChange={(e) => setAddForm((f) => ({ ...f, pick: e.target.value }))}>
                            {restorable(ctx, st, g.id).map((k) => <option key={k.kind} value={k.kind}>Khôi phục: {k.label}</option>)}
                            <option value="new">Cách đánh mới (tự đặt tên, ký hiệu)</option>
                          </select>
                        </label>
                      )}
                      {addForm.pick === 'new' && (
                        <div className="sce-add-grid">
                          <label>Tên<input value={addForm.name} onChange={(e) => setAddForm((f) => ({ ...f, name: e.target.value }))} type="text" maxLength={30} placeholder="Ví dụ: Đề 3 số" /></label>
                          <label>Ký hiệu<input value={addForm.symbol} onChange={(e) => setAddForm((f) => ({ ...f, symbol: e.target.value }))} type="text" maxLength={12} placeholder="Ví dụ: d3" /></label>
                          <label>So với
                            <select value={addForm.tiers} onChange={(e) => setAddForm((f) => ({ ...f, tiers: e.target.value }))}>
                              <option value="special">Giải đặc biệt</option>
                              <option value="all">Tất cả các giải</option>
                            </select>
                          </label>
                          <label>Số cuối
                            <select value={addForm.digits} onChange={(e) => setAddForm((f) => ({ ...f, digits: Number(e.target.value) }))}>
                              <option value={2}>2 số</option>
                              <option value={3}>3 số</option>
                              <option value={4}>4 số</option>
                            </select>
                          </label>
                          <label>Giá tiền / 1 điểm<input value={addForm.price} onChange={(e) => setAddForm((f) => ({ ...f, price: e.target.value }))} type="number" min="0" step="any" /></label>
                          <label>Giá trúng / 1 điểm<input value={addForm.payout} onChange={(e) => setAddForm((f) => ({ ...f, payout: e.target.value }))} type="number" min="0" step="any" /></label>
                        </div>
                      )}
                      {addForm.error && <p className="alert alert-error">{addForm.error}</p>}
                      <div className="sce-add-actions">
                        <AppButton variant="ghost" size="sm" onClick={() => setAddForm((f) => ({ ...f, open: false }))}>Huỷ</AppButton>
                        <AppButton variant="primary" size="sm" type="submit">{addForm.pick === 'new' ? 'Thêm' : 'Khôi phục'}</AppButton>
                      </div>
                    </form>
                  </td>
                </tr>
              )}
              {g.rows.map((r: Row) => {
                const own = hasOwn(ctx, st, r)
                const tag = tagOf(ctx, st, r)
                const warn = notSet(r)
                const f = fieldsOf(r)
                return (
                  <Fragment key={r.type}>
                    <tr className={`${r.off ? 'off' : ''}${isCustomer && own ? ' own' : ''}`.trim()}>
                      {isCustomer && (
                        <td className="c-use" data-label="Dùng">
                          {editing ? (
                            <input type="checkbox" checked={!r.off} aria-label={`Khách này đánh ${r.label}`} onChange={() => setSt((s) => toggleOff(ctx, s, r))} />
                          ) : (
                            <span>{r.off ? '–' : '✓'}</span>
                          )}
                        </td>
                      )}
                      <td className="c-kind" data-label="Kiểu đánh">
                        {editing && r.extra ? (
                          <input value={r.name} onChange={(e) => patchRow(r.type, { name: e.target.value })} type="text" className="name-input" maxLength={30} aria-label={`Tên cách đánh ${r.type}`} />
                        ) : (
                          <strong>{r.label}</strong>
                        )}
                        {tag && <span className={`sce-tag${own ? ' own' : ''}`}>{tag}</span>}
                        <small className="sce-src">Lấy số: {srcCaption(r, st.region)}
                          {editing && !r.off && <button type="button" className="link-btn" onClick={() => patchRow(r.type, { srcOpen: !r.srcOpen })}>{r.srcOpen ? 'Đóng' : 'Chỉnh lấy số'}</button>}
                        </small>
                      </td>
                      <td className="c-sym" data-label="Ký hiệu">
                        {editing && r.editable ? (
                          <input value={r.symbolsInput} onChange={(e) => patchRow(r.type, { symbolsInput: e.target.value })} type="text" className="sym-input" aria-label={`Ký hiệu ${r.label}`} placeholder="Cách nhau bằng dấu phẩy" />
                        ) : (
                          <span className="sce-muted">{symbolText(r)}</span>
                        )}
                      </td>
                      <td className="c-num" data-label="Giá tiền / 1 điểm">
                        {editing && !r.off ? (
                          <input value={r.price} onChange={(e) => patchRow(r.type, { price: e.target.value })} type="number" min="0" step="any" inputMode="decimal" aria-label={`Giá tiền 1 điểm ${r.label}`} />
                        ) : !r.off ? (
                          <span className="val">{fmt(r.price)}</span>
                        ) : (
                          <span className="sce-muted">-</span>
                        )}
                      </td>
                      <td className="c-num" data-label="Giá trúng / 1 điểm">
                        {editing && !r.off ? (
                          <input value={r.payout} onChange={(e) => patchRow(r.type, { payout: e.target.value })} type="number" min="0" step="any" inputMode="decimal" className={warn ? 'warn' : ''} aria-label={`Giá trúng 1 điểm ${r.label}`} />
                        ) : !r.off ? (
                          <span className={`val${warn ? ' warn' : ''}`}>{fmt(r.payout)}</span>
                        ) : (
                          <span className="sce-muted">-</span>
                        )}
                        {warn && <small className="sce-warn">Chưa nhập</small>}
                      </td>
                      <td className="c-act">
                        {editing && (
                          <>
                            {own && isCustomer && <AppButton variant="ghost" size="sm" onClick={() => setSt((s) => resetRow(ctx, s, r))}>Theo chung</AppButton>}
                            {(r.extra || !isCustomer) && <button type="button" className="btn btn-ghost btn-sm sce-del" onClick={() => onRemove(r)}>Xoá</button>}
                          </>
                        )}
                      </td>
                    </tr>
                    {editing && r.srcOpen && !r.off && (
                      <tr className="src-row">
                        <td colSpan={colCount}>
                          <div className="src-panel">
                            {f.tiers && (
                              <div className="src-field">
                                <strong>Giải (dãy giải lấy số)</strong>
                                <div className="src-tiers">
                                  {prizeInfo(st.region).map((p: any) => (
                                    <label key={p.tier} className="src-tier">
                                      <input type="checkbox" checked={r.srcTiers.includes(p.tier)} onChange={() => toggleTier(r, p.tier)} />
                                      {p.label} <span className="sce-muted">({p.count} lô × {p.digits} số)</span>
                                    </label>
                                  ))}
                                </div>
                              </div>
                            )}
                            <div className="src-line">
                              {f.position && (
                                <label>Vị trí
                                  <select value={r.srcPos} onChange={(e) => patchRow(r.type, { srcPos: e.target.value })}><option value="last">Cuối (đuôi)</option><option value="first">Đầu</option></select>
                                </label>
                              )}
                              {f.digits && (
                                <label>Bao nhiêu số
                                  <select value={r.srcDigits} onChange={(e) => patchRow(r.type, { srcDigits: Number(e.target.value) })}>{[1, 2, 3, 4, 5, 6].map((n) => <option key={n} value={n}>{n} số</option>)}</select>
                                </label>
                              )}
                              {f.pick && (
                                <label>Lô thứ (để trống = mọi lô của giải)
                                  <input value={r.srcPick} onChange={(e) => patchRow(r.type, { srcPick: e.target.value })} type="text" placeholder="Ví dụ: 1, 2" />
                                </label>
                              )}
                              <AppButton variant="ghost" size="sm" onClick={() => patchRow(r.type, resetSrcPatch(r, st.region))}>Về mặc định</AppButton>
                            </div>
                            <small className="sce-muted">Đang lấy: {describeSource(srcOf(r), st.region)}</small>
                          </div>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                )
              })}
            </tbody>
          ))}
        </table>
      </div>

      <ActionBar
        sticky={editing}
        align="between"
        start={editing ? <AppButton variant="ghost" size="sm" disabled={saving} onClick={() => setSt(newState(ctx, resetAllWork(ctx), st.region))}>{isCustomer ? 'Bỏ cấu hình riêng' : 'Đặt lại mặc định'}</AppButton> : undefined}
        note={noteOf(ctx, st.work)}
      >
        {editing && (
          <>
            <AppButton variant="ghost" disabled={saving} onClick={cancelEdit}>Huỷ</AppButton>
            <AppButton variant="primary" loading={saving} disabled={!dirty} onClick={save}>{saving ? 'Đang lưu...' : isCustomer ? 'Lưu cấu hình khách này' : 'Lưu cấu hình'}</AppButton>
          </>
        )}
      </ActionBar>
    </div>
  )
}
