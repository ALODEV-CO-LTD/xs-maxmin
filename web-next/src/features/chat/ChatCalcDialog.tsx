'use client'
import './ChatCalcDialog.css'
import { useEffect, useMemo, useState } from 'react'
import ModalDialog from '@/components/ModalDialog'
import { api } from '@/lib/api'
import { buildReport, groupLines, money, reportId, reportText } from '@/lib/chatReport'
import { stationName as nameOf, stationsOn } from '@/lib/lotteryStations'
import { parseMessage } from '@/lib/messageParser'
import { kindSymbolsFor, typesOf } from '@/lib/scoringConfig'
import { useChatStore, reasonText } from './chatStore'

// Tính toán từ tin nhắn: Chọn đài → Kết quả tính toán (8 mục) → Lưu / Copy / Gửi cho khách hàng.
//   Chọn đài   một thẻ lớn cho mỗi đài quay trong ngày; không tự chọn.
//   Kết quả    tính bằng kết quả ĐÚNG đài + ngày của tài khoản (GET /lottery-results); chưa có kết quả thì báo và cho
//              thử lại, tuyệt đối không dùng số mẫu hay đài khác.
//   Lưu        trên máy này (metaSet `report:<id>` + danh sách `reports:index`); id theo nội dung nên không trùng bản ghi.
//   Gửi        xem trước rồi gửi đúng nội dung báo cáo qua chat mã hoá; kết quả gửi lấy từ trạng thái tin thật.
/* eslint-disable @typescript-eslint/no-explicit-any */
type Friend = { id: string; name: string }
type Customer = { id: string; name: string; scoringRates?: any }
type SavedIndex = { id: string; savedAt: string; date: string; stationName: string; profit: number | null }

const fmtDate = (d: string) => String(d || '').split('-').reverse().join('/')
const fmtProfit = (n: number | null | undefined) => (n == null ? 'Chưa đủ dữ liệu' : money(n))

export default function ChatCalcDialog({ open, text, date, friends, customerId, onClose, onBack }: {
  open: boolean
  text: string
  date: string
  friends: Friend[]
  customerId: string
  onClose?: () => void
  onBack: () => void
}) {
  void onClose
  const [step, setStep] = useState<'station' | 'report' | 'saved'>('station')
  const [selected, setSelected] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [rep, setRep] = useState<any>(null)
  const [notice, setNotice] = useState('')
  const [customers, setCustomers] = useState<Customer[]>([])
  const [rates, setRates] = useState<any>({})
  const [saved, setSaved] = useState<SavedIndex[]>([])
  const [sendOpen, setSendOpen] = useState(false)
  const [sendTo, setSendTo] = useState<Friend | null>(null)
  const [sending, setSending] = useState(false)
  const [sendResult, setSendResult] = useState('')
  const chat = useChatStore.getState

  const customer = customers.find((c) => c.id === customerId) || null
  const stationIds = useMemo(() => ['mb', ...stationsOn('mt', date), ...stationsOn('mn', date)], [date])
  const nameFor = (id: string) => (id === 'mb' ? 'Miền Bắc' : nameOf(id))
  const title = step === 'station' ? 'Chọn đài tính toán' : step === 'saved' ? 'Báo cáo đã lưu' : 'Kết quả tính toán'

  useEffect(() => {
    if (!open) return
    setStep('station'); setSelected(''); setError(''); setNotice(''); setSendResult(''); setRep(null); setSendOpen(false)
    ;(async () => {
      try { setRates((await api.get('/me/scoring-settings')).rates || {}) } catch { /* mặc định */ }
      try { setCustomers((await api.get('/me/customers')).customers || []) } catch { setCustomers([]) }
      setSaved((await chat().metaGet('reports:index')) || [])
    })()
  }, [open, chat])

  const reportBody: string = rep ? reportText(rep) : ''

  async function confirmStation() {
    if (!selected) return
    setLoading(true)
    setError('')
    try {
      let result = null
      try {
        result = (await api.get(`/lottery-results?date=${date}&station=${encodeURIComponent(selected)}`)).result
      } catch (err) {
        setError((err as Error).message || 'Không lấy được kết quả xổ số')
        return
      }
      const own = customer?.scoringRates || null
      const region = selected === 'mb' ? 'mb' : selected.startsWith('mt') ? 'mt' : 'mn'
      const types = typesOf(rates).length ? typesOf(rates) : ['de', 'lo']
      const { rows } = parseMessage(text, { betTypes: types, kindSymbols: kindSymbolsFor(rates, own, region) } as any)
      if (!rows.length) return setError('Không tìm thấy số liệu hợp lệ trong các tin đã chọn.')
      const next = buildReport({ rows, result, station: selected, stationName: nameFor(selected), customerName: customer?.name || '', date, accountRates: rates, customerRates: own } as any)
      setRep(next)
      setStep('report')
      if (next.missingResult) setError(`Chưa có kết quả đài ${nameFor(selected)} ngày ${fmtDate(date)}. Hãy lưu kết quả ở tab Nhập kết quả rồi bấm Thử lại.`)
    } finally {
      setLoading(false)
    }
  }

  async function save() {
    setNotice('')
    try {
      const id = reportId(rep, text.split('\n'))
      const index: SavedIndex[] = (await chat().metaGet('reports:index')) || []
      if (index.some((x) => x.id === id) && !rep.missingResult) {
        const old = await chat().metaGet(`report:${id}`)
        if (old && old.text === reportBody) return setNotice('Báo cáo này đã được lưu.')
      }
      const savedAt = new Date().toISOString()
      await chat().metaSet(`report:${id}`, { id, rep: JSON.parse(JSON.stringify(rep)), source: text, text: reportBody, savedAt })
      const entry = { id, savedAt, date: rep.date, stationName: rep.stationName, profit: rep.totals.profit }
      const next = [entry, ...index.filter((x) => x.id !== id)].slice(0, 200)
      await chat().metaSet('reports:index', next)
      setSaved(next)
      setNotice('Đã lưu báo cáo.')
    } catch {
      setNotice('Không lưu được báo cáo.')
    }
  }
  async function copy() {
    setNotice('')
    try {
      await navigator.clipboard.writeText(reportBody)
      setNotice('Đã sao chép báo cáo')
    } catch {
      // trình duyệt từ chối Clipboard API (không có quyền / trang không được focus): thử cách cũ
      try {
        const ta = document.createElement('textarea')
        ta.value = reportBody
        ta.style.cssText = 'position:fixed;opacity:0'
        document.body.appendChild(ta)
        ta.select()
        const ok = document.execCommand('copy')
        ta.remove()
        setNotice(ok ? 'Đã sao chép báo cáo' : 'Không sao chép được, hãy thử lại.')
      } catch {
        setNotice('Không sao chép được, hãy thử lại.')
      }
    }
  }
  async function openSaved(s: SavedIndex) {
    const r = await chat().metaGet(`report:${s.id}`)
    if (!r) return
    setRep(r.rep)
    setError('')
    setNotice(`Báo cáo đã lưu lúc ${new Date(r.savedAt).toLocaleString('vi-VN')}.`)
    setStep('report')
  }
  async function doSend() {
    if (!sendTo) return
    setSending(true)
    setSendResult('')
    try {
      const m = await chat().send(sendTo, reportBody, null)
      const now = (await chat().messages(sendTo.id)).find((x: { id: string }) => x.id === m.id)
      setSendResult(now?.status === 'failed'
        ? `Chưa gửi được: ${String(reasonText(now.reason)).replace(/\.$/, '')}. Tin nằm trong cuộc trò chuyện, có nút Gửi lại.`
        : 'Đã gửi báo cáo. Nếu bạn bè đang offline, cuộc trò chuyện sẽ báo lỗi và có nút Gửi lại.')
      if (now?.status !== 'failed') setSendOpen(false)
    } catch (err) {
      setSendResult((err as Error).message || 'Không gửi được báo cáo.')
    } finally {
      setSending(false)
    }
  }
  const back = () => (step === 'station' ? onBack() : setStep('station'))

  return (
    <ModalDialog open={open} title={title} xwide back onClose={back}>
      <div className="cc-root">
        {step === 'station' && (
          <>
            <p className="cc-hint">Ngày {fmtDate(date)}. Chọn đài có kết quả dùng để tính (tin nhắn và nội dung giải mã được giữ nguyên).</p>
            <p className="cc-cfg"><strong>Khách hàng: {customer?.name || '(chưa chọn)'}</strong><span>{customer?.scoringRates ? 'Tính theo cấu hình giá riêng của khách này.' : 'Tính theo cấu hình giá mặc định.'}</span></p>
            <div className="cc-cards" role="radiogroup" aria-label="Đài tính toán">
              {stationIds.map((id) => (
                <button key={id} type="button" role="radio" className={`cc-card${selected === id ? ' on' : ''}`} aria-checked={selected === id} onClick={() => setSelected(id)}>
                  <span className="cc-ico">▦</span>
                  <span>Dùng kết quả {id === 'mb' ? 'Miền Bắc' : `đài ${nameFor(id)}`}</span>
                  {selected === id && <span className="cc-tick">✓</span>}
                </button>
              ))}
            </div>
            {error && <p className="cc-err">{error}</p>}
            <div className="cc-actions">
              <button type="button" className="tb-link" onClick={() => setStep('saved')}>Báo cáo đã lưu ({saved.length})</button>
              <button type="button" className="cc-big" disabled={!selected || loading} onClick={confirmStation}>{loading ? 'Đang tính...' : 'Xác nhận chọn đài'}</button>
            </div>
          </>
        )}

        {step === 'saved' && (
          <>
            {!saved.length && <p className="cc-hint">Chưa có báo cáo nào được lưu.</p>}
            {saved.map((s) => (
              <button key={s.id} type="button" className="cc-saved" onClick={() => openSaved(s)}>
                <strong>Đài {s.stationName} · {fmtDate(s.date)}</strong>
                <span>Lợi nhuận: {fmtProfit(s.profit)} · lưu {new Date(s.savedAt).toLocaleString('vi-VN')}</span>
              </button>
            ))}
          </>
        )}

        {step === 'report' && rep && (
          <>
            <div className="cc-head">
              <strong>Đài {rep.stationName}</strong>
              <span>Ngày {fmtDate(rep.date)}</span>
            </div>
            {error && <p className="cc-err">{error} {rep.missingResult && <button type="button" className="tb-link" onClick={confirmStation}>Thử lại</button>}</p>}
            <ol className="cc-items">
              {rep.groups.map((g: any, i: number) => (
                <li key={g.key} className="cc-item">
                  <span className="cc-n">{i + 1}</span>
                  <div>{groupLines(g, rep.missingResult).map((l: string, j: number) => <div key={j} className={j === 0 ? 'strong' : ''}>{l}</div>)}</div>
                </li>
              ))}
              {rep.other.stake ? (
                <li className="cc-item other">
                  <span className="cc-n">+</span>
                  <div>Kiểu đánh khác ({rep.other.kinds.join(', ')}): đánh {money(rep.other.stakeMoney)}{!rep.missingResult && <>, trúng {money(rep.other.winMoney)}</>} (đã tính vào tổng)</div>
                </li>
              ) : null}
              <li className="cc-item"><span className="cc-n">6</span><div className="strong">Tổng tiền khách đánh: {money(rep.totals.stake)}</div></li>
              <li className="cc-item"><span className="cc-n">7</span><div className="strong">Tổng tiền khách trúng: {rep.missingResult ? 'Chưa đủ dữ liệu' : money(rep.totals.won)}</div></li>
              <li className={`cc-item cc-profit${rep.totals.profit != null && rep.totals.profit < 0 ? ' neg' : ''}`}><span className="cc-n">8</span><div className="strong">Tổng lợi nhuận: {fmtProfit(rep.totals.profit)}</div></li>
            </ol>
            {rep.skipped.length > 0 && <p className="cc-warn">{rep.skipped.length} dòng cần kiểm tra chưa được tính: {rep.skipped.map((r: any) => r.value).join(', ')}. Sửa ở màn đối chiếu rồi tính lại.</p>}
            {notice && <p className="cc-note">{notice}</p>}
            <div className="cc-bar">
              <button type="button" className="cc-btn" onClick={save}>💾 Lưu</button>
              <button type="button" className="cc-btn" onClick={copy}>📋 Copy</button>
              <button type="button" className="cc-btn primary" onClick={() => { setSendOpen(true); setSendTo(null); setSendResult('') }}>✉ Gửi cho khách hàng</button>
            </div>

            {sendOpen && (
              <div className="cc-send" role="dialog" aria-label="Gửi cho khách hàng">
                <strong>Gửi cho khách hàng</strong>
                <div className="cc-friends">
                  {friends.map((f) => <button key={f.id} type="button" className={`cc-friend${sendTo?.id === f.id ? ' on' : ''}`} onClick={() => setSendTo(f)}>{f.name}</button>)}
                  {!friends.length && <span className="cc-hint">Chưa có cuộc trò chuyện nào.</span>}
                </div>
                <pre className="cc-preview">{reportBody}</pre>
                {sendResult && <p className="cc-note">{sendResult}</p>}
                <div className="cc-actions">
                  <button type="button" className="tb-link" onClick={() => setSendOpen(false)}>Huỷ</button>
                  <button type="button" className="cc-big" disabled={!sendTo || sending} onClick={doSend}>{sending ? 'Đang gửi...' : 'Gửi'}</button>
                </div>
              </div>
            )}
          </>
        )}
      </div>
    </ModalDialog>
  )
}
