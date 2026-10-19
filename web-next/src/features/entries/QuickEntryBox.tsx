'use client'
// Nhập nhanh: ONE box for a pasted message or a picture of it (choose / drop / paste). A picture is read into the text
// box on this device (tesseract.js), then both go through the same "Phân tích" preview. Nothing is saved until "Lưu".
import { useEffect, useRef, useState } from 'react'
import AppButton from '@/components/AppButton'
import AppSelect from '@/components/AppSelect'
import ModalDialog from '@/components/ModalDialog'
import { showConfirm } from '@/lib/confirm'
import { betTypeLabel } from '@/lib/betTypes'
import { kindSymbolsFor } from '@/lib/scoringConfig'
import { aliasesToText, textToAliases, parseMessage, DEFAULT_STAKE_MARKERS } from '@/lib/messageParser'
import { readClipboardImage, usePasteImage } from '@/lib/pasteImage'
import { nextUid, ocrGuessRows, rowComplete } from './logic'

/* eslint-disable @typescript-eslint/no-explicit-any */
type Draft = { uid: number; type: string; value: string; score: string; selected: boolean; reasons: string[]; raw: string }

export default function QuickEntryBox({ c }: { c: any }) {
  const [text, setText] = useState('')
  const [drafts, setDrafts] = useState<Draft[]>([])
  const [ignored, setIgnored] = useState<string[]>([])
  const [error, setError] = useState('')
  const [saving, setSaving] = useState(false)
  const [templateOpen, setTemplateOpen] = useState(false)
  const [tpl, setTpl] = useState({ defaultType: '', aliasText: '', markersText: DEFAULT_STAKE_MARKERS.join(', ') })
  const [templateMsg, setTemplateMsg] = useState('')
  const [ocrRunning, setOcrRunning] = useState(false)
  const [ocrProgress, setOcrProgress] = useState(0)
  const [ocrError, setOcrError] = useState('')
  const [previewUrl, setPreviewUrl] = useState('')
  const [zoom, setZoom] = useState(false)
  const [dragOver, setDragOver] = useState(false)
  const fileInput = useRef<HTMLInputElement>(null)
  const ta = useRef<HTMLTextAreaElement>(null)

  const own = c.customers.find((x: any) => x.name === c.customerName)?.scoringRates
  const draftConfig = (t = tpl) => ({
    defaultType: t.defaultType,
    typeAliases: textToAliases(t.aliasText, c.betTypes),
    stakeMarkers: t.markersText.split(/[,;\s]+/).map((m) => m.trim()).filter(Boolean),
  })

  // the textarea grows with its content
  useEffect(() => {
    const el = ta.current
    if (!el) return
    el.style.height = 'auto'
    el.style.height = `${el.scrollHeight + 2}px`
  }, [text])

  // the customer changed: its template fills the template fields and a preview made for the old customer is dropped
  const cfg = c.savedTemplate?.config
  useEffect(() => {
    setTpl({
      defaultType: cfg?.defaultType || '',
      aliasText: aliasesToText(cfg?.typeAliases),
      markersText: (cfg?.stakeMarkers?.length ? cfg.stakeMarkers : DEFAULT_STAKE_MARKERS).join(', '),
    })
    setTemplateMsg('')
  }, [cfg])
  useEffect(() => {
    setDrafts([])
    setIgnored([])
    setError('')
  }, [c.customerName])

  function analyze(source = text, t = tpl): number {
    setError('')
    const res = (parseMessage as any)(source, { betTypes: c.betTypes, template: draftConfig(t), kindSymbols: kindSymbolsFor(c.accountRates, own, c.regionId) })
    setIgnored(res.ignored)
    setDrafts(res.rows.map((r: any) => ({ ...r, uid: nextUid(), selected: !r.uncertain })))
    if (!res.rows.length) setError('Không tìm thấy số nào trong tin nhắn.')
    return res.rows.length
  }

  // text handed over by the chat ("Dùng cho Nhập số"): into the box, analysed like a pasted message (once)
  useEffect(() => {
    if (!c.boxPrefill) return
    const t = c.takeBoxPrefill()
    if (t) {
      setText(t)
      analyze(t)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [c.boxPrefill])

  async function processImage(file: File) {
    setOcrError('')
    if (previewUrl) URL.revokeObjectURL(previewUrl)
    setPreviewUrl(URL.createObjectURL(file))
    setOcrRunning(true)
    setOcrProgress(0)
    try {
      const { recognizeText } = await import('@/lib/ocr')
      const read = (await (recognizeText as any)(file, { onProgress: (p: number) => setOcrProgress(p) })).text.trim()
      if (!read) return setOcrError('Không đọc được chữ nào từ ảnh. Hãy chụp rõ hơn hoặc nhập tay.')
      const merged = text.trim() ? `${text.trim()}\n${read}` : read
      setText(merged)
      if (!analyze(merged)) {
        // nothing like "loại số x điểm": the numbers read become rows of the manual list to check there
        const guess = ocrGuessRows(read, c.betTypes[0])
        c.addRowsFromDrafts(guess)
        if (guess.length) setError('Không thấy dạng "loại số x điểm" trong ảnh: các số đọc được đã thêm vào danh sách phía dưới để bạn kiểm tra.')
      }
    } catch (err) {
      const { describeOcrError } = await import('@/lib/ocr')
      setOcrError(describeOcrError(err))
    } finally {
      setOcrRunning(false)
    }
  }
  usePasteImage((f: File) => processImage(f), () => !!c.customerName && !ocrRunning)

  const clearImage = () => {
    setZoom(false)
    if (previewUrl) URL.revokeObjectURL(previewUrl)
    setPreviewUrl('')
    setOcrError('')
  }
  const patch = (uid: number, p: Partial<Draft>) => setDrafts((d) => d.map((x) => (x.uid === uid ? { ...x, ...p } : x)))
  const picked = drafts.filter((d) => d.selected)
  const uncertain = drafts.filter((d) => d.reasons?.length).length

  async function save() {
    setError('')
    if (!c.customerName) return setError('Chọn khách hàng trước khi lưu.')
    if (!picked.length) return setError('Chưa chọn dòng nào để lưu.')
    if (!picked.every(rowComplete)) return setError('Các dòng đã chọn cần đủ Hạng mục, Số và Điểm vào.')
    const unsure = picked.filter((d) => d.reasons?.length).length
    if (!(await showConfirm({
      title: 'Lưu số liệu từ tin nhắn',
      message: `Lưu ${picked.length} số liệu cho khách hàng "${c.customerName}", ngày ${c.date}?${unsure ? ` Trong đó ${unsure} dòng chưa chắc chắn, hãy chắc là đã kiểm tra.` : ''}`,
      confirmText: 'Lưu',
    }))) return
    setSaving(true)
    try {
      const res = await c.saveDrafts(picked)
      const left = drafts.filter((d) => !res.savedUids.includes(d.uid))
      setDrafts(left)
      setError(res.error)
      if (!left.length) setText('')
      if (!res.error && !left.length) c.finishChatFlow(res.savedCount)
    } finally {
      setSaving(false)
    }
  }
  function toRows() {
    if (!picked.length) return
    c.addRowsFromDrafts(picked)
    setDrafts((d) => d.filter((x) => !x.selected))
  }
  const typeOptions = (t: string) => (c.betTypes.includes(t) ? c.betTypes : [...c.betTypes, t])

  return (
    <div
      className={`en-smart${dragOver ? ' over' : ''}`}
      onDragOver={(e) => { e.preventDefault(); setDragOver(true) }}
      onDragLeave={() => setDragOver(false)}
      onDrop={(e) => {
        e.preventDefault()
        setDragOver(false)
        const f = [...(e.dataTransfer?.files || [])].find((x) => /^image\//.test(x.type))
        if (f && !ocrRunning) processImage(f)
      }}
    >
      <input
        ref={fileInput}
        type="file"
        accept="image/*"
        capture="environment"
        style={{ display: 'none' }}
        data-testid="entries-file"
        onChange={(e) => {
          const f = e.target.files?.[0]
          e.target.value = ''
          if (f) processImage(f)
        }}
      />
      <textarea
        ref={ta}
        className="en-ocr-raw"
        rows={4}
        value={text}
        onChange={(e) => setText(e.target.value)}
        placeholder={'Dán tin nhắn của khách, hoặc dán / thả ảnh vào đây (Ctrl/Cmd+V)\nVd: de 12 34 56 x 10\n      lo 45 78 con 3'}
        aria-label="Tin nhắn hoặc ảnh cần đọc"
      />
      <p className="en-hint">Ảnh được đọc ngay trên trình duyệt, không gửi lên đâu cả. Bấm Phân tích để xem trước; dòng chưa chắc chắn được tô màu và chưa chọn. Chỉ khi bạn bấm Lưu mới ghi vào dữ liệu.</p>
      {ocrError && <div className="alert alert-error">{ocrError}</div>}
      {previewUrl && (
        <div className="en-ocr-result">
          <button type="button" className="en-thumb-btn" title="Bấm để xem ảnh lớn" onClick={() => setZoom(true)}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={previewUrl} alt="Ảnh đã chọn" className="en-thumb" />
            <span>Xem ảnh</span>
          </button>
          <div className="en-ocr-text">
            <span className="en-hint">{ocrRunning ? `Đang đọc ảnh... ${ocrProgress}%` : 'Văn bản đọc từ ảnh đã đưa vào ô trên.'}</span>
            <div><AppButton variant="ghost" size="sm" disabled={ocrRunning} onClick={clearImage}>Xoá ảnh</AppButton></div>
          </div>
        </div>
      )}
      <ModalDialog open={zoom} title="Ảnh đã chọn" xwide onClose={() => setZoom(false)}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={previewUrl} alt="Ảnh đã chọn (xem lớn)" className="en-zoom-img" />
      </ModalDialog>

      <div className="en-actions">
        <AppButton variant="primary" size="sm" disabled={!text.trim() || ocrRunning} onClick={() => analyze()}>Phân tích</AppButton>
        <AppButton variant="secondary" size="sm" icon="camera" disabled={ocrRunning} onClick={() => fileInput.current?.click()}>{ocrRunning ? `Đang đọc ${ocrProgress}%` : 'Chọn ảnh'}</AppButton>
        <AppButton
          variant="ghost"
          size="sm"
          disabled={ocrRunning}
          title="Dán ảnh từ bộ nhớ tạm"
          onClick={async () => {
            setOcrError('')
            try { processImage(await readClipboardImage()) } catch (e) { setOcrError((e as Error).message) }
          }}
        >Dán ảnh</AppButton>
        <AppButton variant="ghost" size="sm" onClick={() => setTemplateOpen((v) => !v)}>Mẫu cú pháp của khách này {c.savedTemplate ? '(đã lưu)' : '(chưa lưu)'}</AppButton>
      </div>

      {templateOpen && (
        <div className="en-box">
          <p className="en-hint">Mô tả cách khách này hay viết để phân tích đúng hơn. Mẫu chỉ được lưu khi bạn bấm Lưu mẫu, hệ thống không tự học thêm.</p>
          <div className="en-tpl-grid">
            <div className="field">
              <label htmlFor="tpl-type">Hạng mục mặc định</label>
              <AppSelect id="tpl-type" value={tpl.defaultType} onChange={(v: string) => setTpl({ ...tpl, defaultType: v })}>
                <option value="">Không đặt (dòng không ghi hạng mục sẽ bị đánh dấu)</option>
                {c.betTypes.map((t: string) => <option key={t} value={t}>{betTypeLabel(t)}</option>)}
              </AppSelect>
            </div>
            <div className="field">
              <label htmlFor="tpl-alias">Cách viết hạng mục</label>
              <input id="tpl-alias" type="text" value={tpl.aliasText} placeholder="vd: dd=de, l=lo" onChange={(e) => setTpl({ ...tpl, aliasText: e.target.value })} />
            </div>
            <div className="field">
              <label htmlFor="tpl-markers">Dấu ngăn điểm</label>
              <input id="tpl-markers" type="text" value={tpl.markersText} placeholder="vd: x, con, =" onChange={(e) => setTpl({ ...tpl, markersText: e.target.value })} />
            </div>
          </div>
          <div className="en-actions">
            <AppButton variant="secondary" size="sm" onClick={async () => setTemplateMsg(await c.saveTemplate(draftConfig()))}>Lưu mẫu cho {c.customerName}</AppButton>
            {c.savedTemplate && <AppButton variant="ghost" size="sm" onClick={async () => setTemplateMsg(await c.deleteTemplate())}>Xoá mẫu</AppButton>}
          </div>
          {templateMsg && <p className="en-hint">{templateMsg}</p>}
        </div>
      )}

      {error && <div className="alert alert-error">{error}</div>}

      {drafts.length > 0 && (
        <div className="en-box">
          <p className="en-hint">Đã chọn {picked.length}/{drafts.length} dòng{uncertain ? `, ${uncertain} dòng chưa chắc chắn (tô vàng)` : ''}.</p>
          {drafts.map((r) => (
            <div key={r.uid} className={`en-pv-row${r.reasons?.length ? ' is-uncertain' : ''}`}>
              <label className="en-check"><input type="checkbox" checked={r.selected} aria-label={`Chọn dòng ${r.value}`} onChange={(e) => patch(r.uid, { selected: e.target.checked })} /></label>
              <AppSelect value={r.type} onChange={(v: string) => patch(r.uid, { type: v })} aria-label="Hạng mục">
                {typeOptions(r.type).map((t: string) => <option key={t} value={t}>{betTypeLabel(t)}</option>)}
              </AppSelect>
              <input type="text" className="en-input en-number" aria-label="Số" value={r.value} onChange={(e) => patch(r.uid, { value: e.target.value })} />
              <input type="text" inputMode="decimal" className="en-input" placeholder="Điểm vào" aria-label="Điểm vào" value={r.score} onChange={(e) => patch(r.uid, { score: e.target.value })} />
              {r.reasons?.length > 0 && <div className="en-pv-reason">Chưa chắc chắn: {r.reasons.join('; ')} (dòng gốc: {r.raw})</div>}
            </div>
          ))}
          {ignored.length > 0 && <p className="en-hint">Bỏ qua {ignored.length} dòng không có số: {ignored.join(' / ')}</p>}
          <div className="en-actions">
            <AppButton variant="primary" size="sm" disabled={saving || !c.canAdd || !picked.length} onClick={save}>{saving ? 'Đang lưu...' : `Xác nhận và lưu ${picked.length} dòng`}</AppButton>
            <AppButton variant="secondary" size="sm" disabled={!picked.length} onClick={toRows}>Đưa vào bảng nhập tay để sửa</AppButton>
            <AppButton variant="ghost" size="sm" onClick={() => { setDrafts([]); setIgnored([]); setError('') }}>Bỏ xem trước</AppButton>
          </div>
        </div>
      )}
    </div>
  )
}
