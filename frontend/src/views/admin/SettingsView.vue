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
import { useRoute, useRouter } from 'vue-router'
import { api, ApiError } from '../../api'
import { useAuthStore } from '../../stores/auth'

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
    maxIds.value = raw.value.max_virtual_ids ?? ''
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

const bankKeys = ['bank_name', 'bank_bin', 'bank_account_number', 'bank_account_holder', 'max_virtual_ids']

// Cap on Mã ID per customer account (settings.max_virtual_ids, default 5).
const maxIds = ref('')
const maxIdsSaving = ref(false)
const maxIdsSaved = ref(false)
const maxIdsError = ref('')

async function saveMaxIds() {
  maxIdsSaving.value = true
  maxIdsSaved.value = false
  maxIdsError.value = ''
  try {
    raw.value = await api.put('/admin/settings', { max_virtual_ids: String(maxIds.value).trim() || '5' })
    maxIds.value = raw.value.max_virtual_ids ?? ''
    maxIdsSaved.value = true
  } catch (err) {
    maxIdsError.value = err instanceof ApiError ? err.message : 'Không thể lưu giới hạn ID ảo'
  } finally {
    maxIdsSaving.value = false
  }
}

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

// Recent security events (failed logins, lockouts, session revocations, wipes)
const events = ref([])
const eventsError = ref('')
const EVENT_LABELS = {
  login_failed: 'Đăng nhập sai',
  login_locked: 'Khoá tạm đăng nhập',
  session_revoked: 'Thu hồi phiên',
  data_wiped: 'Xoá dữ liệu',
}

async function loadEvents() {
  eventsError.value = ''
  try {
    events.value = (await api.get('/admin/security-events?limit=50')).events || []
  } catch (err) {
    eventsError.value = err instanceof ApiError ? err.message : 'Không thể tải nhật ký bảo mật'
  }
}

// A staff account may hold only one of these rights (A07): the settings forms need
// settings.manage, the security log needs security.view.
const auth = useAuthStore()
const canSettings = auth.can('settings.manage')
const canSecurity = auth.can('security.view')
if (canSettings) onMounted(load)
else loading.value = false
if (canSecurity) onMounted(loadEvents)

const route = useRoute()
const router = useRouter()
const TABS = computed(() => [
  ...(canSettings
    ? [
        { key: 'payment', label: 'Thanh toán' },
        { key: 'prices', label: 'Giá gói' },
        { key: 'limits', label: 'Giới hạn ID' },
      ]
    : []),
  ...(canSecurity ? [{ key: 'security', label: 'Nhật ký bảo mật' }] : []),
  ...(canSettings && otherKeys.value.length > 0 ? [{ key: 'other', label: 'Khoá khác' }] : []),
])
const tab = ref(route.query.tab)
const activeTab = computed(() => (TABS.value.some((t) => t.key === tab.value) ? tab.value : TABS.value[0]?.key))
function selectTab(key) {
  tab.value = key
  router.replace({ query: { ...route.query, tab: key } })
}
function onTabKey(e) {
  const list = TABS.value
  const i = list.findIndex((t) => t.key === activeTab.value)
  const next = e.key === 'ArrowRight' ? i + 1 : e.key === 'ArrowLeft' ? i - 1 : null
  if (next === null) return
  e.preventDefault()
  const t = list[(next + list.length) % list.length]
  selectTab(t.key)
  document.getElementById(`set-tab-${t.key}`)?.focus()
}
</script>

<template>
  <div class="page">
    <h1 class="page-title">Cài đặt hệ thống</h1>
    <p class="page-subtitle">Thanh toán, giá gói, giới hạn tài khoản và nhật ký bảo mật</p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="saved" class="alert alert-success">Đã lưu cài đặt</div>
    <div v-if="loading">Đang tải...</div>

    <div v-if="!loading && TABS.length > 0" class="set-tabs" role="tablist" aria-label="Mục cài đặt" @keydown="onTabKey">
      <button
        v-for="t in TABS"
        :id="`set-tab-${t.key}`"
        :key="t.key"
        type="button"
        role="tab"
        class="set-tab"
        :class="{ active: activeTab === t.key }"
        :aria-selected="activeTab === t.key"
        :tabindex="activeTab === t.key ? 0 : -1"
        @click="selectTab(t.key)"
      >
        {{ t.label }}
      </button>
    </div>

    <template v-if="!loading && canSettings">
      <div v-show="activeTab === 'payment'" role="tabpanel">
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
      </div>

      <div v-show="activeTab === 'limits'" role="tabpanel">
      <h2 style="margin-top: 0">Giới hạn ID ảo</h2>
      <p class="page-subtitle">Số Mã ID (ID ảo) tối đa mỗi tài khoản khách hàng được tạo. Mặc định 5.</p>
      <form class="card" @submit.prevent="saveMaxIds">
        <div v-if="maxIdsError" class="alert alert-error">{{ maxIdsError }}</div>
        <div v-if="maxIdsSaved" class="alert alert-success">Đã lưu giới hạn ID ảo</div>
        <div class="field">
          <label>Số ID tối đa mỗi tài khoản (1-100)</label>
          <input v-model="maxIds" type="number" min="1" max="100" placeholder="5" />
        </div>
        <button class="btn btn-primary btn-block" type="submit" :disabled="maxIdsSaving">
          {{ maxIdsSaving ? 'Đang lưu...' : 'Lưu giới hạn' }}
        </button>
      </form>
      </div>

      <div v-show="activeTab === 'prices'" role="tabpanel">
      <h2 style="margin-top: 0">Giá gói dịch vụ</h2>
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
      </div>
    </template>

    <template v-if="canSecurity && activeTab === 'security'">
    <h2 style="margin-top: 0">Nhật ký bảo mật gần đây</h2>
    <p class="page-subtitle">Không ghi mật khẩu hay token.</p>
    <div v-if="eventsError" class="alert alert-error">{{ eventsError }}</div>
    <div class="card" style="padding: 0">
      <div v-if="events.length === 0" style="padding: 16px">Chưa có sự kiện nào.</div>
      <table v-else class="table">
        <thead>
          <tr>
            <th>Thời gian</th>
            <th>Sự kiện</th>
            <th>Tài khoản</th>
            <th>IP</th>
            <th>Chi tiết</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="e in events" :key="e.id">
            <td>{{ new Date(e.createdAt).toLocaleString('vi-VN') }}</td>
            <td>{{ EVENT_LABELS[e.type] || e.type }}</td>
            <td>{{ e.username || '-' }}</td>
            <td>{{ e.ip || '-' }}</td>
            <td>{{ e.detail || '' }}</td>
          </tr>
        </tbody>
      </table>
    </div>

    </template>

    <template v-if="canSettings && !loading && otherKeys.length > 0 && activeTab === 'other'">
      <h2 style="margin-top: 0">Các khoá cài đặt khác</h2>
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

<style scoped>
.set-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 20px;
}
.set-tab {
  flex: 1 0 auto;
  min-height: 44px;
  padding: 0 20px;
  font: inherit;
  font-size: 15px;
  font-weight: 600;
  color: var(--text-secondary);
  white-space: nowrap;
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  cursor: pointer;
}
.set-tab:hover {
  color: var(--text-primary);
  border-color: var(--primary);
}
.set-tab.active {
  color: var(--on-primary);
  background: var(--primary);
  border-color: var(--primary);
}
.set-tab:focus-visible {
  outline: 2px solid var(--primary);
  outline-offset: 2px;
}
</style>
