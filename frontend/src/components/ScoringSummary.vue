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
  getResult: { type: Function, required: true }, // (date, station) -> result | null | undefined
})

const s = computed(() => summarize(props.days, props.accountRates, props.customerRates, props.getResult))
const showWon = ref(false)
const nf = new Intl.NumberFormat('vi-VN')
const money = (n) => `${nf.format(Math.round(n))} đ`
const fmtDate = (iso) => iso.split('-').reverse().join('/')
const sign = (n) => (n > 0 ? '+' : '')
</script>

<template>
  <section class="card sum" aria-label="Tổng kết tiền">
    <div class="sum-block">
      <h3>(1) Tiền khách gửi</h3>
      <div class="sum-big">
        <span><MaskedValue :text="`${nf.format(s.sent.lots)} lô`" /></span>
        <span v-if="s.sent.points"><MaskedValue :text="`${nf.format(s.sent.points)} điểm`" /></span>
        <strong><MaskedValue :text="money(s.sent.money)" /></strong>
      </div>
      <table v-if="s.byType.length" class="sum-table">
        <thead>
          <tr><th>Loại</th><th>Số lô</th><th>Tổng</th><th>Thành tiền</th></tr>
        </thead>
        <tbody>
          <tr v-for="t in s.byType" :key="t.key">
            <td>{{ betTypeLabel(t.key) }}</td>
            <td><MaskedValue :text="nf.format(t.lots)" /></td>
            <td>
              <MaskedValue :text="t.unit === 'point' ? `${nf.format(t.amount)} điểm × ${nf.format(t.pointValue)} đ` : 'tính theo tiền'" />
            </td>
            <td><MaskedValue :text="money(t.money)" /></td>
          </tr>
        </tbody>
      </table>
    </div>

    <div class="sum-block">
      <h3>(2) Lô trúng <span class="sum-note">(các ngày đã có kết quả)</span></h3>
      <div class="sum-big">
        <span><MaskedValue :text="`${nf.format(s.won.lots)} lô trúng`" /></span>
        <span v-if="s.won.hits !== s.won.lots"><MaskedValue :text="`${nf.format(s.won.hits)} lần trúng`" /></span>
        <strong><MaskedValue :text="money(s.won.money)" /></strong>
      </div>
      <button v-if="s.won.items.length" type="button" class="btn btn-ghost btn-sm" @click="showWon = !showWon">
        {{ showWon ? 'Ẩn danh sách lô trúng' : 'Xem các lô trúng' }}
      </button>
      <ul v-if="showWon" class="won-list">
        <li v-for="(w, i) in s.won.items" :key="i">
          <span class="won-num"><MaskedValue :text="w.number" /></span>
          <span class="won-meta">{{ betTypeLabel(w.type) }} · {{ fmtDate(w.date) }}<template v-if="w.station && w.station !== 'mb'"> · {{ stationName(w.station) }}</template><template v-if="w.hits > 1"> · trúng {{ w.hits }} lần</template></span>
          <strong><MaskedValue :text="money(w.money)" /></strong>
        </li>
      </ul>
      <p v-else-if="!s.won.items.length" class="sum-note">Chưa có lô nào trúng.</p>
    </div>

    <div class="sum-block sum-rest">
      <h3>(3) Còn lại = (1) − (2)</h3>
      <div class="sum-big">
        <strong :class="s.remaining > 0 ? 'pos' : s.remaining < 0 ? 'neg' : ''">
          <MaskedValue :text="`${sign(s.remaining)}${money(s.remaining)}`" />
        </strong>
      </div>
      <p class="sum-note">
        Tính trên <MaskedValue :text="`${nf.format(s.settled.lots)} lô, ${money(s.settled.money)}`" /> khách gửi ở các ngày đã có kết quả.
        <template v-if="s.pending.lots">
          Chưa có kết quả: <MaskedValue :text="`${nf.format(s.pending.lots)} lô, ${money(s.pending.money)}`" /> (chưa tính).
        </template>
        Dương là tiền còn lại sau khi trả khách.
      </p>
    </div>
  </section>
</template>

<style scoped>
.sum {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 16px 24px;
  margin-bottom: 12px;
  padding: 16px;
}
.sum-block h3 {
  margin: 0 0 6px;
  font-size: 15px;
}
.sum-big {
  display: flex;
  flex-wrap: wrap;
  align-items: baseline;
  gap: 4px 14px;
  margin-bottom: 8px;
  font-size: 15px;
}
.sum-big strong {
  font-size: 22px;
}
.sum-note {
  font-size: 12.5px;
  font-weight: 400;
  color: var(--muted);
}
.sum-table {
  width: 100%;
  font-size: 13px;
  border-collapse: collapse;
}
.sum-table th,
.sum-table td {
  padding: 3px 6px 3px 0;
  text-align: left;
  border-bottom: 1px solid var(--border);
}
.sum-table th {
  font-weight: 600;
  color: var(--muted);
}
.won-list {
  margin: 8px 0 0;
  padding: 0;
  list-style: none;
  max-height: 220px;
  overflow-y: auto;
}
.won-list li {
  display: grid;
  grid-template-columns: 56px 1fr auto;
  gap: 8px;
  align-items: baseline;
  padding: 4px 0;
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
