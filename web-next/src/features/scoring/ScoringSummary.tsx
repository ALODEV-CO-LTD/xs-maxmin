'use client'
import './ScoringSummary.css'
import { useMemo } from 'react'
import MaskedValue from '@/components/MaskedValue'
import { summarize } from '@/lib/scoringSummary'

// Tổng kết tiền của MỘT khách trên các ngày đang hiện (Tính điểm), xem lib/scoringSummary.js:
//   (1) Tiền khách gửi: tổng lô, tổng điểm, đổi ra đồng (theo từng kiểu đánh);
//   (2) Lô trúng: bao nhiêu lô trúng, tiền trúng;
//   (3) Còn lại = (1) - (2), trên các ngày đã có kết quả xổ số.
// Số liệu thành "••••" khi bật "Ẩn số liệu" (lib/maskStore.js).
export interface ScoringSummaryProps {
  days: { date: string; entries: any[] }[]
  accountRates: any
  customerRates?: any
  customerRegion?: string | null // 'mb' | 'mn' | null: vùng của khách (Đầu trên kết quả Miền Bắc)
  getResult: (date: string, station: string) => any // kết quả | null | undefined
}

const nf = new Intl.NumberFormat('vi-VN')
const money = (n: number) => `${nf.format(Math.round(n))} đ`
const sign = (n: number) => (n > 0 ? '+' : '')

export default function ScoringSummary({ days, accountRates, customerRates = null, customerRegion = null, getResult }: ScoringSummaryProps) {
  // getResult đọc bộ nhớ đệm đổi dần: màn cha tạo hàm mới mỗi khi bộ nhớ đổi nên tính lại theo nó.
  const s = useMemo(
    () => summarize(days, accountRates, customerRates, getResult, { customerRegion }),
    [days, accountRates, customerRates, getResult, customerRegion],
  )
  return (
    <section className="sum scoring-sum" aria-label="Tổng kết tiền">
      <div className="tiles">
        <div className="tile">
          <span className="tile-label">(1) Tiền khách gửi</span>
          <strong className="tile-money"><MaskedValue text={money(s.sent.money)} /></strong>
          <span className="tile-sub">
            <MaskedValue text={`${nf.format(s.sent.lots)} lô`} />
            {s.sent.points ? <> · <MaskedValue text={`${nf.format(s.sent.points)} điểm`} /></> : null}
          </span>
        </div>
        <div className="tile">
          <span className="tile-label">(2) Tiền khách trúng</span>
          <strong className="tile-money"><MaskedValue text={money(s.won.money)} /></strong>
          <span className="tile-sub">
            <MaskedValue text={`${nf.format(s.won.lots)} lô trúng`} />
            {s.won.hits !== s.won.lots ? <> · <MaskedValue text={`${nf.format(s.won.hits)} lần`} /></> : null}
          </span>
        </div>
        <div className="tile tile-rest">
          <span className="tile-label">(3) Còn lại = (1) − (2)</span>
          <strong className={`tile-money ${s.remaining > 0 ? 'pos' : s.remaining < 0 ? 'neg' : ''}`}>
            <MaskedValue text={`${sign(s.remaining)}${money(s.remaining)}`} />
          </strong>
          <span className="tile-sub">{s.remaining > 0 ? 'Còn lại sau khi trả khách' : s.remaining < 0 ? 'Phải trả khách thêm' : ''}</span>
        </div>
      </div>
      <p className="sum-note">
        Tính trên <MaskedValue text={`${nf.format(s.settled.lots)} lô, ${money(s.settled.money)}`} /> khách gửi ở các ngày đã có kết quả.
        {s.pending.lots ? <> Chưa có kết quả: <MaskedValue text={`${nf.format(s.pending.lots)} lô, ${money(s.pending.money)}`} /> (chưa tính).</> : null}
      </p>
    </section>
  )
}
