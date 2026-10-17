<!--
  /admin/settings - package price overrides + bank transfer config.
  API: GET /admin/settings -> { [key]: stringValue }  (arbitrary key/value store)
       PUT /admin/settings body { [key]: value }  (upsert one or more keys)
       DELETE /admin/settings body { keys: [...] }  (restore a key to its hard-coded default)

  Package catalog (add / edit / hide / delete) lives in its own table:
    GET/POST /admin/packages, PATCH/DELETE /admin/packages/:code.
  Dedicated form on this same generic store:
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
import AppButton from '../../components/AppButton.vue'
import AppSelect from '../../components/AppSelect.vue'
import { ref, onMounted, computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api, ApiError } from '../../api'
import { useAuthStore } from '../../stores/auth'
import { showConfirm } from '../../confirm'
import SecurityPolicyView from './SecurityPolicyView.vue'
import AppVersionPanel from '../../components/AppVersionPanel.vue'
import BackupsView from './BackupsView.vue'

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
const bank = ref({ bank_bin: '', bank_account_number: '', bank_account_holder: '' })
// Each form only shows its values; "Sửa" unlocks it, "Lưu" / "Huỷ" lock it again.
const editBank = ref(false)
const editMax = ref(false)
const editPrices = ref(false)
const bankSaving = ref(false)
const bankSaved = ref(false)
const bankError = ref('')

async function load() {
  loading.value = true
  error.value = ''
  saved.value = false
  try {
    raw.value = await api.get('/admin/settings')
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
    editMax.value = false
  } catch (err) {
    maxIdsError.value = err instanceof ApiError ? err.message : 'Không thể lưu giới hạn ID ảo'
  } finally {
    maxIdsSaving.value = false
  }
}

// Internal one-time markers set by the server; not settings, so never listed.
const INTERNAL_KEYS = ['unread_epoch', 'e2ee_friend_chat_purged', 'perm_split_maintenance']
const otherKeys = computed(() =>
  Object.keys(raw.value).filter(
    (k) => !k.startsWith('package_price_') && !k.startsWith('app_') && !bankKeys.includes(k) && !INTERNAL_KEYS.includes(k),
  ),
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
    editBank.value = false
  } catch (err) {
    bankError.value = err instanceof ApiError ? err.message : 'Không thể lưu cấu hình thanh toán'
  } finally {
    bankSaving.value = false
  }
}

// ---- Package catalog (add / edit / hide / delete) ----
const packages = ref([])
const pkgError = ref('')
const pkgNotice = ref('')
const pkgBusy = ref('')
const pkgEditing = ref('') // code being edited, or 'new'
const pkgForm = ref({ label: '', durationDays: '', priceVnd: '' })

function formatVnd(v) {
  return Number(v).toLocaleString('vi-VN') + ' đ'
}
function formatDuration(d) {
  if (d % 365 === 0) return `${d} ngày (${d / 365} năm)`
  if (d % 30 === 0) return `${d} ngày (${d / 30} tháng)`
  return `${d} ngày`
}

async function loadPackages() {
  pkgError.value = ''
  try {
    packages.value = (await api.get('/admin/packages')).packages
  } catch (err) {
    pkgError.value = err instanceof ApiError ? err.message : 'Không tải được danh sách gói'
  }
}

function startNewPackage() {
  pkgForm.value = { label: '', durationDays: '', priceVnd: '' }
  pkgEditing.value = 'new'
  pkgNotice.value = ''
}
function startEditPackage(p) {
  pkgForm.value = { label: p.label, durationDays: String(p.durationDays), priceVnd: String(p.priceVnd) }
  pkgEditing.value = p.type
  pkgNotice.value = ''
}
function cancelPackage() {
  pkgEditing.value = ''
}

async function savePackage() {
  const body = {
    label: pkgForm.value.label.trim(),
    durationDays: Number(pkgForm.value.durationDays),
    priceVnd: Number(pkgForm.value.priceVnd),
  }
  pkgBusy.value = pkgEditing.value
  pkgError.value = ''
  try {
    if (pkgEditing.value === 'new') await api.post('/admin/packages', body)
    else await api.patch(`/admin/packages/${pkgEditing.value}`, body)
    pkgNotice.value = pkgEditing.value === 'new' ? 'Đã thêm gói' : 'Đã lưu gói (giá mới chỉ áp dụng cho yêu cầu mua sau này)'
    pkgEditing.value = ''
    await loadPackages()
  } catch (err) {
    pkgError.value = err instanceof ApiError ? err.message : 'Không lưu được gói'
  } finally {
    pkgBusy.value = ''
  }
}

async function togglePackage(p) {
  pkgBusy.value = p.type
  pkgError.value = ''
  try {
    await api.patch(`/admin/packages/${p.type}`, { active: !p.active })
    pkgNotice.value = p.active ? `Đã ẩn gói ${p.label} (người dùng không còn thấy để mua)` : `Đã hiện lại gói ${p.label}`
    await loadPackages()
  } catch (err) {
    pkgError.value = err instanceof ApiError ? err.message : 'Không cập nhật được gói'
  } finally {
    pkgBusy.value = ''
  }
}

async function removePackage(p) {
  const used = p.usage.users + p.usage.requests + p.usage.transactions > 0
  if (used) {
    pkgError.value = `Gói "${p.label}" đã có tài khoản hoặc giao dịch sử dụng nên không xoá được. Hãy ẩn gói để ngừng bán.`
    return
  }
  if (!(await showConfirm({ title: 'Xoá gói', message: `Xoá gói "${p.label}"?`, confirmText: 'Xoá', danger: true }))) return
  pkgBusy.value = p.type
  pkgError.value = ''
  try {
    await api.del(`/admin/packages/${p.type}`)
    pkgNotice.value = `Đã xoá gói ${p.label}`
    await loadPackages()
  } catch (err) {
    pkgError.value = err instanceof ApiError ? err.message : 'Không xoá được gói'
  } finally {
    pkgBusy.value = ''
  }
}

// Recent security events (failed logins, lockouts, session revocations, wipes)
const events = ref([])
const eventsError = ref('')
const EVENT_LABELS = {
  login_failed: 'Đăng nhập sai',
  login_locked: 'Khoá tạm đăng nhập',
  session_revoked: 'Thu hồi phiên',
  data_wiped: 'Xoá dữ liệu',
  app_version_changed: 'Đổi phiên bản ứng dụng',
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
const canPolicy = auth.can('security.policy')
const canBackups = auth.can('backups.manage')
if (canSettings) onMounted(() => { load(); loadPackages() })
else loading.value = false
if (canSecurity) onMounted(loadEvents)

const route = useRoute()
const router = useRouter()
const TABS = computed(() => [
  ...(canSettings
    ? [
        { key: 'payment', label: 'Thanh toán' },
        { key: 'prices', label: 'Gói dịch vụ' },
        { key: 'limits', label: 'Giới hạn ID' },
        { key: 'appversion', label: 'Phiên bản ứng dụng' },
      ]
    : []),
  ...(canSecurity ? [{ key: 'security', label: 'Nhật ký bảo mật' }] : []),
  ...(canPolicy ? [{ key: 'policy', label: 'Chính sách bảo mật' }] : []),
  ...(canBackups ? [{ key: 'backups', label: 'Sao lưu' }] : []),
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
    <p class="page-subtitle">Thanh toán, giá gói, giới hạn tài khoản, nhật ký và chính sách bảo mật, sao lưu</p>

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

        <fieldset class="ro" :disabled="!editBank">
          <div class="field">
            <label>Ngân hàng</label>
            <AppSelect v-model="bank.bank_bin">
              <option value="" disabled>-- Chưa chọn ngân hàng --</option>
              <option v-for="b in BANKS" :key="b.bin" :value="b.bin">{{ b.name }}</option>
            </AppSelect>
          </div>
          <div v-for="f in bankFields" :key="f.key" class="field">
            <label>{{ f.label }}</label>
            <input v-model="bank[f.key]" type="text" :placeholder="f.label" />
          </div>
        </fieldset>

        <div class="edit-actions">
          <AppButton variant="secondary" v-if="!editBank"  @click="editBank = true">Sửa</AppButton>
          <template v-else>
            <AppButton variant="ghost" :disabled="bankSaving" @click="cancelBank">Huỷ</AppButton>
            <AppButton variant="primary" type="submit" :disabled="bankSaving">{{ bankSaving ? 'Đang lưu...' : 'Lưu cấu hình thanh toán' }}</AppButton>
          </template>
        </div>
      </form>
      </div>

      <div v-show="activeTab === 'limits'" role="tabpanel">
      <h2 style="margin-top: 0">Giới hạn ID ảo</h2>
      <p class="page-subtitle">Số Mã ID (ID ảo) tối đa mỗi tài khoản khách hàng được tạo. Mặc định 5.</p>
      <form class="card" @submit.prevent="saveMaxIds">
        <div v-if="maxIdsError" class="alert alert-error">{{ maxIdsError }}</div>
        <div v-if="maxIdsSaved" class="alert alert-success">Đã lưu giới hạn ID ảo</div>
        <fieldset class="ro" :disabled="!editMax">
          <div class="field">
            <label>Số ID tối đa mỗi tài khoản (1-100)</label>
            <input v-model="maxIds" type="number" min="1" max="100" placeholder="5" />
          </div>
        </fieldset>
        <div class="edit-actions">
          <AppButton variant="secondary" v-if="!editMax"  @click="editMax = true">Sửa</AppButton>
          <template v-else>
            <AppButton variant="ghost" :disabled="maxIdsSaving" @click="cancelMax">Huỷ</AppButton>
            <AppButton variant="primary" type="submit" :disabled="maxIdsSaving">{{ maxIdsSaving ? 'Đang lưu...' : 'Lưu giới hạn' }}</AppButton>
          </template>
        </div>
      </form>
      </div>

      <div v-show="activeTab === 'prices'" role="tabpanel">
      <h2 style="margin-top: 0">Gói dịch vụ</h2>
      <p class="page-subtitle">Thêm, sửa, ẩn hoặc xoá các gói khách hàng có thể mua. Đổi giá chỉ áp dụng cho yêu cầu mua sau này.</p>
      <div v-if="pkgError" class="alert alert-error">{{ pkgError }}</div>
      <div v-if="pkgNotice" class="alert alert-success">{{ pkgNotice }}</div>

      <div class="pkg-bar">
        <AppButton variant="primary" size="sm" v-if="pkgEditing !== 'new'"  @click="startNewPackage">+ Thêm gói</AppButton>
      </div>

      <form v-if="pkgEditing === 'new'" class="card pkg-form" @submit.prevent="savePackage">
        <div class="pkg-fields">
          <label>Tên gói<input v-model="pkgForm.label" type="text" maxlength="60" placeholder="Vd: 2 tháng" required /></label>
          <label>Thời hạn (ngày)<input v-model="pkgForm.durationDays" type="number" min="1" max="3650" required /></label>
          <label>Giá (đ)<input v-model="pkgForm.priceVnd" type="number" min="0" required /></label>
        </div>
        <div class="pkg-actions">
          <AppButton variant="primary" size="sm" type="submit" :disabled="pkgBusy === 'new'">Thêm gói</AppButton>
          <AppButton variant="ghost" size="sm" @click="cancelPackage">Huỷ</AppButton>
        </div>
      </form>

      <div v-if="packages.length === 0 && pkgEditing !== 'new'" class="card">Chưa có gói nào.</div>
      <div v-for="p in packages" :key="p.type" class="card pkg-card">
        <template v-if="pkgEditing !== p.type">
          <div class="pkg-head">
            <div>
              <strong>{{ p.label }}</strong>
              <span v-if="!p.active" class="chip">Đang ẩn</span>
              <div class="pkg-meta">{{ formatDuration(p.durationDays) }} · {{ formatVnd(p.priceVnd) }} · {{ p.usage.users }} tài khoản đang dùng</div>
            </div>
            <div class="pkg-actions">
              <AppButton variant="primary" size="sm" :disabled="pkgBusy === p.type" @click="startEditPackage(p)">Sửa</AppButton>
              <AppButton variant="secondary" size="sm" :disabled="pkgBusy === p.type" @click="togglePackage(p)">{{ p.active ? 'Ẩn' : 'Hiện lại' }}</AppButton>
              <button type="button" class="btn btn-ghost btn-sm pkg-danger" :disabled="pkgBusy === p.type" @click="removePackage(p)">Xoá</button>
            </div>
          </div>
        </template>
        <form v-else @submit.prevent="savePackage">
          <div class="pkg-fields">
            <label>Tên gói<input v-model="pkgForm.label" type="text" maxlength="60" required /></label>
            <label>Thời hạn (ngày)<input v-model="pkgForm.durationDays" type="number" min="1" max="3650" required /></label>
            <label>Giá (đ)<input v-model="pkgForm.priceVnd" type="number" min="0" required /></label>
          </div>
          <div class="pkg-actions">
            <AppButton variant="primary" size="sm" type="submit" :disabled="pkgBusy === p.type">Lưu</AppButton>
            <AppButton variant="ghost" size="sm" @click="cancelPackage">Huỷ</AppButton>
          </div>
        </form>
      </div>
      </div>
    </template>

    <div v-if="canSettings && activeTab === 'appversion'" role="tabpanel">
      <AppVersionPanel />
    </div>

    <div v-if="canPolicy && activeTab === 'policy'" role="tabpanel">
      <SecurityPolicyView embedded />
    </div>
    <div v-if="canBackups && activeTab === 'backups'" role="tabpanel">
      <BackupsView embedded />
    </div>

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
.pkg-bar {
  margin-bottom: 12px;
}
.pkg-card,
.pkg-form {
  margin-bottom: 10px;
  padding: 14px 16px;
}
.pkg-head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
}
.pkg-meta {
  margin-top: 2px;
  font-size: 14px;
  color: var(--muted);
}
.pkg-fields {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 10px;
  margin-bottom: 12px;
}
.pkg-fields label {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 13px;
  color: var(--muted);
}
.pkg-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.pkg-danger {
  color: var(--danger-text);
}
.set-tabs {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-bottom: 20px;
}
.set-tab {
  flex: 0 0 auto;
  min-height: 36px;
  padding: 0 14px;
  font: inherit;
  font-size: 14px;
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

fieldset.ro {
  min-width: 0;
  margin: 0;
  padding: 0;
  border: 0;
}
fieldset.ro:disabled input,
fieldset.ro:disabled :deep(button),
fieldset.ro:disabled :deep(.app-select-trigger) {
  opacity: 1;
  cursor: default;
  color: var(--text-primary);
}
.edit-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 12px;
}
</style>
