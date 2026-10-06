<!--
  "Thêm loại đánh" dialog for Cấu hình tính điểm. One place to fill in everything a
  bet type needs, grouped into labelled sections instead of loose inputs in a table row:
    1. Tên loại đánh
    2. Tỉ lệ ăn      (payout multiple: điểm ra = điểm vào × tỉ lệ)
    3. So khớp       (how many trailing digits are compared)
    4. Đối chiếu với (which prize groups of the lottery result count)
  It only collects and validates; the parent adds the row (and the user still has to
  press "Lưu cài đặt" there to store it).
  Props:  open, existingKeys (string[]), digitOptions (number[]), tiers ([{key,label}])
  Emits:  close, add({ key, rate, digits, tiers })
-->
<script setup>
import { computed, nextTick, ref, watch } from 'vue'

const props = defineProps({
  open: { type: Boolean, default: false },
  existingKeys: { type: Array, default: () => [] },
  digitOptions: { type: Array, default: () => [1, 2, 3, 4, 5] },
  tiers: { type: Array, required: true },
})
const emit = defineEmits(['close', 'add'])

const box = ref(null)
const nameInput = ref(null)
const name = ref('')
const rate = ref('')
const digits = ref(2)
const picked = ref([])
const submitted = ref(false)
let lastFocus = null

// What gets stored as the type's key: lower case, spaces become dashes.
const key = computed(() => name.value.trim().toLowerCase().replace(/\s+/g, '-'))

const nameError = computed(() => {
  if (!key.value) return 'Nhập tên loại đánh'
  if (props.existingKeys.includes(key.value)) return `Loại "${key.value}" đã có trong danh sách`
  return ''
})
const rateError = computed(() => {
  const n = Number(rate.value)
  if (rate.value === '' || rate.value === null || !Number.isFinite(n) || n <= 0) return 'Nhập tỉ lệ ăn lớn hơn 0'
  return ''
})
const tierError = computed(() => (picked.value.length === 0 ? 'Chọn ít nhất một giải để đối chiếu' : ''))
const valid = computed(() => !nameError.value && !rateError.value && !tierError.value)

watch(
  () => props.open,
  async (open) => {
    if (open) {
      lastFocus = document.activeElement
      name.value = ''
      rate.value = ''
      digits.value = props.digitOptions.includes(2) ? 2 : props.digitOptions[0]
      // Start with every prize group ticked: the inclusive default, easy to narrow down.
      picked.value = props.tiers.map((t) => t.key)
      submitted.value = false
      await nextTick()
      nameInput.value?.focus()
    } else if (lastFocus && typeof lastFocus.focus === 'function') {
      lastFocus.focus()
      lastFocus = null
    }
  },
)

function toggle(tierKey) {
  const i = picked.value.indexOf(tierKey)
  if (i === -1) picked.value.push(tierKey)
  else picked.value.splice(i, 1)
}
const pickAll = () => (picked.value = props.tiers.map((t) => t.key))
const pickOnly = (tierKey) => (picked.value = [tierKey])
const pickNone = () => (picked.value = [])

function submit() {
  submitted.value = true
  if (!valid.value) return
  emit('add', { key: key.value, rate: Number(rate.value), digits: Number(digits.value), tiers: [...picked.value] })
}

function onKey(e) {
  if (e.key === 'Escape') {
    e.preventDefault()
    emit('close')
  } else if (e.key === 'Tab') {
    // keep focus inside the dialog
    const items = [...box.value.querySelectorAll('input, select, button:not([disabled])')]
    if (!items.length) return
    const first = items[0]
    const last = items[items.length - 1]
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault()
      last.focus()
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault()
      first.focus()
    }
  }
}
</script>

<template>
  <Teleport to="body">
    <div v-if="open" class="bt-overlay" @mousedown.self="emit('close')" @keydown="onKey">
      <form ref="box" class="bt-box" role="dialog" aria-modal="true" aria-labelledby="bt-title" novalidate @submit.prevent="submit">
        <header class="bt-head">
          <h2 id="bt-title" class="bt-title">Thêm loại đánh</h2>
          <p class="bt-sub">Điền thông tin cho loại đánh mới. Sau khi thêm, nhớ bấm "Lưu cài đặt" để áp dụng.</p>
        </header>

        <section class="bt-section">
          <label class="bt-label" for="bt-name">1. Tên loại đánh</label>
          <input
            id="bt-name"
            ref="nameInput"
            v-model="name"
            type="text"
            class="bt-input"
            placeholder="Ví dụ: xiên 2, 3 càng, bao lô 4"
            autocomplete="off"
          />
          <p v-if="key && !nameError" class="bt-hint">Mã lưu: <strong>{{ key }}</strong></p>
          <p v-if="submitted && nameError" class="bt-error">{{ nameError }}</p>
        </section>

        <div class="bt-row">
          <section class="bt-section">
            <label class="bt-label" for="bt-rate">2. Tỉ lệ ăn</label>
            <input id="bt-rate" v-model="rate" type="number" min="1" step="any" class="bt-input" placeholder="Ví dụ: 70" inputmode="decimal" />
            <p class="bt-hint">Điểm ra = điểm vào × tỉ lệ</p>
            <p v-if="submitted && rateError" class="bt-error">{{ rateError }}</p>
          </section>

          <section class="bt-section">
            <label class="bt-label" for="bt-digits">3. So khớp</label>
            <select id="bt-digits" v-model.number="digits" class="bt-input">
              <option v-for="d in digitOptions" :key="d" :value="d">{{ d }} số cuối</option>
            </select>
            <p class="bt-hint">Số khách đánh khớp với bấy nhiêu chữ số cuối của giải</p>
          </section>
        </div>

        <section class="bt-section">
          <div class="bt-label-row">
            <span class="bt-label">4. Đối chiếu với</span>
            <span class="bt-quick">
              <button type="button" class="bt-link" @click="pickAll">Tất cả</button>
              <button type="button" class="bt-link" @click="pickOnly('dacBiet')">Chỉ Đặc biệt</button>
              <button type="button" class="bt-link" @click="pickNone">Bỏ chọn</button>
            </span>
          </div>
          <div class="bt-tiers">
            <label v-for="t in tiers" :key="t.key" class="bt-tier" :class="{ on: picked.includes(t.key) }">
              <input type="checkbox" :checked="picked.includes(t.key)" @change="toggle(t.key)" />
              {{ t.label }}
            </label>
          </div>
          <p v-if="submitted && tierError" class="bt-error">{{ tierError }}</p>
        </section>

        <footer class="bt-actions">
          <button type="button" class="btn btn-secondary" @click="emit('close')">Huỷ</button>
          <button type="submit" class="btn btn-primary">Thêm loại đánh</button>
        </footer>
      </form>
    </div>
  </Teleport>
</template>

<style scoped>
.bt-overlay {
  position: fixed;
  inset: 0;
  z-index: 100;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  background: var(--overlay);
  overflow-y: auto;
}
.bt-box {
  width: 100%;
  max-width: 520px;
  max-height: calc(100vh - 32px);
  overflow-y: auto;
  padding: 24px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 16px;
  box-shadow: var(--shadow-lg);
}
.bt-head {
  margin-bottom: 18px;
}
.bt-title {
  margin: 0 0 4px;
  font-size: 18px;
  line-height: 1.3;
}
.bt-sub {
  margin: 0;
  font-size: 13px;
  line-height: 1.45;
  color: var(--text-secondary);
}
.bt-section {
  margin-bottom: 18px;
  min-width: 0;
}
.bt-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}
.bt-label,
.bt-label-row {
  display: block;
  margin-bottom: 6px;
  font-size: 14px;
  font-weight: 700;
}
.bt-label-row {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: 8px;
  flex-wrap: wrap;
}
.bt-label-row .bt-label {
  margin: 0;
}
.bt-input {
  width: 100%;
  height: 42px;
  padding: 0 12px;
  font-size: 15px;
  color: var(--text);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  box-sizing: border-box;
}
.bt-input:hover {
  border-color: var(--input-border-hover);
}
.bt-input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.bt-hint {
  margin: 6px 0 0;
  font-size: 12px;
  color: var(--text-secondary);
}
.bt-error {
  margin: 6px 0 0;
  font-size: 13px;
  color: var(--danger-text);
}
.bt-quick {
  display: inline-flex;
  gap: 12px;
}
.bt-link {
  padding: 0;
  font: inherit;
  font-size: 13px;
  font-weight: 600;
  color: var(--primary);
  background: none;
  border: 0;
  cursor: pointer;
}
.bt-link:hover {
  text-decoration: underline;
}
.bt-tiers {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 8px;
}
.bt-tier {
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 40px;
  padding: 0 12px;
  font-size: 14px;
  cursor: pointer;
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.bt-tier.on {
  border-color: var(--primary);
  background: color-mix(in srgb, var(--primary) 12%, var(--surface));
}
.bt-tier input {
  width: 16px;
  height: 16px;
  flex: none;
  accent-color: var(--primary);
}
.bt-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 8px;
}
.bt-actions .btn {
  min-height: 40px;
  padding: 0 18px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
}
@media (max-width: 480px) {
  .bt-box {
    padding: 18px;
  }
  .bt-row {
    grid-template-columns: 1fr;
    gap: 0;
  }
  .bt-actions {
    flex-direction: column-reverse;
  }
  .bt-actions .btn {
    width: 100%;
  }
}
</style>
