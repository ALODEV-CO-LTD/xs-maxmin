<!--
  Đối chiếu tin nhắn gốc và nội dung giải mã (Tính toán trong khung chat).
  Mỗi tin đã chọn: bên trái bản GỐC (chỉ đọc), bên phải bản giải mã từng dòng, sửa được. Tin gốc không bao giờ bị đổi;
  bản đã sửa lưu riêng trên máy này (chat.metaSet `decode:<id>`), mở lại vẫn còn. "Khôi phục" đưa một dòng về bản giải mã,
  "Giải mã lại" bỏ mọi chỗ sửa. "Dùng cho Nhập số" chuyển nội dung đã sửa sang trang Nhập số.
  Props: open, messages [{id, content}], betTypes, kindSymbols. Emits: close, use(text, { date, station }), calc(text, date, customerId). Đài/ngày: chọn đài xổ số của ngày (Miền Bắc, cả vùng, hoặc một đài trong các đài quay hôm đó).
-->
<script setup>
import { computed, onMounted, reactive, ref, watch } from 'vue'
import { api } from '../api'
import { today } from '../dates'
import { loadStations, regionOf, stationName, stationOptions, stationsOn } from '../lotteryStations'
import AppSelect from './AppSelect.vue'
import { decodeMessage } from '../messageParser'
import { useChatStore } from '../e2ee/chat'
import ModalDialog from './ModalDialog.vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  messages: { type: Array, default: () => [] },
  betTypes: { type: Array, default: () => ['de', 'lo'] },
  kindSymbols: { type: Object, default: null },
})
const emit = defineEmits(['close', 'use', 'calc'])
const chat = useChatStore()

// Khách hàng (trong tài khoản) mà số liệu này thuộc về: BẮT BUỘC chọn trước khi dùng cho Nhập số hoặc tính toán.
const customers = ref([])
const customerId = ref('')
const customerName = computed(() => customers.value.find((c) => c.id === customerId.value)?.name || '')
async function loadCustomers() {
  try {
    customers.value = (await api.get('/me/customers')).customers || []
  } catch {
    customers.value = []
  }
}
const needCustomer = ref(false)
const date = ref(today())
const station = ref('mb')
onMounted(loadStations)
watch(() => props.open, (o) => { if (o) { needCustomer.value = false; loadCustomers() } })
const stationChoices = computed(() => stationOptions(date.value))
// the chosen value must exist on that day (the schedule rotates by weekday)
watch(date, () => {
  if (!stationChoices.value.some((o) => o.value === station.value)) station.value = 'mb'
})
const dayHint = computed(() => {
  const code = station.value
  if (code === 'mb') return ''
  const region = ['mt', 'mn'].includes(code) ? code : regionOf(code).id
  const list = stationsOn(region, date.value)
  return list.length > 1 ? `Ngày này ${regionOf(region).name} quay ${list.length} đài: ${list.map(stationName).join(', ')}. Chọn một đài hoặc cả vùng.` : ''
})

const items = reactive([]) // { id, original, lines: [{ original, decoded, text, changed, unknown }] }
const note = ref('')

const decode = (content) => decodeMessage(content, { betTypes: props.betTypes, kindSymbols: props.kindSymbols })

async function build() {
  items.splice(0)
  note.value = ''
  for (const m of props.messages) {
    const lines = decode(m.content).map((l) => ({ original: l.original, decoded: l.decoded, text: l.decoded, changed: l.changed, unknown: l.unknown }))
    const saved = await chat.metaGet(`decode:${m.id}`)
    // an edit only applies to the same original text
    if (saved && saved.original === m.content && Array.isArray(saved.lines) && saved.lines.length === lines.length) {
      saved.lines.forEach((t, i) => (lines[i].text = t))
    }
    items.push({ id: m.id, original: m.content, lines })
  }
}
watch(() => [props.open, props.messages.map((m) => m.id).join()], () => props.open && build(), { immediate: true })

const edited = (l) => l.text !== l.decoded
function restore(l) {
  l.text = l.decoded
}
function redo() {
  for (const it of items) {
    const fresh = decode(it.original)
    it.lines.forEach((l, i) => {
      l.decoded = fresh[i]?.decoded ?? l.decoded
      l.text = l.decoded
    })
  }
  note.value = 'Đã giải mã lại, các chỗ sửa đã bỏ (chưa lưu).'
}
async function save() {
  for (const it of items) {
    const any = it.lines.some(edited)
    await chat.metaSet(`decode:${it.id}`, any ? { original: it.original, lines: it.lines.map((l) => l.text) } : null)
  }
  note.value = 'Đã lưu bản sửa trên máy này. Tin nhắn gốc không bị đổi.'
}
// Tính toán: lưu bản sửa rồi sang màn chọn đài (quay lại vẫn còn nguyên chỗ đã sửa).
async function calc() {
  if (!customerId.value) return void (needCustomer.value = true)
  await save()
  emit('calc', items.flatMap((it) => it.lines.map((l) => l.text)).filter((t) => t.trim()).join('\n'), date.value, customerId.value)
}
function use() {
  if (!customerId.value) return void (needCustomer.value = true)
  emit('use', items.flatMap((it) => it.lines.map((l) => l.text)).filter((t) => t.trim()).join('\n'), { date: date.value, station: station.value, customer: customerName.value })
}
</script>

<template>
  <ModalDialog :open="open" title="Đối chiếu tin nhắn" xwide back @close="emit('close')">
    <p class="dd-hint">Bên trái là tin gốc (giữ nguyên), bên phải là nội dung giải mã. Sửa từng dòng nếu giải mã chưa đúng; dòng có dấu <strong>!</strong> cần kiểm tra.</p>
    <div class="dd-where">
      <label class="dd-customer">Khách hàng của số liệu này *
        <AppSelect v-model="customerId" aria-label="Khách hàng" @update:model-value="needCustomer = false">
          <option value="" disabled>Chọn khách hàng...</option>
          <option v-for="c in customers" :key="c.id" :value="c.id">{{ c.name }}</option>
        </AppSelect>
      </label>
      <label>Ngày<input v-model="date" type="date" /></label>
      <label class="dd-station">Đài
        <AppSelect v-model="station" aria-label="Đài xổ số">
          <option v-for="o in stationChoices" :key="o.value" :value="o.value">{{ o.label }}</option>
        </AppSelect>
      </label>
    </div>
    <p v-if="needCustomer" class="dd-need">Hãy chọn khách hàng cho số liệu đã nhập trước khi tiếp tục.</p>
    <p v-if="dayHint" class="dd-hint">{{ dayHint }}</p>
    <div v-for="(it, n) in items" :key="it.id" class="dd-msg">
      <div class="dd-title">Tin {{ n + 1 }}</div>
      <div class="dd-head"><span>Tin gốc</span><span>Giải mã (sửa được)</span></div>
      <div v-for="(l, i) in it.lines" :key="i" class="dd-line">
        <div class="dd-orig">{{ l.original || ' ' }}</div>
        <div class="dd-dec">
          <input v-model="l.text" type="text" :aria-label="`Dòng ${i + 1} giải mã`" :class="{ edited: edited(l) }" />
          <span v-if="l.unknown" class="dd-flag" title="Có phần chưa nhận ra, hãy kiểm tra">!</span>
          <button v-if="edited(l)" type="button" class="tb-link" @click="restore(l)">Khôi phục</button>
        </div>
      </div>
    </div>
    <p v-if="note" class="dd-note">{{ note }}</p>
    <div class="dd-actions">
      <button type="button" class="tb-link" @click="redo">Giải mã lại</button>
      <button type="button" class="tb-link" @click="save">Lưu bản sửa</button>
      <button type="button" class="tb-link" @click="use">Dùng cho Nhập số</button>
      <button type="button" class="tb-link strong" @click="calc">Tính toán</button>
    </div>
  </ModalDialog>
</template>

<style scoped>
.dd-hint { margin: 0 0 12px; font-size: 14px; color: #6b716c; }
.dd-where { display: flex; flex-wrap: wrap; gap: 12px; margin-bottom: 10px; }
.dd-where label { display: flex; flex-direction: column; gap: 4px; font-size: 13px; font-weight: 600; }
.dd-where input { height: 38px; padding: 0 10px; border: 1px solid #16a34a; border-radius: 8px; font: inherit; }
.dd-station { flex: 1; min-width: 220px; }
.dd-customer { flex: 1 1 100%; max-width: 360px; }
.dd-need { margin: 0 0 10px; color: #b91c1c; font-size: 14px; font-weight: 600; }
.dd-msg { margin-bottom: 14px; padding: 10px; border: 1px solid #d9e8dd; border-radius: 10px; }
.dd-title { font-weight: 700; margin-bottom: 6px; }
.dd-head, .dd-line { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
.dd-head { font-size: 12.5px; font-weight: 600; color: #6b716c; margin-bottom: 4px; }
.dd-line { align-items: center; margin-bottom: 6px; }
.dd-orig { padding: 8px 10px; background: #f6faf7; border-radius: 8px; white-space: pre-wrap; overflow-wrap: anywhere; min-height: 20px; }
.dd-dec { display: flex; align-items: center; gap: 6px; min-width: 0; }
.dd-dec input { flex: 1; min-width: 0; height: 38px; padding: 0 10px; border: 1px solid #16a34a; border-radius: 8px; font: inherit; }
.dd-dec input.edited { background: #f0fdf4; }
.dd-flag { color: #b45309; font-weight: 800; }
.dd-note { color: #15803d; font-size: 14px; }
.dd-actions { display: flex; justify-content: flex-end; gap: 16px; padding-top: 6px; }
.tb-link { background: none; border: 0; color: #000; font-size: 15px; cursor: pointer; padding: 4px; }
.tb-link.strong { color: #16a34a; font-weight: 600; }
@media (max-width: 640px) {
  .dd-head, .dd-line { grid-template-columns: 1fr; gap: 4px; }
  .dd-head span:nth-child(2) { display: none; }
}
</style>
