<!--
  /admin/notices - broadcast notices + maintenance mode (A12 / A16).
  API: GET/POST /admin/announcements, PATCH/DELETE /admin/announcements/:id,
       GET/PUT /admin/settings (keys `maintenance_enabled` = "true"/"false",
       `maintenance_message`). Users see both as a banner in AppShell
       (GET /announcements). Maintenance mode only shows a notice, it does not
       block anyone.
-->
<script setup>
import AppSelect from '../../components/AppSelect.vue'
import { onMounted, ref } from 'vue'
import { api, ApiError } from '../../api'
import { showConfirm } from '../../confirm'
import { useAuthStore } from '../../stores/auth'

// Maintenance mode is stored via /admin/settings, which needs settings.manage;
// staff holding only announcements.manage get the announcements part alone.
const canMaintenance = useAuthStore().can('settings.manage')

const KINDS = [
  { value: 'maintenance', label: 'Bảo trì' },
  { value: 'policy', label: 'Đổi chính sách' },
  { value: 'info', label: 'Thông báo chung' },
]
const kindLabel = (k) => KINDS.find((x) => x.value === k)?.label || k

const loading = ref(true)
const error = ref('')

// maintenance mode
const maintenanceOn = ref(false)
const maintenanceMessage = ref('')
const maintenanceSaving = ref(false)
const maintenanceSaved = ref(false)

// announcements
const list = ref([])
const form = ref({ kind: 'info', title: '', body: '' })
const posting = ref(false)

async function load() {
  loading.value = true
  error.value = ''
  try {
    const [settings, ann] = await Promise.all([
      canMaintenance ? api.get('/admin/settings') : Promise.resolve({}),
      api.get('/admin/announcements'),
    ])
    maintenanceOn.value = settings.maintenance_enabled === 'true'
    maintenanceMessage.value = settings.maintenance_message || ''
    list.value = ann.announcements
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tải được dữ liệu'
  } finally {
    loading.value = false
  }
}

async function saveMaintenance() {
  maintenanceSaving.value = true
  maintenanceSaved.value = false
  error.value = ''
  try {
    await api.put('/admin/settings', {
      maintenance_enabled: maintenanceOn.value ? 'true' : 'false',
      maintenance_message: maintenanceMessage.value.trim(),
    })
    maintenanceSaved.value = true
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không lưu được'
  } finally {
    maintenanceSaving.value = false
  }
}

async function post() {
  if (!form.value.title.trim()) return
  if (!(await showConfirm({
    title: 'Gửi thông báo',
    message: `Gửi "${form.value.title.trim()}" tới tất cả người dùng?`,
    confirmText: 'Gửi',
  }))) return
  posting.value = true
  error.value = ''
  try {
    const created = await api.post('/admin/announcements', {
      kind: form.value.kind,
      title: form.value.title.trim(),
      body: form.value.body.trim(),
    })
    list.value.unshift(created)
    form.value = { kind: form.value.kind, title: '', body: '' }
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không gửi được thông báo'
  } finally {
    posting.value = false
  }
}

async function toggle(a) {
  try {
    const updated = await api.patch(`/admin/announcements/${a.id}`, { active: !a.active })
    a.active = updated.active
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không cập nhật được'
  }
}

async function remove(a) {
  if (!(await showConfirm({ title: 'Xoá thông báo', message: `Xoá thông báo "${a.title}"?`, confirmText: 'Xoá', danger: true }))) return
  try {
    await api.del(`/admin/announcements/${a.id}`)
    list.value = list.value.filter((x) => x.id !== a.id)
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không xoá được'
  }
}

onMounted(load)
</script>

<template>
  <div class="page">
    <h1 class="page-title">Thông báo & bảo trì</h1>
    <p class="page-subtitle">Thông báo hiển thị dạng banner cho mọi người dùng đang đăng nhập.</p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="loading" class="card">Đang tải...</div>

    <template v-else>
      <section v-if="canMaintenance" class="card block">
        <h3 class="block-title">Chế độ bảo trì</h3>
        <label class="check-row">
          <input v-model="maintenanceOn" type="checkbox" />
          <span>Đang bảo trì (hiện banner cảnh báo cho mọi người dùng)</span>
        </label>
        <div class="field">
          <label for="mt-msg">Nội dung hiển thị</label>
          <div class="input-wrap">
            <textarea id="mt-msg" v-model="maintenanceMessage" rows="2" placeholder="Vd: Hệ thống bảo trì từ 23:00 đến 24:00"></textarea>
          </div>
        </div>
        <div v-if="maintenanceSaved" class="alert alert-success">Đã lưu.</div>
        <button type="button" class="btn btn-primary" :disabled="maintenanceSaving" @click="saveMaintenance">
          {{ maintenanceSaving ? 'Đang lưu...' : 'Lưu cấu hình bảo trì' }}
        </button>
      </section>

      <section class="card block">
        <h3 class="block-title">Gửi thông báo mới</h3>
        <form @submit.prevent="post">
          <div class="field">
            <label for="an-kind">Loại</label>
            <AppSelect id="an-kind" v-model="form.kind">
              <option v-for="k in KINDS" :key="k.value" :value="k.value">{{ k.label }}</option>
            </AppSelect>
          </div>
          <div class="field">
            <label for="an-title">Tiêu đề</label>
            <div class="input-wrap"><input id="an-title" v-model="form.title" type="text" maxlength="200" /></div>
          </div>
          <div class="field">
            <label for="an-body">Nội dung (tuỳ chọn)</label>
            <div class="input-wrap"><textarea id="an-body" v-model="form.body" rows="3" maxlength="2000"></textarea></div>
          </div>
          <button type="submit" class="btn btn-primary" :disabled="posting || !form.title.trim()">
            {{ posting ? 'Đang gửi...' : 'Gửi thông báo' }}
          </button>
        </form>
      </section>

      <section class="card block">
        <h3 class="block-title">Thông báo đã gửi</h3>
        <p v-if="list.length === 0" class="empty">Chưa có thông báo nào.</p>
        <ul v-else class="ann-list">
          <li v-for="a in list" :key="a.id" class="ann-item">
            <div class="ann-main">
              <div>
                <span class="chip">{{ kindLabel(a.kind) }}</span>
                <span v-if="!a.active" class="chip">Đã ẩn</span>
                <strong class="ann-title">{{ a.title }}</strong>
              </div>
              <div v-if="a.body" class="ann-body">{{ a.body }}</div>
              <div class="ann-date">{{ new Date(a.createdAt).toLocaleString('vi-VN') }}</div>
            </div>
            <div class="ann-actions">
              <button type="button" class="btn btn-secondary btn-sm" @click="toggle(a)">{{ a.active ? 'Ẩn' : 'Hiện lại' }}</button>
              <button type="button" class="btn btn-danger btn-sm" @click="remove(a)">Xoá</button>
            </div>
          </li>
        </ul>
      </section>
    </template>
  </div>
</template>

<style scoped>
.block {
  margin-bottom: 16px;
}
.block-title {
  margin: 0 0 12px;
}
.check-row {
  display: flex;
  align-items: center;
  gap: 10px;
  min-height: 44px;
  margin-bottom: 8px;
  font-weight: 600;
}
.check-row input {
  width: 20px;
  height: 20px;
}
.empty {
  color: var(--muted);
}
.ann-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.ann-item {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--border);
}
.ann-title {
  margin-left: 8px;
}
.ann-body {
  margin-top: 4px;
  white-space: pre-line;
}
.ann-date {
  margin-top: 4px;
  font-size: 14px;
  color: var(--muted);
}
.ann-actions {
  display: flex;
  gap: 8px;
  align-items: flex-start;
}
</style>
