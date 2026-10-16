<!--
  Tính toán từ tin nhắn: Chọn đài → Kết quả tính toán (8 mục) → Lưu / Copy / Gửi cho khách hàng.
    Chọn đài   một thẻ lớn cho mỗi đài quay trong ngày ("Dùng kết quả đài X"); không tự chọn, chọn lại thì bỏ đài cũ.
    Kết quả    tính bằng kết quả ĐÚNG đài + ngày của tài khoản (GET /lottery-results); chưa có kết quả thì báo và cho thử lại,
               tuyệt đối không dùng số mẫu hay đài khác. 8 mục: lô, đầu đuôi, 3 càng, xiên 2, xiên 3, tổng tiền đánh, tổng
               tiền trúng, tổng lợi nhuận (= đánh − trúng).
    Lưu        trên máy này (chat.metaSet `report:<id>` + danh sách `reports:index`); id theo nội dung nên không trùng bản ghi.
    Gửi        xem trước rồi gửi đúng nội dung báo cáo qua chat mã hoá; kết quả gửi lấy từ trạng thái tin thật.
  Props: open, text (các dòng đã giải mã), date, friends. Emits: close, back (về màn đối chiếu)
-->
<script setup>
import { computed, ref, watch } from 'vue'
import { api } from '../api'
import { useChatStore } from '../e2ee/chat'
import { buildReport, groupLines, money, reportId, reportText } from '../chatReport'
import { stationName as nameOf, stationsOn } from '../lotteryStations'
import { parseMessage } from '../messageParser'
import { kindSymbolsFor, typesOf } from '../scoringConfig'
import AppSelect from './AppSelect.vue'
import ModalDialog from './ModalDialog.vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  text: { type: String, default: '' },
  date: { type: String, default: '' },
  friends: { type: Array, default: () => [] },
  customerId: { type: String, default: '' }, // khách hàng đã chọn ở màn đối chiếu
})
const emit = defineEmits(['close', 'back'])
const chat = useChatStore()

const step = ref('station') // 'station' | 'report' | 'saved'
const selected = ref('') // id đài (QUẢNG NAM = 'mt-quangnam', ...); rỗng = chưa chọn
const loading = ref(false)
const error = ref('')
const rep = ref(null)
const notice = ref('')
const customers = ref([])
const customer = computed(() => customers.value.find((c) => c.id === props.customerId) || null)
const rates = ref({})
const saved = ref([])
const sendOpen = ref(false)
const sendTo = ref(null)
const sending = ref(false)
const sendResult = ref('')

const stationIds = computed(() => ['mb', ...stationsOn('mt', props.date), ...stationsOn('mn', props.date)])
const nameFor = (id) => (id === 'mb' ? 'Miền Bắc' : nameOf(id))
const title = computed(() => (step.value === 'station' ? 'Chọn đài tính toán' : step.value === 'saved' ? 'Báo cáo đã lưu' : 'Kết quả tính toán'))
const fmtDate = (d) => String(d || '').split('-').reverse().join('/')

watch(
  () => props.open,
  async (o) => {
    if (!o) return
    step.value = 'station'
    selected.value = ''
    error.value = notice.value = sendResult.value = ''
    rep.value = null
    sendOpen.value = false
    try {
      const r = await api.get('/me/scoring-settings')
      rates.value = r.rates || {}
    } catch { /* mặc định */ }
    try {
      customers.value = (await api.get('/me/customers')).customers || []
    } catch { customers.value = [] }
    saved.value = (await chat.metaGet('reports:index')) || []
  },
)

async function confirmStation() {
  if (!selected.value) return
  loading.value = true
  error.value = ''
  try {
    let result = null
    try {
      result = (await api.get(`/lottery-results?date=${props.date}&station=${encodeURIComponent(selected.value)}`)).result
    } catch (err) {
      error.value = err.message || 'Không lấy được kết quả xổ số'
      return
    }
    const own = customer.value?.scoringRates || null
    const region = selected.value === 'mb' ? 'mb' : selected.value.startsWith('mt') ? 'mt' : 'mn'
    const { rows } = parseMessage(props.text, { betTypes: typesOf(rates.value).length ? typesOf(rates.value) : ['de', 'lo'], kindSymbols: kindSymbolsFor(rates.value, own, region) })
    if (!rows.length) {
      error.value = 'Không tìm thấy số liệu hợp lệ trong các tin đã chọn.'
      return
    }
    rep.value = buildReport({ rows, result, station: selected.value, stationName: nameFor(selected.value), customerName: customer.value?.name || '', date: props.date, accountRates: rates.value, customerRates: own })
    step.value = 'report'
    if (rep.value.missingResult) error.value = `Chưa có kết quả đài ${nameFor(selected.value)} ngày ${fmtDate(props.date)}. Hãy lưu kết quả ở tab Nhập kết quả rồi bấm Thử lại.`
  } finally {
    loading.value = false
  }
}
const text = computed(() => (rep.value ? reportText(rep.value) : ''))

async function save() {
  notice.value = ''
  try {
    const id = reportId(rep.value, props.text.split('\n'))
    const index = (await chat.metaGet('reports:index')) || []
    if (index.some((x) => x.id === id) && !rep.value.missingResult) {
      const old = await chat.metaGet(`report:${id}`)
      if (old && old.text === text.value) return void (notice.value = 'Báo cáo này đã được lưu.')
    }
    const savedAt = new Date().toISOString()
    await chat.metaSet(`report:${id}`, { id, rep: JSON.parse(JSON.stringify(rep.value)), source: props.text, text: text.value, savedAt })
    const entry = { id, savedAt, date: rep.value.date, stationName: rep.value.stationName, profit: rep.value.totals.profit }
    const next = [entry, ...index.filter((x) => x.id !== id)].slice(0, 200)
    await chat.metaSet('reports:index', next)
    saved.value = next
    notice.value = 'Đã lưu báo cáo.'
  } catch {
    notice.value = 'Không lưu được báo cáo.'
  }
}
async function copy() {
  notice.value = ''
  try {
    await navigator.clipboard.writeText(text.value)
    notice.value = 'Đã sao chép báo cáo'
  } catch {
    // trình duyệt từ chối Clipboard API (không có quyền / trang không được focus): thử cách cũ
    try {
      const ta = document.createElement('textarea')
      ta.value = text.value
      ta.style.cssText = 'position:fixed;opacity:0'
      document.body.appendChild(ta)
      ta.select()
      const ok = document.execCommand('copy')
      ta.remove()
      notice.value = ok ? 'Đã sao chép báo cáo' : 'Không sao chép được, hãy thử lại.'
    } catch {
      notice.value = 'Không sao chép được, hãy thử lại.'
    }
  }
}
async function openSaved(s) {
  const r = await chat.metaGet(`report:${s.id}`)
  if (!r) return
  rep.value = r.rep
  error.value = ''
  notice.value = `Báo cáo đã lưu lúc ${new Date(r.savedAt).toLocaleString('vi-VN')}.`
  step.value = 'report'
}
async function doSend() {
  if (!sendTo.value) return
  sending.value = true
  sendResult.value = ''
  try {
    const m = await chat.send(sendTo.value, text.value, null)
    const now = (await chat.messages(sendTo.value.id)).find((x) => x.id === m.id)
    sendResult.value = now?.status === 'failed' ? `Chưa gửi được: ${String(chat.reasonText(now.reason)).replace(/\.$/, '')}. Tin nằm trong cuộc trò chuyện, có nút Gửi lại.` : 'Đã gửi báo cáo. Nếu bạn bè đang offline, cuộc trò chuyện sẽ báo lỗi và có nút Gửi lại.'
    if (now?.status !== 'failed') sendOpen.value = false
  } catch (err) {
    sendResult.value = err.message || 'Không gửi được báo cáo.'
  } finally {
    sending.value = false
  }
}
const back = () => (step.value === 'station' ? emit('back') : (step.value = 'station'))
const fmtProfit = (n) => (n == null ? 'Chưa đủ dữ liệu' : money(n))
</script>

<template>
  <ModalDialog :open="open" :title="title" xwide back @close="back">
    <!-- 1. Chọn đài -->
    <template v-if="step === 'station'">
      <p class="cc-hint">Ngày {{ fmtDate(date) }}. Chọn đài có kết quả dùng để tính (tin nhắn và nội dung giải mã được giữ nguyên).</p>
      <p class="cc-cfg"><strong>Khách hàng: {{ customer?.name || '(chưa chọn)' }}</strong><span>{{ customer?.scoringRates ? 'Tính theo cấu hình giá riêng của khách này.' : 'Tính theo cấu hình giá mặc định.' }}</span></p>
      <div class="cc-cards" role="radiogroup" aria-label="Đài tính toán">
        <button
          v-for="id in stationIds"
          :key="id"
          type="button"
          role="radio"
          class="cc-card"
          :class="{ on: selected === id }"
          :aria-checked="selected === id"
          @click="selected = id"
        >
          <span class="cc-ico">▦</span>
          <span>Dùng kết quả {{ id === 'mb' ? 'Miền Bắc' : `đài ${nameFor(id)}` }}</span>
          <span v-if="selected === id" class="cc-tick">✓</span>
        </button>
      </div>
      <p v-if="error" class="cc-err">{{ error }}</p>
      <div class="cc-actions">
        <button type="button" class="tb-link" @click="step = 'saved'">Báo cáo đã lưu ({{ saved.length }})</button>
        <button type="button" class="cc-big" :disabled="!selected || loading" @click="confirmStation">{{ loading ? 'Đang tính...' : 'Xác nhận chọn đài' }}</button>
      </div>
    </template>

    <!-- 3. Báo cáo đã lưu -->
    <template v-else-if="step === 'saved'">
      <p v-if="!saved.length" class="cc-hint">Chưa có báo cáo nào được lưu.</p>
      <button v-for="s in saved" :key="s.id" type="button" class="cc-saved" @click="openSaved(s)">
        <strong>Đài {{ s.stationName }} · {{ fmtDate(s.date) }}</strong>
        <span>Lợi nhuận: {{ fmtProfit(s.profit) }} · lưu {{ new Date(s.savedAt).toLocaleString('vi-VN') }}</span>
      </button>
    </template>

    <!-- 2. Kết quả tính toán -->
    <template v-else-if="rep">
      <div class="cc-head">
        <strong>Đài {{ rep.stationName }}</strong>
        <span>Ngày {{ fmtDate(rep.date) }}</span>
      </div>
      <p v-if="error" class="cc-err">{{ error }} <button v-if="rep.missingResult" type="button" class="tb-link" @click="confirmStation">Thử lại</button></p>
      <ol class="cc-items">
        <li v-for="(g, i) in rep.groups" :key="g.key" class="cc-item">
          <span class="cc-n">{{ i + 1 }}</span>
          <div>
            <div v-for="(l, j) in groupLines(g, rep.missingResult)" :key="j" :class="{ strong: j === 0 }">{{ l }}</div>
          </div>
        </li>
        <li v-if="rep.other.stake" class="cc-item other">
          <span class="cc-n">+</span>
          <div>Kiểu đánh khác ({{ rep.other.kinds.join(', ') }}): đánh {{ money(rep.other.stakeMoney) }}<template v-if="!rep.missingResult">, trúng {{ money(rep.other.winMoney) }}</template> (đã tính vào tổng)</div>
        </li>
        <li class="cc-item"><span class="cc-n">6</span><div class="strong">Tổng tiền khách đánh: {{ money(rep.totals.stake) }}</div></li>
        <li class="cc-item"><span class="cc-n">7</span><div class="strong">Tổng tiền khách trúng: {{ rep.missingResult ? 'Chưa đủ dữ liệu' : money(rep.totals.won) }}</div></li>
        <li class="cc-item cc-profit" :class="{ neg: rep.totals.profit != null && rep.totals.profit < 0 }"><span class="cc-n">8</span><div class="strong">Tổng lợi nhuận: {{ fmtProfit(rep.totals.profit) }}</div></li>
      </ol>
      <p v-if="rep.skipped.length" class="cc-warn">{{ rep.skipped.length }} dòng cần kiểm tra chưa được tính: {{ rep.skipped.map((r) => r.value).join(', ') }}. Sửa ở màn đối chiếu rồi tính lại.</p>
      <p v-if="notice" class="cc-note">{{ notice }}</p>
      <div class="cc-bar">
        <button type="button" class="cc-btn" @click="save">💾 Lưu</button>
        <button type="button" class="cc-btn" @click="copy">📋 Copy</button>
        <button type="button" class="cc-btn primary" @click="sendOpen = true; sendTo = null; sendResult = ''">✉ Gửi cho khách hàng</button>
      </div>

      <div v-if="sendOpen" class="cc-send" role="dialog" aria-label="Gửi cho khách hàng">
        <strong>Gửi cho khách hàng</strong>
        <div class="cc-friends">
          <button v-for="f in friends" :key="f.id" type="button" class="cc-friend" :class="{ on: sendTo?.id === f.id }" @click="sendTo = f">{{ f.name }}</button>
          <span v-if="!friends.length" class="cc-hint">Chưa có cuộc trò chuyện nào.</span>
        </div>
        <pre class="cc-preview">{{ text }}</pre>
        <p v-if="sendResult" class="cc-note">{{ sendResult }}</p>
        <div class="cc-actions">
          <button type="button" class="tb-link" @click="sendOpen = false">Huỷ</button>
          <button type="button" class="cc-big" :disabled="!sendTo || sending" @click="doSend">{{ sending ? 'Đang gửi...' : 'Gửi' }}</button>
        </div>
      </div>
    </template>
  </ModalDialog>
</template>

<style scoped>
.cc-hint { margin: 0 0 12px; font-size: 14px; color: #6b716c; }
.cc-cfg { display: flex; flex-direction: column; gap: 2px; margin: 0 0 14px; font-size: 14px; }
.cc-cfg span { color: #6b716c; font-size: 13px; }
.cc-cards { display: flex; flex-direction: column; gap: 12px; margin-bottom: 14px; }
.cc-card { position: relative; display: flex; align-items: center; gap: 12px; width: 100%; min-height: 64px; padding: 14px 16px; font: inherit; font-size: 17px; text-align: left; color: #000; background: #fff; border: 1px solid #d9e8dd; border-radius: 14px; cursor: pointer; }
.cc-card.on { border: 2px solid #16a34a; background: #f0fdf4; }
.cc-ico { font-size: 22px; color: #16a34a; }
.cc-tick { margin-left: auto; width: 26px; height: 26px; display: grid; place-items: center; color: #fff; background: #16a34a; border-radius: 50%; }
.cc-err { color: #b91c1c; font-size: 14px; }
.cc-warn { color: #b45309; font-size: 14px; }
.cc-note { color: #15803d; font-size: 14px; margin: 8px 0 0; }
.cc-actions { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin-top: 8px; }
.cc-big { min-height: 48px; padding: 0 22px; font: inherit; font-weight: 600; color: #fff; background: #16a34a; border: 0; border-radius: 12px; cursor: pointer; }
.cc-big:disabled { opacity: 0.5; cursor: default; }
.cc-head { display: flex; flex-direction: column; gap: 2px; margin-bottom: 10px; }
.cc-head span { color: #6b716c; font-size: 14px; }
.cc-items { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 8px; }
.cc-item { display: flex; gap: 10px; padding: 10px 12px; border: 1px solid #d9e8dd; border-radius: 12px; font-size: 14.5px; }
.cc-item .strong { font-weight: 700; }
.cc-item.other { background: #f6faf7; }
.cc-n { flex: none; width: 24px; height: 24px; display: grid; place-items: center; font-size: 13px; font-weight: 700; color: #16a34a; border: 1px solid #16a34a; border-radius: 50%; }
.cc-profit { border: 2px solid #16a34a; background: #f0fdf4; font-size: 17px; }
.cc-profit.neg { border-color: #b91c1c; background: #fef2f2; color: #b91c1c; }
.cc-bar { position: sticky; bottom: 0; display: flex; gap: 8px; padding: 10px 0 4px; background: #fff; }
.cc-btn { flex: 1 1 0; min-width: 0; min-height: 48px; padding: 0 8px; font: inherit; font-size: 15px; font-weight: 600; color: #000; background: #fff; border: 1px solid #16a34a; border-radius: 12px; cursor: pointer; }
.cc-btn.primary { color: #fff; background: #16a34a; }
.cc-saved { display: flex; flex-direction: column; gap: 2px; width: 100%; padding: 10px 12px; margin-bottom: 8px; font: inherit; text-align: left; background: #fff; border: 1px solid #d9e8dd; border-radius: 12px; cursor: pointer; }
.cc-saved span { font-size: 13px; color: #6b716c; }
.cc-send { margin-top: 12px; padding: 12px; border: 1px solid #16a34a; border-radius: 12px; display: flex; flex-direction: column; gap: 8px; }
.cc-friends { display: flex; flex-wrap: wrap; gap: 6px; }
.cc-friend { padding: 8px 14px; font: inherit; background: #fff; border: 1px solid #d9e8dd; border-radius: 999px; cursor: pointer; }
.cc-friend.on { color: #fff; background: #16a34a; border-color: #16a34a; }
.cc-preview { margin: 0; padding: 10px; font: inherit; font-size: 14px; white-space: pre-wrap; background: #f6faf7; border-radius: 8px; max-height: 240px; overflow: auto; }
.tb-link { background: none; border: 0; color: #16a34a; font-size: 15px; cursor: pointer; padding: 4px; }
</style>
