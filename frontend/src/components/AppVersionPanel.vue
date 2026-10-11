<!--
  Cài đặt > Phiên bản ứng dụng (A17): the newest version, the oldest version still allowed and the download link of the
  Android app. The app reads them from the public GET /api/app-version at start-up: below the newest it offers an update,
  below the minimum it blocks until updated. Shown read-only; "Sửa" unlocks the form (Huỷ / Lưu).
  API: GET/PUT /admin/app-version  { latestVersion, minVersion, downloadUrl, notes }
-->
<script setup>
import { computed, onMounted, reactive, ref } from 'vue'
import { api, ApiError } from '../api'

const loading = ref(true)
const saving = ref(false)
const editing = ref(false)
const error = ref('')
const saved = ref(false)
const form = reactive({ latestVersion: '', minVersion: '', downloadUrl: '', notes: '' })
let stored = { latestVersion: '', minVersion: '', downloadUrl: '', notes: '' }

const VERSION = /^\d{1,4}\.\d{1,4}\.\d{1,4}$/
const parts = (v) => v.split('.').map(Number)
const cmp = (a, b) => {
  const x = parts(a)
  const y = parts(b)
  for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] < y[i] ? -1 : 1
  return 0
}

const problem = computed(() => {
  const l = form.latestVersion.trim()
  const m = form.minVersion.trim()
  if (l && !VERSION.test(l)) return 'Phiên bản mới nhất phải có dạng 1.2.3'
  if (m && !VERSION.test(m)) return 'Phiên bản tối thiểu phải có dạng 1.2.3'
  if (m && !l) return 'Hãy nhập phiên bản mới nhất trước khi đặt phiên bản tối thiểu'
  if (l && m && cmp(m, l) > 0) return 'Phiên bản tối thiểu không được lớn hơn phiên bản mới nhất'
  const u = form.downloadUrl.trim()
  if (u && !/^https:\/\/\S+$/.test(u)) return 'Đường dẫn tải phải bắt đầu bằng https://'
  if (form.notes.length > 500) return 'Ghi chú tối đa 500 ký tự'
  return ''
})
const dirty = computed(() => JSON.stringify(form) !== JSON.stringify(stored))

function fill(res) {
  stored = {
    latestVersion: res.latestVersion || '',
    minVersion: res.minVersion || '',
    downloadUrl: res.downloadUrl || '',
    notes: res.notes || '',
  }
  Object.assign(form, stored)
}

async function load() {
  try {
    fill(await api.get('/admin/app-version'))
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tải được cấu hình phiên bản'
  } finally {
    loading.value = false
  }
}
onMounted(load)

function cancel() {
  Object.assign(form, stored)
  error.value = ''
  editing.value = false
}

async function save() {
  if (problem.value) {
    error.value = problem.value
    return
  }
  saving.value = true
  error.value = ''
  saved.value = false
  try {
    fill(await api.put('/admin/app-version', { ...form }))
    saved.value = true
    editing.value = false
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không lưu được'
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <div>
    <h2 style="margin-top: 0">Phiên bản ứng dụng</h2>
    <p class="page-subtitle">
      App Android hỏi thông tin này mỗi lần mở. Thấp hơn phiên bản mới nhất: app nhắc cập nhật. Thấp hơn phiên bản tối thiểu:
      app bị chặn cho tới khi cập nhật. Để trống ô nào thì không áp dụng.
    </p>
    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="saved" class="alert alert-success">Đã lưu phiên bản ứng dụng</div>
    <div v-if="loading" class="card">Đang tải...</div>
    <form v-else class="card" @submit.prevent="save">
      <fieldset class="ro" :disabled="!editing">
        <div class="field">
          <label>Phiên bản mới nhất</label>
          <input v-model="form.latestVersion" type="text" inputmode="decimal" placeholder="Ví dụ 1.2.1" />
        </div>
        <div class="field">
          <label>Phiên bản tối thiểu còn được dùng</label>
          <input v-model="form.minVersion" type="text" inputmode="decimal" placeholder="Ví dụ 1.1.0 (để trống nếu không chặn)" />
        </div>
        <div class="field">
          <label>Đường dẫn tải ứng dụng (https)</label>
          <input v-model="form.downloadUrl" type="url" placeholder="https://..." />
        </div>
        <div class="field">
          <label>Có gì mới (tối đa 500 ký tự)</label>
          <textarea v-model="form.notes" rows="3" maxlength="500" placeholder="Hiện trong hộp nhắc cập nhật"></textarea>
        </div>
      </fieldset>
      <div class="edit-actions">
        <button v-if="!editing" type="button" class="btn btn-secondary" @click="editing = true">Sửa</button>
        <template v-else>
          <button type="button" class="btn btn-ghost" :disabled="saving" @click="cancel">Huỷ</button>
          <button type="submit" class="btn btn-primary" :disabled="saving || !dirty">{{ saving ? 'Đang lưu...' : 'Lưu' }}</button>
        </template>
      </div>
    </form>
  </div>
</template>

<style scoped>
fieldset.ro {
  min-width: 0;
  margin: 0;
  padding: 0;
  border: 0;
}
fieldset.ro:disabled input,
fieldset.ro:disabled textarea {
  opacity: 1;
  cursor: default;
  color: var(--text-primary);
}
.field textarea {
  width: 100%;
  padding: 10px 12px;
  font: inherit;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  resize: vertical;
}
.edit-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 12px;
}
</style>
