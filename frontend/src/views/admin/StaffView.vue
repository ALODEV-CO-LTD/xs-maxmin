<!--
  /admin/staff - multi-level Admin (A07), root Admin only. The root Admin creates
  secondary accounts (e.g. chăm sóc khách hàng, quản lý hệ thống) and ticks which
  of the Admin's high-level rights each one gets. Everything not ticked stays with
  the root Admin; managing these accounts is never delegable.
  API: GET/POST /admin/staff, PATCH/DELETE /admin/staff/:id
-->
<script setup>
import { onMounted, reactive, ref } from 'vue'
import { api, ApiError } from '../../api'
import { showConfirm } from '../../confirm'

const loading = ref(true)
const error = ref('')
const catalog = ref({}) // permission key -> label
const staff = ref([])

// Quick starting points: they only tick boxes, the Admin can still change them.
const PRESETS = [
  { label: 'Chăm sóc khách hàng', keys: ['users.view', 'users.recovery', 'support.messages'] },
  { label: 'Quản lý hệ thống', keys: ['users.view', 'stats.view', 'announcements.manage', 'settings.manage', 'backups.manage', 'security.view'] },
]

const form = reactive({ name: '', username: '', password: '', permissions: [] })
const creating = ref(false)
const showForm = ref(false)
const formError = ref('')

const edits = reactive({}) // staff id -> { permissions, newPassword }
const busyId = ref('')
const notice = ref('')

async function load() {
  error.value = ''
  try {
    const res = await api.get('/admin/staff')
    catalog.value = res.permissions
    staff.value = res.staff
    for (const s of res.staff) edits[s.id] = { permissions: [...s.permissions], newPassword: '' }
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tải được danh sách tài khoản thứ cấp'
  } finally {
    loading.value = false
  }
}
onMounted(load)

function toggle(list, key) {
  const i = list.indexOf(key)
  if (i === -1) list.push(key)
  else list.splice(i, 1)
}
function applyPreset(list, keys) {
  list.splice(0, list.length, ...keys)
}

async function create() {
  formError.value = ''
  creating.value = true
  try {
    await api.post('/admin/staff', { ...form, permissions: [...form.permissions] })
    Object.assign(form, { name: '', username: '', password: '', permissions: [] })
    showForm.value = false
    notice.value = 'Đã tạo tài khoản. Hãy gửi tên đăng nhập và mật khẩu cho nhân viên qua kênh riêng.'
    await load()
  } catch (err) {
    formError.value = err instanceof ApiError ? err.message : 'Không tạo được tài khoản'
  } finally {
    creating.value = false
  }
}

async function patch(s, body, okText) {
  busyId.value = s.id
  error.value = ''
  notice.value = ''
  try {
    await api.patch(`/admin/staff/${s.id}`, body)
    notice.value = okText
    await load()
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không lưu được thay đổi'
  } finally {
    busyId.value = ''
  }
}

const savePermissions = (s) => patch(s, { permissions: edits[s.id].permissions }, `Đã lưu quyền của ${s.name}`)
const toggleLock = (s) => patch(s, { locked: !s.locked }, s.locked ? `Đã mở khoá ${s.name}` : `Đã khoá ${s.name} và đăng xuất mọi thiết bị`)
async function resetPassword(s) {
  const pw = edits[s.id].newPassword
  if (!pw) return
  await patch(s, { newPassword: pw }, `Đã đặt mật khẩu mới cho ${s.name} (đã đăng xuất mọi thiết bị)`)
}
async function remove(s) {
  if (!(await showConfirm({ title: 'Xoá tài khoản thứ cấp', message: `Xoá tài khoản "${s.username}"? Nhân viên sẽ không đăng nhập được nữa.`, confirmText: 'Xoá', danger: true }))) return
  busyId.value = s.id
  try {
    await api.del(`/admin/staff/${s.id}`)
    notice.value = `Đã xoá ${s.username}`
    await load()
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không xoá được'
  } finally {
    busyId.value = ''
  }
}
const same = (a, b) => a.length === b.length && a.every((k) => b.includes(k))
</script>

<template>
  <div class="page">
    <h1 class="page-title">Phân quyền Admin</h1>
    <p class="page-subtitle">
      Tạo tài khoản thứ cấp cho nhân viên và tích chọn những quyền của Admin mà họ được dùng. Chỉ Admin gốc quản lý được phần này; quyền thay đổi có hiệu lực ngay ở lần thao tác kế tiếp của nhân viên.
    </p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="notice" class="alert alert-success">{{ notice }}</div>
    <div v-if="loading" class="card">Đang tải...</div>

    <template v-else>
      <div class="bar">
        <h2 class="bar-title">Tài khoản thứ cấp <span class="count">{{ staff.length }}</span></h2>
        <button type="button" class="btn btn-primary" @click="showForm = !showForm">{{ showForm ? 'Đóng' : '+ Tạo tài khoản' }}</button>
      </div>

      <form v-if="showForm" class="card block" @submit.prevent="create">
        <div v-if="formError" class="alert alert-error">{{ formError }}</div>
        <div class="grid">
          <label>Tên hiển thị<input v-model="form.name" type="text" required /></label>
          <label>Tên đăng nhập<input v-model="form.username" type="text" autocomplete="off" required /></label>
          <label>Mật khẩu<input v-model="form.password" type="text" autocomplete="off" required /></label>
        </div>
        <div class="presets">
          <span>Chọn nhanh:</span>
          <button v-for="p in PRESETS" :key="p.label" type="button" class="btn btn-secondary btn-sm" @click="applyPreset(form.permissions, p.keys)">{{ p.label }}</button>
          <button type="button" class="btn btn-ghost btn-sm" @click="form.permissions.splice(0)">Bỏ chọn</button>
        </div>
        <div class="perms">
          <label v-for="(label, key) in catalog" :key="key" class="perm">
            <input type="checkbox" :checked="form.permissions.includes(key)" @change="toggle(form.permissions, key)" />
            <span>{{ label }}</span>
          </label>
        </div>
        <button type="submit" class="btn btn-primary" :disabled="creating">{{ creating ? 'Đang tạo...' : 'Tạo tài khoản' }}</button>
      </form>

      <div v-if="staff.length === 0 && !showForm" class="card">Chưa có tài khoản thứ cấp nào.</div>

      <div v-for="s in staff" :key="s.id" class="card block">
        <div class="head">
          <div>
            <strong>{{ s.name }}</strong> <span class="muted">({{ s.username }})</span>
            <span v-if="s.locked" class="tag">Đang khoá</span>
          </div>
          <div class="head-actions">
            <button type="button" class="btn btn-secondary btn-sm" :disabled="busyId === s.id" @click="toggleLock(s)">{{ s.locked ? 'Mở khoá' : 'Khoá' }}</button>
            <button type="button" class="btn btn-ghost btn-sm danger" :disabled="busyId === s.id" @click="remove(s)">Xoá</button>
          </div>
        </div>
        <div class="presets">
          <span>Chọn nhanh:</span>
          <button v-for="p in PRESETS" :key="p.label" type="button" class="btn btn-secondary btn-sm" @click="applyPreset(edits[s.id].permissions, p.keys)">{{ p.label }}</button>
        </div>
        <div class="perms">
          <label v-for="(label, key) in catalog" :key="key" class="perm">
            <input type="checkbox" :checked="edits[s.id].permissions.includes(key)" @change="toggle(edits[s.id].permissions, key)" />
            <span>{{ label }}</span>
          </label>
        </div>
        <div class="row">
          <button type="button" class="btn btn-primary btn-sm" :disabled="busyId === s.id || !edits[s.id].permissions.length || same(edits[s.id].permissions, s.permissions)" @click="savePermissions(s)">Lưu quyền</button>
          <input v-model="edits[s.id].newPassword" type="text" placeholder="Mật khẩu mới" autocomplete="off" />
          <button type="button" class="btn btn-secondary btn-sm" :disabled="busyId === s.id || !edits[s.id].newPassword" @click="resetPassword(s)">Đặt lại mật khẩu</button>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}
.bar-title {
  margin: 0;
  font-size: 18px;
}
.count {
  margin-left: 6px;
  padding: 1px 8px;
  font-size: 13px;
  color: var(--muted);
  background: var(--surface);
  border-radius: 999px;
}
.block {
  margin-bottom: 12px;
  padding: 16px;
  border-radius: 12px;
}
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 10px;
  margin-bottom: 12px;
}
label {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 13px;
  color: var(--muted);
}
input[type='text'] {
  height: 40px;
  padding: 0 12px;
  font: inherit;
  font-size: 15px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.presets {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 6px 8px;
  margin-bottom: 8px;
  font-size: 13px;
  color: var(--muted);
}
.perms {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
  gap: 6px 16px;
  margin-bottom: 12px;
}
.perm {
  flex-direction: row;
  align-items: flex-start;
  gap: 8px;
  font-size: 14px;
  color: var(--text-primary);
  cursor: pointer;
}
.perm input {
  margin-top: 3px;
}
.head {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  margin-bottom: 8px;
}
.head-actions,
.row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
}
.row input {
  flex: 1 1 160px;
  max-width: 240px;
}
.muted {
  color: var(--muted);
}
.tag {
  margin-left: 8px;
  padding: 2px 8px;
  font-size: 12px;
  color: var(--danger-text);
  border: 1px solid var(--border);
  border-radius: 999px;
}
.danger {
  color: var(--danger-text);
}
</style>
