<!--
  Tổng kết tiền of ONE customer over the days on screen (Tính điểm), see scoringSummary.js:
    (1) Tiền khách gửi: total lô, total điểm, converted to đồng (per bet type);
    (2) Lô trúng: how many lô hit, which ones, the money;
    (3) Còn lại = (1) - (2), over the days that already have a lottery result.
  Figures hide behind "••••" while "Ẩn số liệu" is on (stores/mask.js).
  Props: days [{date, entries}], accountRates, customerRates, getResult(date, station)
-->
<script setup>
import { computed, ref } from 'vue'
import MaskedValue from './MaskedValue.vue'
import { betTypeLabel } from '../betTypes'
import { summarize } from '../scoringSummary'
import { stationName } from '../lotteryStations'

const props = defineProps({
  days: { type: Array, required: true },
  accountRates: { type: Object, required: true },
  customerRates: { type: Object, default: null },
  customerRegion: { type: String, default: null }, // 'mb' | 'mn' | null: the customer's own region (Đầu on a Miền Bắc result)
  getResult: { type: Function, required: true }, // (date, station) -> result | null | undefined
})

const s = computed(() => summarize(props.days, props.accountRates, props.customerRates, props.getResult, { customerRegion: props.customerRegion }))
const showWon = ref(false)
const nf = new Intl.NumberFormat('vi-VN')
const money = (n) => `${nf.format(Math.round(n))} đ`
const fmtDate = (iso) => iso.split('-').reverse().join('/')
const sign = (n) => (n > 0 ? '+' : '')
</script>

<template>
  <section class="sum" aria-label="Tổng kết tiền">
    <div class="tiles">
      <div class="tile">
        <span class="tile-label">(1) Tiền khách gửi</span>
        <strong class="tile-money"><MaskedValue :text="money(s.sent.money)" /></strong>
        <span class="tile-sub">
          <MaskedValue :text="`${nf.format(s.sent.lots)} lô`" />
          <template v-if="s.sent.points"> · <MaskedValue :text="`${nf.format(s.sent.points)} điểm`" /></template>
        </span>
      </div>
      <div class="tile">
        <span class="tile-label">(2) Tiền khách trúng</span>
        <strong class="tile-money"><MaskedValue :text="money(s.won.money)" /></strong>
        <span class="tile-sub">
          <MaskedValue :text="`${nf.format(s.won.lots)} lô trúng`" />
          <template v-if="s.won.hits !== s.won.lots"> · <MaskedValue :text="`${nf.format(s.won.hits)} lần`" /></template>
        </span>
      </div>
      <div class="tile tile-rest">
        <span class="tile-label">(3) Còn lại = (1) − (2)</span>
        <strong class="tile-money" :class="s.remaining > 0 ? 'pos' : s.remaining < 0 ? 'neg' : ''">
          <MaskedValue :text="`${sign(s.remaining)}${money(s.remaining)}`" />
        </strong>
        <span class="tile-sub">{{ s.remaining > 0 ? 'Còn lại sau khi trả khách' : s.remaining < 0 ? 'Phải trả khách thêm' : '' }}</span>
      </div>
    </div>
    <p class="sum-note">
      Tính trên <MaskedValue :text="`${nf.format(s.settled.lots)} lô, ${money(s.settled.money)}`" /> khách gửi ở các ngày đã có kết quả.
      <template v-if="s.pending.lots">
        Chưa có kết quả: <MaskedValue :text="`${nf.format(s.pending.lots)} lô, ${money(s.pending.money)}`" /> (chưa tính).
      </template>
    </p>
  </section>
</template>

<style scoped>
.sum {
  margin-bottom: 14px;
  padding: 16px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
}
.tiles {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
  gap: 10px;
}
.tile {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 14px 16px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 12px;
}
.tile-rest {
  border-color: var(--primary);
}
.tile-label {
  font-size: 13.5px;
  color: var(--muted);
}
.tile-money {
  font-size: 26px;
  line-height: 1.15;
  font-variant-numeric: tabular-nums;
}
.tile-sub {
  min-height: 18px;
  font-size: 13px;
  color: var(--muted);
}
.sum-note {
  margin: 10px 0 0;
  font-size: 12.5px;
  font-weight: 400;
  color: var(--muted);
}
.sum-more {
  margin-top: 10px;
  font-size: 14px;
}
.sum-more summary {
  cursor: pointer;
  font-weight: 600;
}
.sum-table {
  width: 100%;
  margin-top: 6px;
  font-size: 13px;
  border-collapse: collapse;
}
.sum-table th,
.sum-table td {
  padding: 4px 8px 4px 0;
  text-align: left;
  border-bottom: 1px solid var(--border);
}
.sum-table th {
  font-weight: 600;
  color: var(--muted);
}
.won-list {
  margin: 6px 0 0;
  padding: 0;
  list-style: none;
  max-height: 260px;
  overflow-y: auto;
}
.won-list li {
  display: grid;
  grid-template-columns: 64px 1fr auto;
  gap: 8px;
  align-items: baseline;
  padding: 5px 0;
  font-size: 13.5px;
  border-bottom: 1px solid var(--border);
}
.won-num {
  font-weight: 700;
}
.won-meta {
  color: var(--muted);
  font-size: 12.5px;
}
.pos {
  color: var(--success-text);
}
.neg {
  color: var(--danger-text);
}
</style>
