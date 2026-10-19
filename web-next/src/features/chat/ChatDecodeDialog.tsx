'use client'
import './ChatDecodeDialog.css'
import { useEffect, useMemo, useState } from 'react'
import AppSelect from '@/components/AppSelect'
import ModalDialog from '@/components/ModalDialog'
import { api } from '@/lib/api'
import { today } from '@/lib/dates'
import { loadStations, regionOf, stationName, stationOptions, stationsOn } from '@/lib/lotteryStations'
import { decodeMessage } from '@/lib/messageParser'
import { useStations } from '@/lib/useStations'
import { useChatStore } from './chatStore'

// Đối chiếu tin nhắn gốc và nội dung giải mã (Tính toán trong khung chat). Mỗi tin đã chọn: bên trái bản GỐC (chỉ đọc),
// bên phải bản giải mã từng dòng, sửa được. Tin gốc không bao giờ bị đổi; bản đã sửa lưu riêng trên máy này (metaSet
// `decode:<id>`), mở lại vẫn còn. "Khôi phục" đưa một dòng về bản giải mã, "Giải mã lại" bỏ mọi chỗ sửa.
export interface DecodeWhere { date: string; station: string; customer: string }
type Line = { original: string; decoded: string; text: string; changed: boolean; unknown: boolean }
type Item = { id: string; original: string; lines: Line[] }
type Customer = { id: string; name: string }

export default function ChatDecodeDialog({
  open,
  messages,
  betTypes,
  kindSymbols,
  onClose,
  onUse,
  onCalc,
}: {
  open: boolean
  messages: { id: string; content: string }[]
  betTypes: string[]
  kindSymbols: unknown
  onClose: () => void
  onUse: (text: string, where: DecodeWhere) => void
  onCalc: (text: string, date: string, customerId: string) => void
}) {
  const [customers, setCustomers] = useState<Customer[]>([])
  const [customerId, setCustomerId] = useState('')
  const [needCustomer, setNeedCustomer] = useState(false)
  const [date, setDate] = useState(today())
  const [station, setStation] = useState('mb')
  const [items, setItems] = useState<Item[]>([])
  const [note, setNote] = useState('')
  useStations() // re-render when the station catalog arrives
  useEffect(() => { loadStations() }, [])

  const customerName = customers.find((c) => c.id === customerId)?.name || ''
  const stationChoices = stationOptions(date)
  // the chosen value must exist on that day (the schedule rotates by weekday)
  const stationValue = stationChoices.some((o) => o.value === station) ? station : 'mb'
  const dayHint = useMemo(() => {
    if (stationValue === 'mb') return ''
    const region = ['mt', 'mn'].includes(stationValue) ? stationValue : regionOf(stationValue).id
    const list = stationsOn(region, date)
    return list.length > 1 ? `Ngày này ${regionOf(region).name} quay ${list.length} đài: ${list.map(stationName).join(', ')}. Chọn một đài hoặc cả vùng.` : ''
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [stationValue, date, items])

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const decode = (content: string): any[] => decodeMessage(content, { betTypes, kindSymbols } as any)

  const key = messages.map((m) => m.id).join()
  useEffect(() => {
    if (!open) return
    let gone = false
    setNeedCustomer(false)
    api.get('/me/customers').then((r: { customers?: Customer[] }) => !gone && setCustomers(r.customers || []), () => !gone && setCustomers([]))
    ;(async () => {
      const built: Item[] = []
      for (const m of messages) {
        const lines: Line[] = decode(m.content).map((l) => ({ original: l.original, decoded: l.decoded, text: l.decoded, changed: l.changed, unknown: l.unknown }))
        const saved = await useChatStore.getState().metaGet(`decode:${m.id}`)
        // an edit only applies to the same original text
        if (saved && saved.original === m.content && Array.isArray(saved.lines) && saved.lines.length === lines.length) saved.lines.forEach((t: string, i: number) => (lines[i].text = t))
        built.push({ id: m.id, original: m.content, lines })
      }
      if (!gone) { setItems(built); setNote('') }
    })()
    return () => { gone = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, key])

  const edited = (l: Line) => l.text !== l.decoded
  const setLine = (n: number, i: number, text: string) =>
    setItems((cur) => cur.map((it, a) => (a !== n ? it : { ...it, lines: it.lines.map((l, b) => (b === i ? { ...l, text } : l)) })))
  function redo() {
    setItems((cur) => cur.map((it) => {
      const fresh = decode(it.original)
      return { ...it, lines: it.lines.map((l, i) => { const d = fresh[i]?.decoded ?? l.decoded; return { ...l, decoded: d, text: d } }) }
    }))
    setNote('Đã giải mã lại, các chỗ sửa đã bỏ (chưa lưu).')
  }
  async function save() {
    for (const it of items) {
      const any = it.lines.some(edited)
      await useChatStore.getState().metaSet(`decode:${it.id}`, any ? { original: it.original, lines: it.lines.map((l) => l.text) } : null)
    }
    setNote('Đã lưu bản sửa trên máy này. Tin nhắn gốc không bị đổi.')
  }
  const fullText = () => items.flatMap((it) => it.lines.map((l) => l.text)).filter((t) => t.trim()).join('\n')
  async function calc() {
    if (!customerId) return setNeedCustomer(true)
    await save()
    onCalc(fullText(), date, customerId)
  }
  function use() {
    if (!customerId) return setNeedCustomer(true)
    onUse(fullText(), { date, station: stationValue, customer: customerName })
  }

  return (
    <ModalDialog open={open} title="Đối chiếu tin nhắn" xwide back onClose={onClose}>
      <div className="dd-root">
        <p className="dd-hint">Bên trái là tin gốc (giữ nguyên), bên phải là nội dung giải mã. Sửa từng dòng nếu giải mã chưa đúng; dòng có dấu <strong>!</strong> cần kiểm tra.</p>
        <div className="dd-where">
          <label className="dd-customer">Khách hàng của số liệu này *
            <AppSelect value={customerId} onChange={(v) => { setCustomerId(v); setNeedCustomer(false) }} aria-label="Khách hàng">
              <option value="" disabled>Chọn khách hàng...</option>
              {customers.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </AppSelect>
          </label>
          <label>Ngày<input value={date} type="date" onChange={(e) => setDate(e.target.value)} /></label>
          <label className="dd-station">Đài
            <AppSelect value={stationValue} onChange={setStation} aria-label="Đài xổ số">
              {stationChoices.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
            </AppSelect>
          </label>
        </div>
        {needCustomer && <p className="dd-need">Hãy chọn khách hàng cho số liệu đã nhập trước khi tiếp tục.</p>}
        {dayHint && <p className="dd-hint">{dayHint}</p>}
        {items.map((it, n) => (
          <div key={it.id} className="dd-msg">
            <div className="dd-title">Tin {n + 1}</div>
            <div className="dd-head"><span>Tin gốc</span><span>Giải mã (sửa được)</span></div>
            {it.lines.map((l, i) => (
              <div key={i} className="dd-line">
                <div className="dd-orig">{l.original || ' '}</div>
                <div className="dd-dec">
                  <input value={l.text} type="text" aria-label={`Dòng ${i + 1} giải mã`} className={edited(l) ? 'edited' : ''} onChange={(e) => setLine(n, i, e.target.value)} />
                  {l.unknown && <span className="dd-flag" title="Có phần chưa nhận ra, hãy kiểm tra">!</span>}
                  {edited(l) && <button type="button" className="tb-link" onClick={() => setLine(n, i, l.decoded)}>Khôi phục</button>}
                </div>
              </div>
            ))}
          </div>
        ))}
        {note && <p className="dd-note">{note}</p>}
        <div className="dd-actions">
          <button type="button" className="tb-link" onClick={redo}>Giải mã lại</button>
          <button type="button" className="tb-link" onClick={save}>Lưu bản sửa</button>
          <button type="button" className="tb-link" onClick={use}>Dùng cho Nhập số</button>
          <button type="button" className="tb-link strong" onClick={calc}>Tính toán</button>
        </div>
      </div>
    </ModalDialog>
  )
}
