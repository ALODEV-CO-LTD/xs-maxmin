<!--
  /admin/settings - package price overrides + bank transfer config.
  API: GET /admin/settings -> { [key]: stringValue }  (arbitrary key/value store)
       PUT /admin/settings body { [key]: value }  (upsert one or more keys)
       DELETE /admin/settings body { keys: [...] }  (restore a key to its hard-coded default)

  Two dedicated forms read/write this same generic store:
    - `package_price_<wireValue>` overriding the hard-coded prices in
      package_plans.dart (see resolvedPriceVnd).
    - `bank_name` / `bank_account_number` / `bank_account_holder` /
      `bank_bin` - the account customers transfer to when buying a package
      (read by GET /me/payment-info, shown on PackagesView.vue's "Thông tin
      chuyển khoản" card, and by `bank_bin` used to render a VietQR
      quick-pay code there so banking apps can auto-fill the transfer).
  Any other keys present are listed read/write generically below so
  nothing in the store is hidden - this includes `lottery_payout_rate`,
  which has its own dedicated page at /admin/scoring-settings
  (ScoringSettingsView.vue) using this same generic store, so it still
  shows up here too if someone looks.
-->
<script setup>
import AppSelect from '../../components/AppSelect.vue'
import { ref, onMounted, computed } from 'vue'
import { api, ApiError } from '../../api'

const packages = [
  { wire: '1m', label: '1 tháng', default: 99000 },
  { wire: '3m', label: '3 tháng', default: 269000 },
  { wire: '6m', label: '6 tháng', default: 499000 },
  { wire: '12m', label: '12 tháng', default: 899000 },
]

// BIN codes per Napas/VietQR - used both to identify the bank on transfers
// and to render the VietQR quick-pay code on PackagesView.vue.
const BANKS = [
  { bin: '970436', name: 'Vietcombank' },
  { bin: '970415', name: 'VietinBank' },
  { bin: '970418', name: 'BIDV' },
  { bin: '970405', name: 'Agribank' },
  { bin: '970422', name: 'MB Bank' },
  { bin: '970407', name: 'Techcombank' },
  { bin: '970416', name: 'ACB' },
  { bin: '970432', name: 'VPBank' },
  { bin: '970423', name: 'TPBank' },
  { bin: '970403', name: 'Sacombank' },
  { bin: '970437', name: 'HDBank' },
  { bin: '970443', name: 'SHB' },
  { bin: '970431', name: 'Eximbank' },
  { bin: '970426', name: 'MSB' },
  { bin: '970448', name: 'OCB' },
  { bin: '970440', name: 'SeABank' },
  { bin: '970441', name: 'VIB' },
  { bin: '970449', name: 'LienVietPostBank (LPBank)' },
  { bin: '970429', name: 'SCB' },
  { bin: '970406', name: 'DongA Bank' },
]

const bankFields = [
  { key: 'bank_account_number', label: 'Số tài khoản' },
  { key: 'bank_account_holder', label: 'Chủ tài khoản' },
]

const loading = ref(true)
const error = ref('')
const saved = ref(false)
const saving = ref(false)

const raw = ref({})
const prices = ref({})
const bank = ref({ bank_bin: '', bank_account_number: '', bank_account_holder: '' })
const bankSaving = ref(false)
const bankSaved = ref(false)
const bankError = ref('')

function keyFor(wire) {
  return `package_price_${wire}`
}

async function load() {
  loading.value = true
  error.value = ''
  saved.value = false
  try {
    raw.value = await api.get('/admin/settings')
    const p = {}
    for (const pkg of packages) {
      p[pkg.wire] = raw.value[keyFor(pkg.wire)] ?? ''
    }
    prices.value = p
    bank.value = {
      bank_bin: raw.value.bank_bin ?? '',
      bank_account_number: raw.value.bank_account_number ?? '',
      bank_account_holder: raw.value.bank_account_holder ?? '',
    }
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể tải cài đặt'
  } finally {
    loading.value = false
  }
}

const bankKeys = ['bank_name', 'bank_bin', 'bank_account_number', 'bank_account_holder']

const otherKeys = computed(() =>
  Object.keys(raw.value).filter((k) => !packages.some((p) => keyFor(p.wire) === k) && !bankKeys.includes(k)),
)

async function saveBank() {
  bankSaving.value = true
  bankSaved.value = false
  bankError.value = ''
  try {
    const acc = bank.value.bank_account_number.trim()
    const holder = bank.value.bank_account_holder.trim()
    const bin = bank.value.bank_bin
    if (!bin || !acc || !holder) {
      bankError.value = 'Vui lòng chọn ngân hàng và nhập đầy đủ số tài khoản, chủ tài khoản'
      return
    }
    const bankName = BANKS.find((b) => b.bin === bin)?.name || ''
    raw.value = await api.put('/admin/settings', {
      bank_bin: bin,
      bank_name: bankName,
      bank_account_number: acc,
      bank_account_holder: holder,
    })
    bankSaved.value = true
  } catch (err) {
    bankError.value = err instanceof ApiError ? err.message : 'Không thể lưu cấu hình thanh toán'
  } finally {
    bankSaving.value = false
  }
}

async function save() {
  saving.value = true
  saved.value = false
  error.value = ''
  try {
    const body = {}
    const keysToDelete = []
    for (const pkg of packages) {
      const val = String(prices.value[pkg.wire] ?? '').trim()
      if (val === '') {
        if (raw.value[keyFor(pkg.wire)] !== undefined) keysToDelete.push(keyFor(pkg.wire))
        continue
      }
      body[keyFor(pkg.wire)] = val
    }
    if (Object.keys(body).length > 0) {
      raw.value = await api.put('/admin/settings', body)
    }
    if (keysToDelete.length > 0) {
      raw.value = await api.del('/admin/settings', { keys: keysToDelete })
    }
    saved.value = true
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không thể lưu cài đặt'
  } finally {
    saving.value = false
  }
}

async function resetPrice(wire) {
  prices.value[wire] = ''
  await save()
}

onMounted(load)
</script>

<template>
  <div class="page">
    <h1 class="page-title">Cài đặt hệ thống</h1>
    <p class="page-subtitle">Ghi đè giá gói dịch vụ (để trống để dùng giá mặc định)</p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="saved" class="alert alert-success">Đã lưu cài đặt</div>
    <div v-if="loading">Đang tải...</div>

    <template v-else>
      <h2 style="margin-top: 0">Tài khoản nhận thanh toán</h2>
      <p class="page-subtitle">
        Khách hàng sẽ thấy thông tin này (và mã QR chuyển khoản nhanh) ở trang Gói dịch vụ khi mua gói.
      </p>
      <form class="card" @submit.prevent="saveBank">
        <div v-if="bankError" class="alert alert-error">{{ bankError }}</div>
        <div v-if="bankSaved" class="alert alert-success">Đã lưu cấu hình thanh toán</div>

        <div class="field">
          <label>Ngân hàng</label>
          <AppSelect v-model="bank.bank_bin">
            <option value="" disabled>-- Chọn ngân hàng --</option>
            <option v-for="b in BANKS" :key="b.bin" :value="b.bin">{{ b.name }}</option>
          </AppSelect>
        </div>
        <div v-for="f in bankFields" :key="f.key" class="field">
          <label>{{ f.label }}</label>
          <input v-model="bank[f.key]" type="text" :placeholder="f.label" />
        </div>

        <button class="btn btn-primary btn-block" type="submit" :disabled="bankSaving">
          {{ bankSaving ? 'Đang lưu...' : 'Lưu cấu hình thanh toán' }}
        </button>
      </form>

      <h2>Giá gói dịch vụ</h2>
      <form class="card" @submit.prevent="save">
      <div v-for="pkg in packages" :key="pkg.wire" class="field">
        <label>{{ pkg.label }} (mặc định {{ pkg.default.toLocaleString('vi-VN') }} đ)</label>
        <div style="display: flex; gap: 8px">
          <input
            v-model="prices[pkg.wire]"
            type="number"
            min="0"
            :placeholder="String(pkg.default)"
          />
          <button
            v-if="raw[keyFor(pkg.wire)] !== undefined"
            type="button"
            class="btn btn-ghost btn-sm"
            @click="resetPrice(pkg.wire)"
          >
            Dùng mặc định
          </button>
        </div>
      </div>

      <button class="btn btn-primary btn-block" type="submit" :disabled="saving">
        {{ saving ? 'Đang lưu...' : 'Lưu cài đặt' }}
      </button>
    </form>
    </template>

    <template v-if="!loading && otherKeys.length > 0">
      <h2 style="margin-top: 32px">Các khoá cài đặt khác</h2>
      <div class="card" style="padding: 0">
        <table class="table">
          <thead>
            <tr>
              <th>Khoá</th>
              <th>Giá trị</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="k in otherKeys" :key="k">
              <td>{{ k }}</td>
              <td>{{ raw[k] }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </div>
</template>
