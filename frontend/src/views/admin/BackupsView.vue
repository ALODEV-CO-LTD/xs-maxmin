<!--
  /admin/backups - database backups (A13), admin only.
  API: GET /admin/backups (list), POST /admin/backups (create a snapshot with
  SQLite VACUUM INTO into backend/data/backups), GET /admin/backups/:name
  (download - fetched as a Blob because <a href> can't send the bearer token).
  Backup files never go into git (backend/data/ is ignored).
-->
<script setup>
import { onMounted, ref } from 'vue'
import { api, ApiError } from '../../api'

const backups = ref([])
const loading = ref(true)
const creating = ref(false)
const downloading = ref('')
const error = ref('')
const message = ref('')

function formatSize(bytes) {
  if (bytes >= 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`
  return `${Math.max(1, Math.round(bytes / 1024))} KB`
}

async function load() {
  loading.value = true
  error.value = ''
  try {
    backups.value = (await api.get('/admin/backups')).backups
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tải được danh sách'
  } finally {
    loading.value = false
  }
}

async function create() {
  creating.value = true
  error.value = ''
  message.value = ''
  try {
    const b = await api.post('/admin/backups')
    backups.value.unshift(b)
    message.value = `Đã tạo bản sao lưu ${b.name}`
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tạo được bản sao lưu'
  } finally {
    creating.value = false
  }
}

async function download(b) {
  downloading.value = b.name
  error.value = ''
  try {
    const blob = await api.blob(`/admin/backups/${encodeURIComponent(b.name)}`)
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = b.name
    document.body.appendChild(a)
    a.click()
    a.remove()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  } catch (err) {
    error.value = err instanceof ApiError ? err.message : 'Không tải được tệp'
  } finally {
    downloading.value = ''
  }
}

onMounted(load)
</script>

<template>
  <div class="page">
    <h1 class="page-title">Sao lưu dữ liệu</h1>
    <p class="page-subtitle">Tạo bản sao lưu cơ sở dữ liệu (lưu trên máy chủ) và tải về máy của bạn. Bản sao lưu chứa dữ liệu của mọi người dùng, hãy cất giữ cẩn thận.</p>

    <div v-if="error" class="alert alert-error">{{ error }}</div>
    <div v-if="message" class="alert alert-success">{{ message }}</div>

    <div class="card">
      <button type="button" class="btn btn-primary" :disabled="creating" @click="create">
        {{ creating ? 'Đang tạo...' : 'Tạo bản sao lưu mới' }}
      </button>

      <div v-if="loading" class="gap">Đang tải...</div>
      <p v-else-if="backups.length === 0" class="gap muted">Chưa có bản sao lưu nào.</p>
      <table v-else class="table stack-table gap">
        <thead>
          <tr><th>Tên tệp</th><th>Thời gian</th><th>Dung lượng</th><th></th></tr>
        </thead>
        <tbody>
          <tr v-for="b in backups" :key="b.name">
            <td data-label="Tên tệp">{{ b.name }}</td>
            <td data-label="Thời gian">{{ new Date(b.createdAt).toLocaleString('vi-VN') }}</td>
            <td data-label="Dung lượng">{{ formatSize(b.size) }}</td>
            <td>
              <button type="button" class="btn btn-secondary btn-sm" :disabled="downloading === b.name" @click="download(b)">
                {{ downloading === b.name ? 'Đang tải...' : 'Tải về' }}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped>
.gap {
  margin-top: 16px;
}
.muted {
  color: var(--muted);
}
</style>
