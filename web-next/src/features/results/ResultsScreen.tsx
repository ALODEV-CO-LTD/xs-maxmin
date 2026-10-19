'use client'
// Nhập kết quả (port of views/ResultsView.vue): the day's lottery results per region / station, read from a photo or
// typed, and the "Điểm ra" of every entry of the day worked out from them.
import './results.css'
import { useRef } from 'react'
import AppButton from '@/components/AppButton'
import AppDatePicker from '@/components/AppDatePicker'
import AppIcon from '@/components/AppIcon'
import AppSelect from '@/components/AppSelect'
import { stationName, regionOf } from '@/lib/lotteryStations'
import { readClipboardImage, usePasteImage } from '@/lib/pasteImage'
import { useResults } from './useResults'
import { MB_COL, SINGLE_TIERS, cellBad } from './logic'
import { useState } from 'react'

/* eslint-disable @typescript-eslint/no-explicit-any */
export default function ResultsScreen() {
  const r: any = useResults()
  const file = useRef<HTMLInputElement>(null)
  const [gridOpen, setGridOpen] = useState(false)
  const [addPick, setAddPick] = useState('')
  const mb = r.region === MB_COL
  const colName = (c: string) => (c === MB_COL ? 'Miền Bắc' : stationName(c))
  const cur = r.curCol
  const form = cur ? r.formOf(cur) : null
  const locked = cur ? r.locked(cur) : false
  const flagEmpty = !!r.read[cur] // empty cells of a photo are flagged
  const open = gridOpen || r.filled > 0
  const regionName = regionOf(r.region).name

  usePasteImage((f: File) => r.processImage(f), () => !r.ocr.running)

  return (
    <div className="page rs-page">
      <h1 className="page-title">Nhập kết quả</h1>
      <p className="page-subtitle">
        Nhập kết quả xổ số (Miền Bắc, Miền Trung, Miền Nam) rồi bấm &quot;Lưu kết quả&quot; để điểm ra tự hiện theo số và điểm vào, rồi bấm &quot;Lưu điểm ra&quot; để lưu cho tất cả khách hàng. Kết quả xổ số đã lưu chỉ hiển thị; bấm &quot;Sửa&quot; để chỉnh.
      </p>

      <div className="card rs-card">
        <div className="rs-head">
          <h3>Kết quả xổ số {regionName}</h3>
          <div className="rs-date-nav">
            <AppButton variant="ghost" size="sm" aria-label="Ngày trước" title="Ngày trước" onClick={() => r.shift(-1)}>‹</AppButton>
            <AppDatePicker className="rs-date" value={r.date} onChange={(v) => v && r.setDate(v)} />
            <AppButton variant="ghost" size="sm" aria-label="Ngày sau" title="Ngày sau" onClick={() => r.shift(1)}>›</AppButton>
          </div>
        </div>

        <div className="rs-tabs" role="tablist" aria-label="Miền">
          {r.regions.map((x: any) => (
            <button key={x.id} type="button" role="tab" className={`rs-tab${r.region === x.id ? ' on' : ''}`} aria-selected={r.region === x.id} onClick={() => r.setRegion(x.id)}>{x.name}</button>
          ))}
        </div>

        <div className="rs-ocr">
          <input
            ref={file}
            type="file"
            accept="image/*"
            {...(mb ? { capture: 'environment' as const } : {})}
            style={{ display: 'none' }}
            onChange={(e) => {
              const f = e.target.files?.[0]
              e.target.value = ''
              if (f) r.processImage(f)
            }}
          />
          <AppButton variant="secondary" block disabled={r.ocr.running} onClick={() => file.current?.click()}>
            {!r.ocr.running && <AppIcon name="camera" />}
            {' '}
            {r.ocr.running ? `Đang đọc ảnh... ${r.ocr.progress}%` : 'Đọc kết quả từ ảnh'}
          </AppButton>
          <button
            type="button"
            className="btn btn-ghost btn-sm rs-paste"
            disabled={r.ocr.running}
            onClick={async () => {
              r.patchOcr({ error: '' })
              try { r.processImage(await readClipboardImage()) } catch (e) { r.patchOcr({ error: (e as Error).message }) }
            }}
          >Dán ảnh từ bộ nhớ tạm</button>
          <p className="rs-hint">
            Chọn hoặc dán ảnh (Ctrl/Cmd+V) bảng kết quả{mb ? '' : ' (mỗi đài một cột)'}. Xử lý ngay trên trình duyệt; kết quả chỉ là gợi ý để bạn kiểm tra (đặc biệt số có số 0 ở đầu), chưa lưu cho tới khi bạn bấm lưu.
          </p>
          {r.ocr.error && <div className="alert alert-error">{r.ocr.error}</div>}
          {!mb && r.ocr.note && <div className="alert alert-success">{r.ocr.note}</div>}
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {mb && r.ocr.previewUrl && !r.ocr.running && <img src={r.ocr.previewUrl} alt="Ảnh đã chọn" className="rs-thumb" />}
          {!mb && r.ocr.warnings.length > 0 && <ul className="rs-warnings">{r.ocr.warnings.map((w: string, i: number) => <li key={i}>{w}</li>)}</ul>}
        </div>

        {r.boardLoading ? (
          <p className="page-subtitle">Đang tải...</p>
        ) : (
          <>
            {r.error && <div className="alert alert-error">{r.error}</div>}
            {r.saveMsg && <div className="alert alert-success">{r.saveMsg}</div>}

            {!r.cols.length ? (
              <p className="page-subtitle">Ngày này không có đài nào của miền này.</p>
            ) : (
              <>
                {!mb && (
                  <div className="rs-tabs" role="tablist" aria-label="Đài">
                    {r.cols.map((c: string) => (
                      <button key={c} type="button" role="tab" className={`rs-chip${cur === c ? ' on' : ''}`} aria-selected={cur === c} onClick={() => r.setActiveCol(c)}>
                        {colName(c)}{r.saved[c] && <span className="rs-chip-saved" title="Đã lưu"> ✓</span>}
                      </button>
                    ))}
                    {r.otherStations.length > 0 && (
                      <AppSelect className="rs-station-add" value={addPick} aria-label="Thêm đài khác" onChange={(v: string) => { r.addStation(v); setAddPick('') }}>
                        <option value="">+ Đài khác ({r.otherStations.length})</option>
                        {r.otherStations.map((o: any) => <option key={o.value} value={o.value}>{o.label}</option>)}
                      </AppSelect>
                    )}
                  </div>
                )}

                <button type="button" className={`rs-toggle${open ? ' open' : ''}`} aria-expanded={open} aria-controls="lottery-grid" onClick={() => setGridOpen(!gridOpen)}>
                  <span className="rs-toggle-label">Nhập tay các giải{!mb ? ` · ${colName(cur)}` : ''}</span>
                  <span className="rs-toggle-count">{r.filled}/{r.total}</span>
                  <AppIcon name="chevron-down" />
                </button>

                {form && (
                  <div id="lottery-grid" className={`rs-grid${open ? '' : ' collapsed'}${locked ? ' readonly' : ''}`}>
                    {r.structure.map((p: any) => (
                      <div key={p.tier} className="rs-tier">
                        <label>{p.label}<span className="rs-tier-count">{p.count} ô · {p.digits} số</span></label>
                        {SINGLE_TIERS.includes(p.tier) ? (
                          <input
                            value={form[p.tier]}
                            readOnly={locked}
                            maxLength={p.digits}
                            placeholder={'0'.repeat(p.digits)}
                            className={`rs-n${p.digits}${cellBad(p, form[p.tier], mb ? false : flagEmpty) ? ' bad' : ''}`}
                            inputMode="numeric"
                            autoComplete="off"
                            aria-label={`${p.label} ${colName(cur)}`}
                            onChange={(e) => r.editCell(cur, p, null, e.target.value)}
                          />
                        ) : (
                          <div className="rs-tier-inputs">
                            {form[p.tier].map((v: string, k: number) => (
                              <input
                                key={k}
                                value={v}
                                readOnly={locked}
                                maxLength={p.digits}
                                placeholder={'0'.repeat(p.digits)}
                                className={`rs-n${p.digits}${cellBad(p, v, mb ? false : flagEmpty) ? ' bad' : ''}`}
                                inputMode="numeric"
                                autoComplete="off"
                                aria-label={`${p.label} ${colName(cur)} số ${k + 1}`}
                                onChange={(e) => r.editCell(cur, p, k, e.target.value)}
                              />
                            ))}
                            {!locked && (
                              <span className="rs-cell-tools">
                                <button type="button" className="rs-cell-btn" aria-label={`Thêm ô ${p.label}`} title="Thêm một ô nếu kết quả có nhiều số hơn" onClick={() => r.plusCell(cur, p)}>+</button>
                                {form[p.tier].length > p.count && <button type="button" className="rs-cell-btn" aria-label={`Bớt ô ${p.label}`} title="Bớt ô vừa thêm" onClick={() => r.minusCell(cur, p)}>−</button>}
                              </span>
                            )}
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}

                <div className="rs-actions">
                  {r.saved[cur] && <AppButton variant="danger" size="sm" disabled={r.deleting === cur} onClick={() => r.deleteColumn(cur)}>{r.deleting === cur ? 'Đang xoá...' : 'Xoá kết quả này'}</AppButton>}
                  <AppButton variant="secondary" size="sm" disabled={!locked} onClick={() => r.unlock(cur)}>Sửa</AppButton>
                  <AppButton variant="ghost" size="sm" onClick={r.clearForm}>Xoá form</AppButton>
                  <AppButton variant="primary" disabled={r.saving || !r.cols.length} onClick={r.save}>{r.saving ? 'Đang lưu...' : 'Lưu kết quả'}</AppButton>
                </div>
              </>
            )}
          </>
        )}
      </div>

      {r.loading ? (
        <div className="card">Đang tải...</div>
      ) : r.loadError ? (
        <div className="alert alert-error">{r.loadError}</div>
      ) : (
        <>
          {r.syncMsg && (
            <div className="alert alert-success rs-sync">
              <span>{r.syncMsg}</span>
              {r.undo && <AppButton variant="secondary" size="sm" disabled={r.undoing} onClick={r.undoScores}>{r.undoing ? 'Đang hoàn tác...' : 'Hoàn tác'}</AppButton>}
            </div>
          )}
          {r.syncError && <div className="alert alert-error">{r.syncError}</div>}
        </>
      )}
    </div>
  )
}
