<!--
  Nhập số: enter the customer + numbers (+ optional "Điểm vào") side of a
  data entry. "Điểm ra" (result) is intentionally NOT editable here anymore
  - it moved to ResultsView.vue ("Nhập kết quả") since the two are a
  two-step daily workflow (enter bets in the morning, enter results after
  the lottery draw) that used to be crammed into one form.

  API: GET/POST /me/entries, PATCH/DELETE /me/entries/:id,
  GET/POST /me/syntax-templates (per-customer message syntax).

  Also here (offline.js): entries typed while offline are queued in IndexedDB
  and synced later, history is cached for offline viewing/searching; filters
  (K17), copy (K18), and "Nhập từ tin nhắn" (K13/K16: paste -> preview ->
  user confirms -> save; nothing is ever saved automatically).
-->
<script setup>
import { showConfirm } from '../confirm'
import AppSelect from '../components/AppSelect.vue'
import AppIcon from '../components/AppIcon.vue'
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api } from '../api'
import { useAuthStore } from '../stores/auth'
import { betTypeLabel } from '../betTypes'
import { today } from '../dates'
import { addConflict, cachedGet, createEntry, loadEntries, onEntriesChanged, updateEntry } from '../offline'
import { aliasesToText, fold, parseMessage, textToAliases, DEFAULT_STAKE_MARKERS } from '../messageParser'
import { confirmCopyEnabled, copyEntries, setConfirmCopy } from '../clipboard'

const auth = useAuthStore()

const route = useRoute()
const router = useRouter()

const entries = ref([])
const loading = ref(true)
const loadError = ref('')
const fromCache = ref(false) // showing the copy saved on this device (offline)

// Customer roster (Khách hàng page) - entry form must PICK a customer from
// here rather than free-typing a name, so a typo can't silently create a
// "phantom" duplicate customer. See CustomersView.vue for add/remove.
const customers = ref([])
async function loadCustomers() {
  try {
    const { customers: list } = await cachedGet('/me/customers')
    customers.value = list
  } catch (_) {
    // Leave the list empty - the select will just show none.
  }
}

// Bet types (đề/lô/...) come from this account's own rate config - see
// /scoring-settings (also used by ScoringView to pick a payout rate).
// Falls back to {de, lo} if that call fails, so the form still works.
const betTypes = ref(['de', 'lo'])
async function loadBetTypes() {
  try {
    const { rates } = await cachedGet('/me/scoring-settings')
    const keys = Object.keys(rates || {})
    if (keys.length) betTypes.value = keys
  } catch (_) {
    // Keep the fallback list.
  }
}


const form = reactive({
  customerName: '',
  entryDate: today(),
  note: '',
})
// Manual entry: a flat list of rows, each = (hạng mục, số, điểm vào). Every
// filled-in row becomes its own data_entries row on submit (value=<số>,
// score=<điểm>, betType=<hạng mục>), so two numbers with different stakes
// are never merged. Hạng mục options come from /scoring-settings (đề, lô, ...).
let rowSeq = 0
function blankRow(type) {
  return { uid: ++rowSeq, type: type || betTypes.value[0] || 'de', value: '', score: '' }
}
const rows = ref([blankRow()])
// once the account's own bet types are known, keep every row on a valid one
watch(betTypes, (types) => {
  for (const row of rows.value) if (!types.includes(row.type)) row.type = types[0]
})

function addRow() {
  rows.value.push(blankRow(rows.value[rows.value.length - 1]?.type))
}
function removeRow(idx) {
  const [gone] = rows.value.splice(idx, 1)
  if (gone) selectedIds.value = selectedIds.value.filter((id) => id !== gone.uid)
  if (rows.value.length === 0) rows.value.push(blankRow())
}

// Row selection + bulk edit: tick rows (or all), then change their hạng mục
// and/or điểm vào in one go.
const selectedIds = ref([])
const selectedCount = computed(() => selectedIds.value.length)
const allSelected = computed(() => rows.value.length > 0 && rows.value.every((r) => selectedIds.value.includes(r.uid)))
const someSelected = computed(() => selectedCount.value > 0 && !allSelected.value)
function toggleRow(uid) {
  selectedIds.value = selectedIds.value.includes(uid)
    ? selectedIds.value.filter((id) => id !== uid)
    : [...selectedIds.value, uid]
}
function toggleAllRows() {
  selectedIds.value = allSelected.value ? [] : rows.value.map((r) => r.uid)
}
function deleteSelectedRows() {
  rows.value = rows.value.filter((r) => !selectedIds.value.includes(r.uid))
  selectedIds.value = []
  if (rows.value.length === 0) rows.value.push(blankRow())
}
const bulkType = ref('')
const bulkScore = ref('')
const canApplyBulk = computed(() => selectedCount.value > 0 && (bulkType.value !== '' || bulkScore.value.trim() !== ''))
function applyBulk() {
  if (!canApplyBulk.value) return
  for (const row of rows.value) {
    if (!selectedIds.value.includes(row.uid)) continue
    if (bulkType.value !== '') row.type = bulkType.value
    if (bulkScore.value.trim() !== '') row.score = bulkScore.value.trim()
  }
  bulkType.value = ''
  bulkScore.value = ''
}

// Second side panel: select a customer (same state the form's dropdown uses)
function selectCustomer(name) {
  form.customerName = name
}
function entryCount(name) {
  return entries.value.filter((e) => e.customerName === name).length
}

const submitting = ref(false)
const formError = ref('')
const notice = ref('') // informational (e.g. saved offline)

const editingId = ref(null)
const editForm = reactive({
  customerName: '',
  value: '',
  entryDate: '',
  score: '',
  betType: 'de',
  note: '',
})
const editError = ref('')
const editSubmitting = ref(false)
const emValueInput = ref(null)

// OCR (đọc số liệu từ ảnh): runs fully client-side via tesseract.js, no
// image ever leaves the browser. It only ever *suggests* values into the
// form - never auto-submits - since handwriting/photo OCR on freeform
// betting numbers is inherently unreliable and a silent mistake here means
// real money. The user must review/edit and press "Thêm số liệu" themselves.
const ocrRunning = ref(false)
const ocrProgress = ref(0)
const ocrError = ref('')
const ocrRawText = ref('')
const ocrPreviewUrl = ref('')
const ocrFileInput = ref(null)

function pickImage() {
  ocrFileInput.value?.click()
}

async function onImageSelected(e) {
  const file = e.target.files?.[0]
  e.target.value = '' // allow picking the same file again later
  if (!file) return

  ocrError.value = ''
  ocrRawText.value = ''
  if (ocrPreviewUrl.value) URL.revokeObjectURL(ocrPreviewUrl.value)
  ocrPreviewUrl.value = URL.createObjectURL(file)

  ocrRunning.value = true
  ocrProgress.value = 0
  try {
    const { recognizeText } = await import('../ocr')
    const { text } = await recognizeText(file, { onProgress: (p) => (ocrProgress.value = p) })
    ocrRawText.value = text.trim()
    applyOcrGuess(ocrRawText.value)
  } catch (err) {
    const { describeOcrError } = await import('../ocr')
    ocrError.value = describeOcrError(err)
  } finally {
    ocrRunning.value = false
  }
}

function applyOcrGuess(text) {
  if (!text) return
  const lines = text
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean)

  // Numbers: lottery-style groups of 2-4 digits, one row per number since
  // each one may carry its own "Điểm vào". OCR can't tell which hạng mục a
  // photo is for, so rows get the default one (usually "Đề") and the user
  // can change it per row. Điểm vào is left blank - OCR only guesses the
  // numbers. If the form already has numbers typed, the guesses are appended.
  const numberGroups = text.match(/\d{2,4}/g) || []
  if (numberGroups.length) {
    const guessed = numberGroups.map((n) => ({ ...blankRow(), value: n }))
    const empty = rows.value.every((r) => !r.value.trim() && !r.score.trim())
    rows.value = empty ? guessed : [...rows.value.filter((r) => r.value.trim() || r.score.trim()), ...guessed]
  }

  // First line that has letters (not just digits/punctuation) is the best
  // guess for a customer name written above/near the numbers. Since the
  // name field is now a picklist (not free text), only auto-select it when
  // it EXACTLY matches (case-insensitive) an existing roster entry -
  // otherwise leave it alone rather than guess-creating a name that isn't
  // in the roster and can't display in the <select>.
  const nameLine = lines.find((l) => /[a-zA-ZÀ-ỹ]{2,}/.test(l))
  if (nameLine && !form.customerName.trim()) {
    const match = customers.value.find((c) => c.name.toLowerCase() === nameLine.toLowerCase())
    if (match) form.customerName = match.name
  }
}

function clearOcr() {
  if (ocrPreviewUrl.value) URL.revokeObjectURL(ocrPreviewUrl.value)
  ocrPreviewUrl.value = ''
  ocrRawText.value = ''
  ocrError.value = ''
}

const pkg = computed(() => auth.user?.package)
const stats = computed(() => auth.user?.stats)
const canAdd = computed(() => pkg.value?.isActive)

// "Điểm vào" (score) / "Điểm ra" (result) reuse the two existing free-text
// entry fields as numeric point counters instead of generic notes - parsed
// leniently (strip everything but digits/minus/dot) so entries typed before
// this change don't break the totals, they just count as 0.
function toNumber(str) {
  if (!str) return 0
  const cleaned = String(str).replace(/[^\d.-]/g, '')
  const n = parseFloat(cleaned)
  return Number.isFinite(n) ? n : 0
}

// The list/stats below only ever show the customer currently selected in
// the form above - this page is a per-customer data-entry workspace, not
// a full history browser (that's Khách hàng/Tính điểm). No customer
// selected yet -> nothing to show.
const visibleEntries = computed(() => {
  if (!form.customerName) return []
  return entries.value.filter((e) => e.customerName === form.customerName)
})

const totals = computed(() => {
  let vao = 0
  let ra = 0
  for (const e of visibleEntries.value) {
    vao += toNumber(e.score)
    ra += toNumber(e.result)
  }
  return { vao, ra, chenhLech: vao - ra }
})

function formatNumber(n) {
  return new Intl.NumberFormat('vi-VN').format(n)
}

async function loadAll() {
  loading.value = true
  loadError.value = ''
  try {
    // cachedGet/loadEntries fall back to the copy saved on this device when
    // offline, so the page keeps working (see offline.js).
    const [me, list] = await Promise.all([cachedGet('/me'), loadEntries()])
    auth.user = me
    entries.value = list.entries
    fromCache.value = list.fromCache
  } catch (err) {
    loadError.value = err.message || 'Không tải được dữ liệu'
  } finally {
    loading.value = false
  }
}

onMounted(loadAll)
onMounted(loadBetTypes)
onMounted(loadTemplates)
// after the offline queue synced / a conflict was resolved: reload the list
const stopListening = onEntriesChanged(loadAll)
onBeforeUnmount(stopListening)
// Coming back from "+ Thêm khách hàng mới" (Khách hàng page): preselect the new customer.
onMounted(async () => {
  await loadCustomers()
  const name = route.query.customer
  if (typeof name === 'string' && customers.value.some((c) => c.name === name)) {
    form.customerName = name
  }
  if (route.query.customer !== undefined) router.replace({ name: 'entries' })
})

async function submitForm() {
  formError.value = ''
  // Every complete row (Hạng mục + Số + Điểm vào) becomes its own entry.
  // A half-filled row blocks the whole submit so nothing is added by mistake.
  const started = rows.value.filter((row) => row.value.trim() || String(row.score ?? '').trim())
  const isComplete = (row) => row.type && row.value.trim() && String(row.score ?? '').trim()
  if (!form.customerName.trim() || started.length === 0) {
    formError.value = 'Nhập ít nhất một số'
    return
  }
  if (!started.every(isComplete)) {
    formError.value = 'Nhập đủ Hạng mục, Số và Điểm vào'
    return
  }
  const tasks = started.map((row) => ({ type: row.type, row }))
  submitting.value = true
  try {
    const results = await Promise.allSettled(
      tasks.map((task) =>
        createEntry({
          customerName: form.customerName.trim(),
          value: task.row.value.trim(),
          entryDate: form.entryDate,
          score: task.row.score.trim() || undefined,
          betType: task.type,
          note: form.note.trim() || undefined,
        })
      )
    )
    const failed = []
    let anySucceeded = false
    let queuedCount = 0
    for (let i = 0; i < results.length; i++) {
      const r = results[i]
      const task = tasks[i]
      if (r.status === 'fulfilled') {
        entries.value.unshift(r.value.entry)
        if (auth.user?.stats && !r.value.queued) auth.user.stats.used += 1
        if (r.value.queued) queuedCount++
        anySucceeded = true
        const idx = rows.value.indexOf(task.row)
        if (idx !== -1) rows.value.splice(idx, 1)
        selectedIds.value = selectedIds.value.filter((id) => id !== task.row.uid)
      } else {
        failed.push(`${betTypeLabel(task.type)} "${task.row.value}": ${r.reason?.message || 'lỗi không rõ'}`)
      }
    }
    // The form always shows at least one (possibly blank) row.
    if (rows.value.length === 0) rows.value.push(blankRow())
    if (failed.length) formError.value = failed.join(' · ')
    if (queuedCount) notice.value = `Đang offline: ${queuedCount} số liệu đã lưu trên máy, sẽ tự đồng bộ khi có mạng.`
    if (anySucceeded) form.note = ''
    // Keep customerName + date - common to add several customers/entries
    // for the same day in a row.
  } finally {
    submitting.value = false
  }
}

// While editing, the customer being edited might have a customerName that
// isn't (or is no longer) in the roster - e.g. entered before the roster
// existed, or since removed from Khách hàng. Add it as an extra option so
// the <select> still shows and keeps it selected instead of silently
// blanking/changing the customer on save.
const editCustomers = computed(() => {
  const name = editForm.customerName
  if (!name || customers.value.some((c) => c.name === name)) return customers.value
  return [...customers.value, { id: `__current-${name}`, name }]
})

const editingEntry = computed(() => entries.value.find((e) => e.id === editingId.value))
watch(editingId, async (id) => {
  if (!id) return
  await nextTick()
  emValueInput.value?.focus()
})

function startEdit(entry) {
  editingId.value = entry.id
  editError.value = ''
  editForm.customerName = entry.customerName || ''
  editForm.value = entry.value || ''
  editForm.entryDate = entry.entryDate || today()
  editForm.score = entry.score || ''
  editForm.betType = entry.betType || 'de'
  editForm.note = entry.note || ''
}

function cancelEdit() {
  editingId.value = null
  editError.value = ''
}

async function saveEdit(id) {
  editError.value = ''
  if (!editForm.customerName.trim() || !editForm.value.trim()) {
    editError.value = 'Vui lòng nhập tên khách hàng và số liệu'
    return
  }
  editSubmitting.value = true
  try {
    const changes = {
      customerName: editForm.customerName.trim(),
      value: editForm.value.trim(),
      entryDate: editForm.entryDate,
      score: editForm.score.trim(),
      betType: editForm.betType,
      note: editForm.note.trim(),
    }
    const base = entries.value.find((e) => e.id === id)
    try {
      const { entry: updated, queued } = await updateEntry(base, changes)
      const idx = entries.value.findIndex((e) => e.id === id)
      if (idx !== -1) entries.value[idx] = updated
      if (queued) notice.value = 'Đang offline: thay đổi đã lưu trên máy, sẽ tự đồng bộ khi có mạng.'
      editingId.value = null
    } catch (err) {
      if (err.status === 409 && err.data?.conflict) {
        // edited elsewhere meanwhile -> ask which version to keep (SyncStatus.vue)
        addConflict(base, changes, err.data.server)
        editingId.value = null
      } else {
        throw err
      }
    }
  } catch (err) {
    editError.value = err.message || 'Không lưu được thay đổi'
  } finally {
    editSubmitting.value = false
  }
}

const deletingId = ref(null)
const deleteErrors = reactive({}) // id -> error message

async function deleteEntry(entry) {
  if (entry.pending) {
    deleteErrors[entry.id] = 'Số liệu đang chờ đồng bộ, hãy đợi đồng bộ xong rồi xoá.'
    return
  }
  if (!(await showConfirm({
    title: 'Xoá số liệu',
    message: `Xoá số liệu "${entry.value}" (${entry.customerName})? Không thể hoàn tác.`,
    confirmText: 'Xoá',
    danger: true,
  }))) return
  deleteErrors[entry.id] = ''
  deletingId.value = entry.id
  try {
    await api.del(`/me/entries/${entry.id}`)
    entries.value = entries.value.filter((e) => e.id !== entry.id)
    if (auth.user?.stats) auth.user.stats.used = Math.max(auth.user.stats.used - 1, 0)
    if (editingId.value === entry.id) editingId.value = null
  } catch (err) {
    deleteErrors[entry.id] = err.message || 'Không xoá được'
  } finally {
    deletingId.value = null
  }
}

// "Xoá tất cả số liệu": removes every entry of the selected customer (one
// DELETE per entry, there is no bulk endpoint), after a confirmation.
const deletingAll = ref(false)
const deleteAllError = ref('')
async function deleteAllEntries() {
  const list = visibleEntries.value.filter((e) => !e.pending)
  if (!list.length) return
  if (!(await showConfirm({
    title: 'Xoá tất cả số liệu',
    message: `Xoá toàn bộ ${list.length} số liệu của khách hàng "${form.customerName}"? Không thể hoàn tác.`,
    confirmText: 'Xoá tất cả',
    danger: true,
  }))) return
  deleteAllError.value = ''
  deletingAll.value = true
  let failed = 0
  for (const entry of list) {
    try {
      await api.del(`/me/entries/${entry.id}`)
      entries.value = entries.value.filter((e) => e.id !== entry.id)
      if (auth.user?.stats) auth.user.stats.used = Math.max(auth.user.stats.used - 1, 0)
      if (editingId.value === entry.id) editingId.value = null
    } catch (_) {
      failed++
    }
  }
  if (failed) deleteAllError.value = `${failed} số liệu không xoá được, thử lại.`
  deletingAll.value = false
}
// ---- Tìm kiếm & bộ lọc (K17) ------------------------------------------------
// Runs locally on the loaded (or cached) entries, so it also works offline.
const filters = reactive({ date: '', type: '', q: '', all: false })
const hasFilter = computed(() => !!(filters.date || filters.type || filters.q.trim() || filters.all))
const filteredEntries = computed(() => {
  const q = fold(filters.q.trim())
  return entries.value.filter((e) => {
    if (!filters.all && (!form.customerName || e.customerName !== form.customerName)) return false
    if (filters.date && e.entryDate !== filters.date) return false
    if (filters.type && (e.betType || 'de') !== filters.type) return false
    if (q) {
      const hay = fold([e.customerName, e.entryDate, betTypeLabel(e.betType || 'de'), e.value, e.score, e.result, e.note].join(' '))
      if (!hay.includes(q)) return false
    }
    return true
  })
})
function clearFilters() {
  filters.date = ''
  filters.type = ''
  filters.q = ''
  filters.all = false
}

// ---- Sao chép (K18) ---------------------------------------------------------
const confirmCopy = ref(confirmCopyEnabled())
watch(confirmCopy, (on) => setConfirmCopy(on))
const copyMessage = ref('')
async function copyShown() {
  copyMessage.value = ''
  const label = [filters.all ? 'tất cả khách' : form.customerName, filters.date].filter(Boolean).join(', ')
  const res = await copyEntries(filteredEntries.value, { label, withCustomer: filters.all })
  if (res === 'copied') copyMessage.value = `Đã sao chép ${filteredEntries.value.length} số liệu`
  else if (res === 'failed') copyMessage.value = 'Không sao chép được'
}

// ---- Nhập từ tin nhắn (K13) + mẫu cú pháp theo khách (K16) -------------------
// Paste -> parse into a PREVIEW (uncertain lines highlighted, unticked) -> the
// user edits/ticks and confirms -> only then are rows saved. The per-customer
// syntax template is saved only when the user presses "Lưu mẫu", never learned.
const pasteOpen = ref(false)
const pasteText = ref('')
const previewRows = ref([])
const previewIgnored = ref([])
const pasteError = ref('')
const pasteSaving = ref(false)

const templates = ref([]) // [{ id, customerName, config }]
const templateOpen = ref(false)
const templateDraft = reactive({ defaultType: '', aliasText: '', markersText: DEFAULT_STAKE_MARKERS.join(', ') })
const templateMsg = ref('')
const savedTemplate = computed(() => templates.value.find((t) => t.customerName === form.customerName) || null)

async function loadTemplates() {
  try {
    templates.value = (await cachedGet('/me/syntax-templates')).templates
  } catch (_) {
    // no templates yet / offline without cache - parsing still works with the defaults
  }
}
function loadDraft() {
  const cfg = savedTemplate.value?.config
  templateDraft.defaultType = cfg?.defaultType || ''
  templateDraft.aliasText = aliasesToText(cfg?.typeAliases)
  templateDraft.markersText = (cfg?.stakeMarkers?.length ? cfg.stakeMarkers : DEFAULT_STAKE_MARKERS).join(', ')
  templateMsg.value = ''
}
watch(() => form.customerName, loadDraft)
// Picking a customer puts the cursor in the first "Số" box so numbers can be typed straight away;
// preventScroll keeps the page still on phones.
watch(
  () => form.customerName,
  (name) => {
    if (!name) return
    nextTick(() => document.querySelector('.manual-rows .mr-number')?.focus({ preventScroll: true }))
  },
)
watch(templates, loadDraft)

function draftConfig() {
  return {
    defaultType: templateDraft.defaultType,
    typeAliases: textToAliases(templateDraft.aliasText, betTypes.value),
    stakeMarkers: templateDraft.markersText
      .split(/[,;\s]+/)
      .map((m) => m.trim())
      .filter(Boolean),
  }
}

function analyzeMessage() {
  pasteError.value = ''
  const { rows: parsed, ignored } = parseMessage(pasteText.value, { betTypes: betTypes.value, template: draftConfig() })
  previewIgnored.value = ignored
  previewRows.value = parsed.map((r) => ({ ...r, uid: ++rowSeq, selected: !r.uncertain }))
  if (!parsed.length) pasteError.value = 'Không tìm thấy số nào trong tin nhắn.'
}

const previewSelected = computed(() => previewRows.value.filter((r) => r.selected))
const previewUncertain = computed(() => previewRows.value.filter((r) => r.uncertain).length)

function clearPreview() {
  previewRows.value = []
  previewIgnored.value = []
  pasteError.value = ''
}

function previewRowComplete(r) {
  return r.type && r.value.trim() && String(r.score ?? '').trim()
}

// Put the ticked rows into the manual-entry rows above (to review/edit there).
function previewToRows() {
  const picked = previewSelected.value
  if (!picked.length) return
  const fresh = picked.map((r) => ({ uid: ++rowSeq, type: r.type, value: r.value, score: r.score }))
  const empty = rows.value.every((r) => !r.value.trim() && !r.score.trim())
  rows.value = empty ? fresh : [...rows.value, ...fresh]
  previewRows.value = previewRows.value.filter((r) => !r.selected)
}

async function savePreview() {
  pasteError.value = ''
  const picked = previewSelected.value
  if (!form.customerName) {
    pasteError.value = 'Chọn khách hàng trước khi lưu.'
    return
  }
  if (!picked.length) {
    pasteError.value = 'Chưa chọn dòng nào để lưu.'
    return
  }
  if (!picked.every(previewRowComplete)) {
    pasteError.value = 'Các dòng đã chọn cần đủ Hạng mục, Số và Điểm vào.'
    return
  }
  const unsure = picked.filter((r) => r.uncertain).length
  if (!(await showConfirm({
    title: 'Lưu số liệu từ tin nhắn',
    message: `Lưu ${picked.length} số liệu cho khách hàng "${form.customerName}", ngày ${form.entryDate}?${unsure ? ` Trong đó ${unsure} dòng chưa chắc chắn, hãy chắc là đã kiểm tra.` : ''}`,
    confirmText: 'Lưu',
  }))) return
  pasteSaving.value = true
  let queued = 0
  const failed = []
  try {
    for (const r of picked) {
      try {
        const res = await createEntry({
          customerName: form.customerName.trim(),
          value: r.value.trim(),
          entryDate: form.entryDate,
          score: String(r.score).trim(),
          betType: r.type,
          note: form.note.trim() || undefined,
        })
        entries.value.unshift(res.entry)
        if (res.queued) queued++
        else if (auth.user?.stats) auth.user.stats.used += 1
        previewRows.value = previewRows.value.filter((x) => x.uid !== r.uid)
      } catch (err) {
        failed.push(`${betTypeLabel(r.type)} "${r.value}": ${err.message || 'lỗi không rõ'}`)
      }
    }
  } finally {
    pasteSaving.value = false
  }
  if (failed.length) pasteError.value = failed.join(' · ')
  if (queued) notice.value = `Đang offline: ${queued} số liệu đã lưu trên máy, sẽ tự đồng bộ khi có mạng.`
  if (!previewRows.value.length) pasteText.value = ''
}

async function saveTemplate() {
  templateMsg.value = ''
  if (!form.customerName) return
  if (!(await showConfirm({
    title: 'Lưu mẫu cú pháp',
    message: `Lưu cách viết này làm mẫu riêng cho khách hàng "${form.customerName}"? Lần sau dán tin nhắn của khách này sẽ được phân tích theo mẫu.`,
    confirmText: 'Lưu mẫu',
  }))) return
  try {
    const saved = await api.post('/me/syntax-templates', { customerName: form.customerName, config: draftConfig() })
    templates.value = [...templates.value.filter((t) => t.customerName !== saved.customerName), saved]
    templateMsg.value = 'Đã lưu mẫu cho khách này.'
  } catch (err) {
    templateMsg.value = err.message || 'Không lưu được mẫu'
  }
}
async function deleteTemplate() {
  const t = savedTemplate.value
  if (!t) return
  try {
    await api.del(`/me/syntax-templates/${t.id}`)
    templates.value = templates.value.filter((x) => x.id !== t.id)
    templateMsg.value = 'Đã xoá mẫu.'
  } catch (err) {
    templateMsg.value = err.message || 'Không xoá được mẫu'
  }
}
</script>

<template>
  <div class="page">
    <h1 class="page-title">Nhập số</h1>

    <div v-if="!canAdd && stats" class="alert alert-warning">
      Gói của bạn đã hết hạn. Vui lòng gia hạn ở mục Gói dịch vụ để tiếp tục nhập số liệu.
    </div>

    <div v-if="fromCache" class="alert alert-warning">
      Đang offline: hiển thị số liệu đã lưu trên máy. Số liệu bạn nhập sẽ được gửi lên khi có mạng.
    </div>
    <div v-if="notice" class="alert alert-success notice-row">
      <span>{{ notice }}</span>
      <button type="button" class="btn btn-ghost btn-sm" @click="notice = ''">Đóng</button>
    </div>

    <div class="entries-layout">
      <!-- Second side panel: pick a customer, the form + their data open on the right -->
      <aside class="customer-rail" aria-label="Khách hàng">
        <div class="rail-title">Khách hàng</div>
        <p v-if="customers.length === 0" class="rail-empty">Chưa có khách hàng nào.</p>
        <!-- phones / small tablets: dropdown instead of the side list -->
        <AppSelect v-else v-model="form.customerName" class="rail-select" aria-label="Khách hàng">
          <option value="">-- Chọn khách hàng --</option>
          <option v-for="c in customers" :key="c.id" :value="c.name">{{ c.name }} ({{ entryCount(c.name) }})</option>
        </AppSelect>
        <ul v-if="customers.length > 0" class="rail-list">
          <li v-for="c in customers" :key="c.id">
            <button
              type="button"
              class="rail-item"
              :class="{ active: c.name === form.customerName }"
              :aria-pressed="c.name === form.customerName"
              @click="selectCustomer(c.name)"
            >
              <span class="rail-name">{{ c.name }}</span>
              <span class="rail-count">{{ entryCount(c.name) }}</span>
            </button>
          </li>
        </ul>
        <RouterLink :to="{ name: 'customers', query: { from: 'entries' } }" class="rail-add">+ Thêm khách hàng mới</RouterLink>
      </aside>

      <div class="entries-main">
        <form v-if="form.customerName" class="card add-form" @submit.prevent="submitForm">
          <h3 style="margin-top: 0">Thêm số liệu mới</h3>
          <div v-if="formError" class="alert alert-error">{{ formError }}</div>

          <div class="ocr-box">
            <input
              ref="ocrFileInput"
              type="file"
              accept="image/*"
              capture="environment"
              style="display: none"
              @change="onImageSelected"
            />
            <button type="button" class="btn btn-secondary btn-block" :disabled="ocrRunning" @click="pickImage">
              <AppIcon v-if="!ocrRunning" name="camera" />
              {{ ocrRunning ? `Đang đọc ảnh... ${ocrProgress}%` : 'Nhập từ ảnh (đọc tự động)' }}
            </button>
            <p class="ocr-hint">Ảnh xử lý ngay trên trình duyệt, không gửi lên đâu cả. Kết quả chỉ là gợi ý. Hãy kiểm tra lại trước khi lưu.</p>

            <div v-if="ocrError" class="alert alert-error" style="margin-top: 8px">{{ ocrError }}</div>

            <div v-if="ocrPreviewUrl && !ocrRunning" class="ocr-result">
              <img :src="ocrPreviewUrl" alt="Ảnh đã chọn" class="ocr-thumb" />
              <div class="ocr-text-wrap">
                <label>Văn bản đọc được (để đối chiếu)</label>
                <textarea v-model="ocrRawText" rows="3" class="ocr-raw"></textarea>
              </div>
            </div>
          </div>

          <!-- Nhập từ tin nhắn: paste -> preview -> confirm. Nothing is saved until "Lưu". -->
          <div class="paste-box">
            <button type="button" class="btn btn-secondary btn-block" :aria-expanded="pasteOpen" @click="pasteOpen = !pasteOpen">
              Nhập từ tin nhắn (dán nội dung)
            </button>
            <div v-if="pasteOpen" class="paste-body">
              <p class="ocr-hint">
                Dán tin nhắn của khách, bấm Phân tích để xem trước. Dòng chưa chắc chắn được tô màu và chưa được chọn. Chỉ khi bạn bấm Lưu mới ghi vào dữ liệu.
              </p>
              <textarea
                v-model="pasteText"
                rows="5"
                class="ocr-raw"
                placeholder="Vd:&#10;de 12 34 56 x 10&#10;lo 45 78 con 3"
                aria-label="Nội dung tin nhắn"
              ></textarea>
              <div class="paste-actions">
                <button type="button" class="btn btn-primary btn-sm" :disabled="!pasteText.trim()" @click="analyzeMessage">Phân tích</button>
                <button type="button" class="btn btn-ghost btn-sm" @click="templateOpen = !templateOpen">
                  Mẫu cú pháp của khách này {{ savedTemplate ? '(đã lưu)' : '(chưa lưu)' }}
                </button>
              </div>

              <div v-if="templateOpen" class="tpl-box">
                <p class="ocr-hint">
                  Mô tả cách khách này hay viết để phân tích đúng hơn. Mẫu chỉ được lưu khi bạn bấm Lưu mẫu, hệ thống không tự học thêm.
                </p>
                <div class="tpl-grid">
                  <div class="field">
                    <label for="tpl-type">Hạng mục mặc định</label>
                    <AppSelect id="tpl-type" v-model="templateDraft.defaultType">
                      <option value="">Không đặt (dòng không ghi hạng mục sẽ bị đánh dấu)</option>
                      <option v-for="t in betTypes" :key="t" :value="t">{{ betTypeLabel(t) }}</option>
                    </AppSelect>
                  </div>
                  <div class="field">
                    <label for="tpl-alias">Cách viết hạng mục</label>
                    <div class="input-wrap"><input id="tpl-alias" v-model="templateDraft.aliasText" type="text" placeholder="vd: dd=de, l=lo" /></div>
                  </div>
                  <div class="field">
                    <label for="tpl-markers">Dấu ngăn điểm</label>
                    <div class="input-wrap"><input id="tpl-markers" v-model="templateDraft.markersText" type="text" placeholder="vd: x, con, =" /></div>
                  </div>
                </div>
                <div class="paste-actions">
                  <button type="button" class="btn btn-secondary btn-sm" @click="saveTemplate">Lưu mẫu cho {{ form.customerName }}</button>
                  <button v-if="savedTemplate" type="button" class="btn btn-ghost btn-sm" @click="deleteTemplate">Xoá mẫu</button>
                </div>
                <p v-if="templateMsg" class="ocr-hint">{{ templateMsg }}</p>
              </div>

              <div v-if="pasteError" class="alert alert-error" style="margin-top: 8px">{{ pasteError }}</div>

              <div v-if="previewRows.length" class="preview">
                <p class="ocr-hint">
                  Đã chọn {{ previewSelected.length }}/{{ previewRows.length }} dòng<span v-if="previewUncertain">, {{ previewUncertain }} dòng chưa chắc chắn (tô vàng)</span>.
                </p>
                <div
                  v-for="r in previewRows"
                  :key="r.uid"
                  class="pv-row"
                  :class="{ 'is-uncertain': r.uncertain }"
                >
                  <label class="mr-check"><input v-model="r.selected" type="checkbox" :aria-label="`Chọn dòng ${r.value}`" /></label>
                  <AppSelect v-model="r.type" class="mr-type" aria-label="Hạng mục">
                    <option v-for="t in betTypes" :key="t" :value="t">{{ betTypeLabel(t) }}</option>
                  </AppSelect>
                  <input v-model="r.value" type="text" class="mr-input mr-number" aria-label="Số" />
                  <input v-model="r.score" type="text" inputmode="decimal" class="mr-input" placeholder="Điểm vào" aria-label="Điểm vào" />
                  <div v-if="r.uncertain" class="pv-reason">Chưa chắc chắn: {{ r.reasons.join('; ') }} (dòng gốc: {{ r.raw }})</div>
                </div>
                <p v-if="previewIgnored.length" class="ocr-hint">Bỏ qua {{ previewIgnored.length }} dòng không có số: {{ previewIgnored.join(' / ') }}</p>
                <div class="paste-actions">
                  <button type="button" class="btn btn-primary btn-sm" :disabled="pasteSaving || !canAdd || !previewSelected.length" @click="savePreview">
                    {{ pasteSaving ? 'Đang lưu...' : `Xác nhận và lưu ${previewSelected.length} dòng` }}
                  </button>
                  <button type="button" class="btn btn-secondary btn-sm" :disabled="!previewSelected.length" @click="previewToRows">Đưa vào bảng nhập tay để sửa</button>
                  <button type="button" class="btn btn-ghost btn-sm" @click="clearPreview">Bỏ xem trước</button>
                </div>
              </div>
            </div>
          </div>

          <div class="manual-rows">
            <div class="mr-head">
              <label class="mr-check" title="Chọn tất cả">
                <input
                  type="checkbox"
                  :checked="allSelected"
                  :indeterminate.prop="someSelected"
                  aria-label="Chọn tất cả các dòng"
                  @change="toggleAllRows"
                />
              </label>
              <span>Hạng mục</span>
              <span>Số</span>
              <span>Điểm vào</span>
              <span></span>
            </div>

            <div v-if="selectedCount > 0" class="mr-bulk">
              <AppSelect v-model="bulkType" class="mr-bulk-type" aria-label="Đổi hạng mục">
                <option value="" hidden>Đổi hạng mục</option>
                <option v-for="t in betTypes" :key="t" :value="t">{{ betTypeLabel(t) }}</option>
              </AppSelect>
              <input
                v-model="bulkScore"
                type="text"
                inputmode="decimal"
                class="mr-input mr-bulk-score"
                placeholder="Đổi điểm vào"
                aria-label="Đổi điểm vào"
                @keydown.enter.prevent="applyBulk"
              />
              <button type="button" class="btn btn-secondary btn-sm mr-bulk-apply" :disabled="!canApplyBulk" @click="applyBulk">
                Áp dụng
              </button>
              <button type="button" class="btn btn-danger btn-sm mr-bulk-delete" @click="deleteSelectedRows">Xoá</button>
            </div>

            <div class="mr-list">
              <div v-for="(row, i) in rows" :key="row.uid" class="mr-row" :class="{ 'is-selected': selectedIds.includes(row.uid) }">
                <label class="mr-check">
                  <input
                    type="checkbox"
                    :checked="selectedIds.includes(row.uid)"
                    :aria-label="`Chọn dòng ${i + 1}`"
                    @change="toggleRow(row.uid)"
                  />
                </label>
                <AppSelect v-model="row.type" class="mr-type" :aria-label="`Hạng mục dòng ${i + 1}`">
                  <option v-for="t in betTypes" :key="t" :value="t">{{ betTypeLabel(t) }}</option>
                </AppSelect>
                <input v-model="row.value" type="text" class="mr-input mr-number" placeholder="Số, vd: 12" :aria-label="`Số dòng ${i + 1}`" />
                <input
                  v-model="row.score"
                  type="text"
                  inputmode="decimal"
                  class="mr-input"
                  placeholder="Điểm vào"
                  :aria-label="`Điểm vào dòng ${i + 1}`"
                />
                <button
                  type="button"
                  class="btn btn-ghost btn-sm mr-remove"
                  aria-label="Xoá dòng"
                  :disabled="rows.length === 1 && !row.value && !row.score"
                  @click="removeRow(i)"
                >
                  <AppIcon name="x" />
                </button>
              </div>
            </div>
            <button type="button" class="btn btn-ghost btn-sm mr-add" @click="addRow">+ Thêm số</button>
          </div>

          <div class="field">
            <label for="note">Ghi chú</label>
            <div class="input-wrap">
              <textarea id="note" v-model="form.note" rows="2" placeholder="Tuỳ chọn"></textarea>
            </div>
          </div>

          <div v-if="deleteAllError" class="alert alert-error">{{ deleteAllError }}</div>
          <div class="form-actions">
            <button type="submit" class="btn btn-primary" :disabled="submitting || !canAdd">
              {{ submitting ? 'Đang thêm...' : 'Thêm số liệu' }}
            </button>
            <button
              type="button"
              class="btn btn-danger"
              :disabled="deletingAll || visibleEntries.length === 0"
              @click="deleteAllEntries"
            >
              {{ deletingAll ? 'Đang xoá...' : 'Xoá tất cả số liệu' }}
            </button>
          </div>
        </form>

        <section class="card list-card">
          <div class="list-inner">
            <h3 class="list-title">Danh sách số liệu {{ form.customerName && !filters.all ? `: ${form.customerName}` : '' }}</h3>

            <!-- Tìm kiếm & bộ lọc (K17): chạy ngay trên dữ liệu đã tải, dùng được cả khi offline -->
            <div class="filter-bar" role="search">
              <div class="field filter-q">
                <div class="input-wrap">
                  <AppIcon name="search" class="filter-icon" />
                  <input v-model="filters.q" type="search" placeholder="Tìm số, ghi chú, điểm" aria-label="Tìm theo từ khoá" />
                </div>
              </div>
              <div class="field filter-date">
                <div class="input-wrap"><input v-model="filters.date" type="date" aria-label="Lọc theo ngày" /></div>
              </div>
              <AppSelect v-model="filters.type" class="filter-type" aria-label="Lọc theo loại">
                <option value="">Mọi hạng mục</option>
                <option v-for="t in betTypes" :key="t" :value="t">{{ betTypeLabel(t) }}</option>
              </AppSelect>
              <label class="filter-all">
                <input v-model="filters.all" type="checkbox" /> Tất cả khách hàng
              </label>
              <button v-if="hasFilter" type="button" class="btn btn-ghost btn-sm" @click="clearFilters">Xoá lọc</button>
            </div>
            <div class="copy-bar">
              <button type="button" class="btn btn-secondary btn-sm" :disabled="filteredEntries.length === 0" @click="copyShown">
                Sao chép {{ filteredEntries.length }} số liệu đang hiện
              </button>
              <label class="filter-all">
                <input v-model="confirmCopy" type="checkbox" /> Hỏi xác nhận trước khi sao chép
              </label>
              <span v-if="copyMessage" class="copy-msg" role="status">{{ copyMessage }}</span>
            </div>

            <div v-if="loading" class="list-empty">Đang tải...</div>
            <div v-else-if="loadError" class="alert alert-error">{{ loadError }}</div>
            <div v-else-if="!form.customerName && !filters.all" class="list-empty">Chọn khách hàng để xem và nhập số liệu.</div>
            <div v-else-if="filteredEntries.length === 0" class="list-empty">
              {{ hasFilter ? 'Không có số liệu nào khớp bộ lọc.' : 'Khách hàng này chưa có số liệu nào.' }}
            </div>
            <div v-else class="entries-table-wrap">
              <table class="table entries-table stack-table">
                <thead>
                  <tr>
                    <th v-if="filters.all">Khách hàng</th>
                    <th>Ngày</th>
                    <th>Hạng mục</th>
                    <th>Số</th>
                    <th>Điểm vào</th>
                    <th>Điểm ra</th>
                    <th>Ghi chú</th>
                    <th class="col-btn">Sửa</th>
                    <th class="col-btn">Xoá</th>
                  </tr>
                </thead>
                <tbody>
                  <template v-for="entry in filteredEntries" :key="entry.id">
                    <tr>
                      <td v-if="filters.all" data-label="Khách hàng">{{ entry.customerName }}</td>
                      <td data-label="Ngày">{{ entry.entryDate }}<span v-if="entry.pending" class="chip pending-chip">Chờ đồng bộ</span></td>
                      <td data-label="Hạng mục">{{ betTypeLabel(entry.betType || 'de') }}</td>
                      <td data-label="Số" class="cell-num">{{ entry.value }}</td>
                      <td data-label="Điểm vào" class="cell-points">{{ entry.score || '-' }}</td>
                      <td data-label="Điểm ra" class="cell-points">{{ entry.result || '-' }}</td>
                      <td data-label="Ghi chú" class="cell-note">{{ entry.note || '-' }}</td>
                      <td class="col-btn">
                        <button class="btn btn-secondary btn-sm" @click="startEdit(entry)">Sửa</button>
                      </td>
                      <td class="col-btn">
                        <button class="btn btn-danger btn-sm" :disabled="deletingId === entry.id" @click="deleteEntry(entry)">
                          {{ deletingId === entry.id ? 'Đang xoá...' : 'Xoá' }}
                        </button>
                      </td>
                    </tr>
                    <tr v-if="deleteErrors[entry.id]" class="row-error">
                      <td :colspan="filters.all ? 9 : 8"><div class="alert alert-error">{{ deleteErrors[entry.id] }}</div></td>
                    </tr>
                  </template>
                </tbody>
              </table>
            </div>
            <div v-if="!loading && !loadError && form.customerName && !filters.all" class="list-stats">
              <h3 class="stats-title">Thống kê: {{ form.customerName }}</h3>
              <p class="page-subtitle" style="margin-top: -8px">
                Tính trên {{ visibleEntries.length }} số liệu của khách hàng đang chọn (điểm vào/ra để trống được tính là 0).
              </p>
              <div class="calc-grid">
                <div class="card calc-card">
                  <div class="calc-label">Tổng điểm vào</div>
                  <div class="calc-value calc-in">{{ formatNumber(totals.vao) }}</div>
                </div>
                <div class="card calc-card">
                  <div class="calc-label">Tổng điểm ra</div>
                  <div class="calc-value calc-out">{{ formatNumber(totals.ra) }}</div>
                </div>
                <div class="card calc-card">
                  <div class="calc-label">Chênh lệch (vào − ra)</div>
                  <div class="calc-value" :class="totals.chenhLech >= 0 ? 'calc-in' : 'calc-out'">
                    {{ formatNumber(totals.chenhLech) }}
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <!-- "Sửa số liệu" popup: customer / type / date are shown as read-only info -->
        <Teleport to="body">
          <div v-if="editingId && editingEntry" class="em-overlay" @mousedown.self="!editSubmitting && cancelEdit()" @keydown.esc="!editSubmitting && cancelEdit()">
            <form class="em-box" role="dialog" aria-modal="true" aria-labelledby="em-title" @submit.prevent="saveEdit(editingId)">
              <div class="em-head">
                <h2 id="em-title" class="em-title">Chỉnh sửa số liệu</h2>
                <button type="button" class="em-close" aria-label="Đóng" :disabled="editSubmitting" @click="cancelEdit">
                  <AppIcon name="x" />
                </button>
              </div>

              <div class="em-info">
                <span class="em-info-name">{{ editForm.customerName }}</span>
                <span class="chip">{{ betTypeLabel(editForm.betType) }}</span>
                <span class="chip">{{ editForm.entryDate }}</span>
              </div>

              <div v-if="editError" class="alert alert-error">{{ editError }}</div>

              <div class="em-grid">
                <div class="field">
                  <label for="em-value">Số liệu</label>
                  <div class="input-wrap"><input id="em-value" ref="emValueInput" v-model="editForm.value" type="text" /></div>
                </div>
                <div class="field">
                  <label for="em-score">Điểm vào</label>
                  <div class="input-wrap"><input id="em-score" v-model="editForm.score" type="text" inputmode="decimal" /></div>
                </div>
              </div>
              <p v-if="editingEntry.result" class="em-result">
                Điểm ra: {{ editingEntry.result }} (sửa ở trang Nhập kết quả)
              </p>
              <div class="field">
                <label for="em-note">Ghi chú</label>
                <div class="input-wrap"><textarea id="em-note" v-model="editForm.note" rows="3"></textarea></div>
              </div>

              <div class="em-foot">
                <button type="button" class="btn btn-secondary" :disabled="editSubmitting" @click="cancelEdit">Huỷ</button>
                <button type="submit" class="btn btn-primary" :disabled="editSubmitting">
                  {{ editSubmitting ? 'Đang lưu...' : 'Lưu thay đổi' }}
                </button>
              </div>
            </form>
          </div>
        </Teleport>

      </div>
    </div>
  </div>
</template>

<style scoped>
/* K17 filters, K18 copy, K13 paste preview, offline markers */
.notice-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}
.filter-bar,
.copy-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 12px;
  margin-bottom: 12px;
}
.filter-bar .field {
  margin-bottom: 0;
}
.filter-q {
  flex: 1 1 200px;
}
.filter-date {
  flex: 0 1 170px;
}
.filter-type {
  flex: 0 1 170px;
}
.filter-icon {
  position: absolute;
  left: 12px;
  top: 50%;
  transform: translateY(-50%);
  color: var(--muted);
  pointer-events: none;
}
.filter-q input {
  padding-left: 38px;
}
.filter-all {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-height: 44px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
}
.filter-all input {
  width: 18px;
  height: 18px;
}
.copy-msg {
  font-size: 14px;
  font-weight: 700;
}
.pending-chip {
  margin-left: 6px;
  font-size: 14px;
}
.paste-box {
  margin-bottom: 16px;
}
.paste-body {
  margin-top: 8px;
}
.paste-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: 8px;
}
.tpl-box,
.preview {
  margin-top: 12px;
  padding: 12px;
  border: 1px solid var(--border);
  border-radius: 12px;
  background: var(--surface);
}
.tpl-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 0 12px;
}
.pv-row {
  display: grid;
  grid-template-columns: 28px minmax(88px, 1fr) minmax(64px, 1fr) minmax(72px, 1fr);
  align-items: center;
  gap: 8px;
  padding: 8px;
  margin-bottom: 6px;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: var(--card);
}
.pv-row.is-uncertain {
  background: var(--warning-soft);
}
.pv-reason {
  grid-column: 1 / -1;
  font-size: 14px;
  color: var(--warning-text);
}

/* Page-local control tokens: a border that stays >=3:1 against the card in
   both themes, and one shared control height so every input lines up. */
.page {
  --ctl-border: var(--input-border);
  --ctl-border-hover: var(--input-border-hover);
  --ctl-h: 44px;
  max-width: var(--page-max);
  padding: 32px 24px 96px;
}

.page-title {
  font-size: 28px;
  line-height: 1.2;
  margin-bottom: 8px;
}

.page-subtitle {
  font-size: 15px;
  line-height: 1.5;
  margin-bottom: 24px;
}

/* ---- Section headings ---- */
.page > h3 {
  font-size: 20px;
  margin: 32px 0 16px;
}

/* ---- Package status ---- */
.quota-card {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
  padding: 16px 20px;
  border-radius: 14px;
  border-left: 4px solid var(--accent);
}
.quota-label {
  font-weight: 700;
  font-size: 16px;
}
.quota-numbers {
  color: var(--muted);
  font-size: 14px;
  margin-top: 4px;
}
.quota-card .chip {
  font-size: 14px;
  padding: 6px 14px;
  white-space: nowrap;
}

.page > .alert {
  font-size: 15px;
  line-height: 1.5;
  padding: 14px 16px;
  margin-bottom: 16px;
  border-radius: 12px;
  border-left: 4px solid currentColor;
}

/* ---- Add form ---- */
.add-form {
  margin-bottom: 8px;
  padding: 24px;
  border-radius: 16px;
  box-shadow: var(--shadow-md);
}
.add-form > h3 {
  font-size: 20px;
  margin: 0 0 24px;
  padding-bottom: 16px;
  border-bottom: 1px solid var(--border);
}

.add-form :deep(.alert),
.entry-card :deep(.alert) {
  font-size: 14px;
  border-radius: 10px;
}

/* ---- Shared controls (add form + inline edit) ---- */
.add-form .field,
.entry-card .field {
  margin-bottom: 16px;
}
.add-form .field label,
.entry-card .field label {
  font-size: 14px;
  font-weight: 700;
  color: var(--text);
  margin-bottom: 8px;
}
.add-form .field input,
.add-form .field select,
.entry-card .field input,
.entry-card .field select {
  height: var(--ctl-h);
  padding: 0 14px;
  font-size: 15px;
  border-radius: 10px;
  border: 1px solid var(--ctl-border);
  background: var(--surface-2);
  color: var(--text);
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.add-form .field textarea,
.entry-card .field textarea {
  min-height: 88px;
  padding: 12px 14px;
  font-size: 15px;
  line-height: 1.5;
  border-radius: 10px;
  border: 1px solid var(--ctl-border);
  background: var(--surface-2);
  color: var(--text);
  resize: vertical;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.add-form .field select,
.entry-card .field select {
  cursor: pointer;
}
.add-form .field input::placeholder,
.add-form .field textarea::placeholder {
  color: var(--muted);
  opacity: 1;
}
.add-form .field :is(input, select, textarea):hover,
.entry-card .field :is(input, select, textarea):hover {
  border-color: var(--ctl-border-hover);
}
.add-form .field :is(input, select, textarea):focus,
.entry-card .field :is(input, select, textarea):focus,
.row-line input:focus {
  outline: none;
  border-color: var(--focus);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--focus) 35%, transparent);
}
.add-form .field :is(input, select, textarea):disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.grid-2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0 16px;
}
.hint {
  font-size: 14px;
  line-height: 1.4;
  color: var(--muted);
  margin: 8px 0 0;
}
.hint a {
  font-weight: 700;
  display: inline-block;
  padding: 4px 0;
}

/* ---- Buttons ---- */
.page :deep(.btn) {
  font-weight: 700;
}
.page :deep(.btn:focus-visible) {
  outline: 3px solid color-mix(in srgb, var(--focus) 60%, transparent);
  outline-offset: 2px;
}
.page :deep(.btn-sm) {
  min-height: 40px;
  padding: 0 16px;
  font-size: 14px;
  border-radius: 10px;
}

/* "Nhập từ ảnh": outlined accent action button */
.ocr-box {
  margin-bottom: 24px;
  padding-bottom: 24px;
  border-bottom: 1px dashed var(--ctl-border);
}
.ocr-box > .btn {
  min-height: 48px;
  font-size: 15px;
  border-radius: 10px;
  border: 1.5px solid var(--accent);
  background: var(--accent-soft);
  color: var(--text);
  box-shadow: var(--shadow-sm);
}
.ocr-box > .btn :deep(.app-icon) {
  width: 20px;
  height: 20px;
  color: var(--accent);
}
.ocr-box > .btn:hover:not(:disabled) {
  background: color-mix(in srgb, var(--accent) 22%, var(--card));
}
.ocr-hint {
  font-size: 14px;
  line-height: 1.5;
  color: var(--muted);
  margin: 8px 0 0;
}
.ocr-result {
  display: flex;
  gap: 16px;
  margin-top: 16px;
}
.ocr-thumb {
  width: 96px;
  height: 96px;
  object-fit: cover;
  border-radius: 10px;
  border: 1px solid var(--ctl-border);
  flex-shrink: 0;
}
.ocr-text-wrap {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.ocr-text-wrap label {
  font-size: 14px;
  font-weight: 700;
  color: var(--muted);
}
.ocr-raw {
  width: 100%;
  font-size: 14px;
  border: 1px solid var(--ctl-border);
  border-radius: 10px;
  padding: 8px 12px;
  background: var(--surface-2);
  color: var(--text);
  resize: vertical;
}

/* Submit CTA */
.add-form > .btn-primary {
  min-height: 48px;
  margin-top: 8px;
  font-size: 16px;
  border-radius: 10px;
  box-shadow: var(--shadow-sm);
}


/* ---- Đề / Lô blocks ---- */
.add-form > .page-subtitle {
  font-size: 14px;
  margin: 0 0 16px !important;
}
.type-row {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-bottom: 16px;
  padding: 16px;
  border: 1px solid var(--ctl-border);
  border-left: 4px solid var(--accent);
  border-radius: 12px;
  background: color-mix(in srgb, var(--accent) 6%, var(--card));
}
.type-row-label {
  align-self: flex-start;
  padding: 4px 12px;
  font-size: 14px;
  font-weight: 800;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--text);
  background: var(--accent-soft);
  border: 1px solid var(--accent);
  border-radius: 999px;
  margin: 0;
}
.rows-wrap {
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 8px;
}
.row-line {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(0, 1fr) 44px;
  gap: 8px;
  align-items: center;
}
.row-number,
.row-score {
  width: auto;
  min-width: 0;
}
.row-line input {
  height: var(--ctl-h);
  padding: 0 14px;
  font-size: 16px;
  border: 1px solid var(--ctl-border);
  border-radius: 10px;
  background: var(--surface-2);
  color: var(--text);
  width: 100%;
  text-align: left;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.row-line input::placeholder {
  color: var(--muted);
  opacity: 1;
}
.row-line input:hover {
  border-color: var(--ctl-border-hover);
}
/* Số: emphasised; Điểm vào: neutral */
.row-number input {
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  border-color: color-mix(in srgb, var(--accent) 60%, var(--ctl-border));
}
.row-score input {
  font-variant-numeric: tabular-nums;
}
/* Delete: square, danger on hover */
.page .row-remove {
  width: 44px;
  height: 44px;
  min-height: 44px;
  padding: 0;
  font-size: 18px;
  color: var(--muted);
  border: 1px solid var(--ctl-border);
  border-radius: 10px;
  background: transparent;
}
.page .row-remove:hover:not(:disabled) {
  color: var(--danger-text);
  border-color: var(--danger-text);
  background: var(--danger-soft);
}
.page .row-remove:disabled {
  opacity: 0.4;
}
/* + Thêm số: dashed add button */
.rows-wrap > .btn {
  align-self: flex-start;
  min-height: 40px;
  color: var(--text);
  border: 1.5px dashed var(--accent);
  background: transparent;
}
.rows-wrap > .btn:hover {
  background: var(--accent-soft);
}

@media (max-width: 640px) {
  .page {
    padding: 24px 16px 96px;
  }
  .page-title {
    font-size: 24px;
  }
  .add-form {
    padding: 16px;
  }
  .grid-2 {
    grid-template-columns: 1fr;
  }
  .type-row {
    padding: 12px;
  }
  .quota-card {
    flex-wrap: wrap;
  }
  .ocr-result {
    flex-direction: column;
  }
  .ocr-thumb {
    width: 100%;
    height: 140px;
  }
}

/* ---- Entry list ---- */
.entry-list {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
  gap: 16px;
}
.entry-card {
  padding: 20px;
  border-radius: 14px;
  display: flex;
  flex-direction: column;
}
.entry-top {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 12px;
}
.entry-top strong {
  flex: 1;
  min-width: 0;
  font-size: 16px;
}
.entry-top .chip {
  font-size: 14px;
  padding: 4px 12px;
}
.entry-top .chip:nth-of-type(1) {
  background: var(--accent-soft);
  color: var(--text);
}
.entry-value {
  font-size: 24px;
  font-weight: 800;
  line-height: 1.2;
  color: var(--accent-strong);
  margin-bottom: 8px;
}
.entry-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 16px;
  font-size: 14px;
  color: var(--muted);
  margin-bottom: 8px;
}
.entry-note {
  font-size: 14px;
  line-height: 1.5;
  color: var(--muted);
  margin-bottom: 8px;
}
.entry-actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: auto;
  padding-top: 12px;
}

/* Empty / loading placeholders */
.page > .card:not(.quota-card):not(.add-form):not(.list-card) {
  padding: 24px;
  border-style: dashed;
  border-radius: 14px;
  color: var(--muted);
  font-size: 15px;
  text-align: center;
}

/* ---- Statistics ---- */
.calc-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
  gap: 16px;
  margin-bottom: 8px;
}
.calc-card {
  text-align: center;
  padding: 20px;
  border-radius: 14px;
}
.calc-label {
  color: var(--muted);
  font-size: 14px;
  margin-bottom: 8px;
}
.calc-value {
  font-size: 26px;
  font-weight: 800;
}
.calc-in {
  color: var(--success-text);
}
.calc-out {
  color: var(--danger-text);
}
/* ---- Compact quick-entry refinements ---- */
/* Violet is reserved for focus / active / CTA: neutral frames elsewhere */
.quota-card {
  border-left: 1px solid var(--border);
}

.add-form {
  padding: 20px 24px;
}
.add-form > h3 {
  margin-bottom: 16px;
  padding-bottom: 12px;
}
.add-form .field {
  margin-bottom: 12px;
}

/* Khách hàng / Ngày ~ 70 / 30 */
.grid-2 {
  grid-template-columns: 7fr 3fr;
}

/* helper text: a bit larger and darker */
.hint,
.ocr-hint {
  font-size: 14px;
  line-height: 1.5;
  color: var(--text-secondary);
}
.add-form > .page-subtitle {
  font-size: 14px;
  color: var(--text-secondary);
  margin-bottom: 12px !important;
}

/* "Nhập từ ảnh": an upload / action area, not an input */
.ocr-box {
  margin-bottom: 16px;
  padding-bottom: 16px;
}
.ocr-box > .btn {
  min-height: 64px;
  flex-direction: column;
  gap: 4px;
  border: 1.5px dashed var(--input-border);
  background: var(--surface);
  color: var(--text-primary);
  box-shadow: none;
}
.ocr-box > .btn :deep(.app-icon) {
  width: 24px;
  height: 24px;
  color: var(--text-secondary);
}
.ocr-box > .btn:hover:not(:disabled) {
  background: var(--primary-soft);
  border-color: var(--primary);
}
.ocr-box > .btn:hover:not(:disabled) :deep(.app-icon) {
  color: var(--primary);
}

/* Đề / Lô: sit side by side on desktop, flat (one light frame, no accent bar) */
.type-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(380px, 1fr));
  gap: 16px;
  margin-bottom: 12px;
}
.type-row {
  margin: 0;
  padding: 12px 16px 16px;
  border: 1px solid var(--border);
  border-left: 1px solid var(--border);
  background: var(--surface);
  gap: 8px;
}
.type-row-label {
  padding: 0;
  font-size: 14px;
  letter-spacing: 0.08em;
  color: var(--text-secondary);
  background: transparent;
  border: 0;
  border-radius: 0;
}

/* Số (narrow, emphasised) vs Điểm vào (wider); no frame per row */
.rows-wrap {
  gap: 8px;
}
.row-line {
  grid-template-columns: minmax(96px, 2fr) minmax(0, 3fr) 40px;
}
.row-line input {
  background: var(--card);
}
.row-number input {
  font-weight: 700;
  border-color: var(--input-border);
}
.row-score input {
  font-weight: 500;
}

/* X and "+ Thêm số": same 40px control height, clear click areas */
.page .row-remove {
  width: 40px;
  height: 40px;
  min-height: 40px;
  border-color: var(--border);
}
.rows-wrap > .btn {
  align-self: flex-start;
  min-height: 40px;
  padding: 0 14px;
  border: 1px dashed var(--input-border);
  color: var(--text-primary);
}
.rows-wrap > .btn:hover {
  background: var(--card);
  border-color: var(--primary);
}

/* Empty state for "Danh sách số liệu" (presentation only) */
.page > .card:not(.quota-card):not(.add-form):not(.list-card) {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 120px;
  padding: 32px 24px;
  background: var(--surface);
  border: 1px dashed var(--input-border);
  color: var(--text-secondary);
  font-size: 15px;
  text-align: center;
}

@media (max-width: 640px) {
  .grid-2 {
    grid-template-columns: 1fr;
  }
  .type-grid {
    grid-template-columns: 1fr;
  }
  .add-form {
    padding: 16px;
  }
}
/* ---- Customer side panel (2nd sidebar) + right-hand workspace ---- */
.entries-layout {
  display: grid;
  grid-template-columns: 260px minmax(0, 1fr);
  gap: 24px;
  align-items: start;
}
.entries-main {
  min-width: 0;
}
.entries-main > h3:first-child,
.entries-main > .add-form + h3 {
  margin-top: 0;
}

.customer-rail {
  position: sticky;
  top: 80px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  max-height: calc(100vh - 104px);
  padding: 16px 12px;
  background: var(--sidebar);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: var(--shadow-sm);
}
.rail-title {
  padding: 0 8px 8px;
  font-size: 14px;
  font-weight: 700;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  color: var(--text-secondary);
}
.rail-list {
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin: 0;
  padding: 0;
  overflow-y: auto;
  list-style: none;
}
.rail-item {
  width: 100%;
  min-height: 44px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 0 12px;
  font-family: var(--font-body);
  font-size: 15px;
  font-weight: 600;
  text-align: left;
  color: var(--text-primary);
  background: transparent;
  border: 1px solid transparent;
  border-radius: 10px;
  cursor: pointer;
  transition: background 0.12s ease;
}
.rail-item:hover {
  background: var(--surface);
}
.rail-item:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 1px;
}
.rail-item.active {
  background: var(--primary-soft);
  border-color: color-mix(in srgb, var(--primary) 35%, transparent);
  font-weight: 700;
}
.rail-name {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.rail-count {
  flex: none;
  min-width: 24px;
  padding: 1px 8px;
  font-size: 12px;
  font-weight: 700;
  text-align: center;
  color: var(--text-secondary);
  background: var(--surface);
  border-radius: 999px;
}
.rail-item.active .rail-count {
  background: var(--card);
  color: var(--text-primary);
}
.rail-empty {
  margin: 0;
  padding: 0 8px;
  font-size: 14px;
  color: var(--text-secondary);
}
.rail-add {
  display: flex;
  align-items: center;
  min-height: 44px;
  margin: 8px 8px 0;
  padding-top: 12px;
  border-top: 1px solid var(--border);
  font-size: 14px;
  font-weight: 600;
}

/* ---- Entries as one horizontal row each (easier to scan than a card grid) ---- */
.entry-list {
  grid-template-columns: 1fr;
  gap: 8px;
}
.entry-card:not(:has(.grid-2)) {
  flex-direction: row;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 20px;
  padding: 12px 16px;
}
.entry-card:not(:has(.grid-2)) .entry-top {
  order: 1;
  flex: 0 0 auto;
  margin: 0;
}
.entry-card:not(:has(.grid-2)) .entry-top strong {
  flex: none;
  max-width: 160px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.entry-card:not(:has(.grid-2)) .entry-value {
  order: 2;
  min-width: 72px;
  margin: 0;
  font-size: 22px;
}
.entry-card:not(:has(.grid-2)) .entry-meta {
  order: 3;
  margin: 0;
  gap: 4px 20px;
}
.entry-card:not(:has(.grid-2)) .entry-note {
  order: 4;
  flex: 1 1 160px;
  margin: 0;
}
.entry-card:not(:has(.grid-2)) .entry-actions {
  order: 5;
  margin: 0 0 0 auto;
  padding: 0;
}
.entry-card > .alert {
  order: 6;
  flex: 1 1 100%;
  margin: 0;
}

/* Stats cards live in the right pane now: a bit tighter */
.entries-main .calc-grid {
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
}
.entries-main .add-form {
  margin-bottom: 0;
}

@media (max-width: 900px) {
  .entries-layout {
    grid-template-columns: minmax(0, 1fr);
    gap: 16px;
  }
  .customer-rail {
    position: static;
    max-height: none;
    padding: 12px;
  }
  /* horizontal chips instead of a tall list */
  .rail-list {
    flex-direction: row;
    gap: 8px;
    padding-bottom: 4px;
    overflow-x: auto;
    overflow-y: visible;
  }
  .rail-list li {
    flex: none;
  }
  .rail-item {
    width: auto;
    min-height: 40px;
    border-color: var(--border);
  }
}
/* ---- "Chỉnh sửa số liệu" modal ---- */
.em-overlay {
  position: fixed;
  inset: 0;
  z-index: 90;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  background: var(--overlay);
  overflow-y: auto;
}
.em-box {
  width: 100%;
  max-width: 560px;
  margin: auto;
  padding: 24px;
  background: var(--card);
  border: 1px solid var(--input-border);
  border-radius: 16px;
  box-shadow: var(--shadow-lg);
}
.em-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}
.em-title {
  margin: 0;
  font-size: 20px;
  line-height: 1.3;
}
.em-close {
  flex: none;
  width: 36px;
  height: 36px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0;
  font-size: 22px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  cursor: pointer;
}
.em-close:hover:not(:disabled) {
  background: var(--primary-soft);
}
.em-close:focus-visible {
  outline: 3px solid color-mix(in srgb, var(--primary) 55%, transparent);
  outline-offset: 2px;
}
.em-info {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 16px;
  padding: 10px 12px;
  background: var(--surface);
  border-radius: 10px;
}
.em-info-name {
  margin-right: 4px;
  font-size: 15px;
  font-weight: 700;
  color: var(--text-primary);
}
.em-info .chip {
  font-size: 14px;
  padding: 3px 10px;
  background: var(--card);
  border: 1px solid var(--border);
}
.em-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0 16px;
}
.em-box .field {
  margin-bottom: 12px;
}
.em-box .field label {
  margin-bottom: 6px;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
}
.em-box .field input,
.em-box .field textarea {
  padding: 0 14px;
  font-size: 15px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
}
.em-box .field input {
  height: 44px;
}
.em-box .field textarea {
  padding: 10px 14px;
  min-height: 84px;
  line-height: 1.5;
  resize: vertical;
}
.em-box .field input:hover,
.em-box .field textarea:hover {
  border-color: var(--input-border-hover);
}
.em-box .field input:focus,
.em-box .field textarea:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.em-result {
  margin: -4px 0 12px;
  font-size: 14px;
  color: var(--text-secondary);
}
.em-box .alert {
  margin-bottom: 12px;
  font-size: 14px;
  border-radius: 10px;
}
.em-foot {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 8px;
  padding-top: 16px;
  border-top: 1px solid var(--border);
}
.em-foot .btn {
  min-height: 40px;
  padding: 0 18px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 10px;
}
@media (max-width: 560px) {
  .em-box {
    padding: 20px 16px;
  }
  .em-grid {
    grid-template-columns: 1fr;
  }
  .em-foot {
    flex-direction: column-reverse;
  }
  .em-foot .btn {
    width: 100%;
  }
}
/* ---- Compact one-page workspace (desktop): rail flush against the main
   sidebar, form on the left, entries + stats on the right ---- */
@media (min-width: 901px) {
  .page {
    --rail-w: 220px;
    max-width: none;
    margin: 0;
    padding: 10px 24px 12px calc(var(--rail-w) + 14px);
  }
  .page-title {
    font-size: 22px;
    margin-bottom: 2px;
  }
  .page > .page-subtitle {
    margin-bottom: 8px;
    font-size: 14px;
  }
  .quota-card {
    margin-bottom: 8px;
    padding: 6px 16px;
  }
  .quota-label {
    font-size: 15px;
  }
  .quota-numbers {
    margin-top: 0;
    font-size: 14px;
  }
  .page > .alert {
    margin-bottom: 12px;
    padding: 8px 14px;
  }

  /* rail: a full-height strip attached to the main sidebar (248px) */
  .entries-layout {
    display: block;
  }
  .customer-rail {
    position: fixed;
    left: 248px;
    top: 64px;
    bottom: 0;
    z-index: 5;
    width: var(--rail-w);
    max-height: none;
    padding: 16px 12px;
    background: var(--sidebar);
    border: 0;
    border-right: 1px solid var(--border);
    border-radius: 0;
    box-shadow: none;
  }
  /* list takes only its own height so "+ Thêm khách hàng mới" sits right below
     the last customer; a long list shrinks and scrolls, keeping the link visible */
  .rail-list {
    flex: 0 1 auto;
    min-height: 0;
  }

  /* compact form */
  .add-form {
    padding: 12px 18px 14px;
    border-radius: 14px;
  }
  .add-form > h3 {
    margin-bottom: 10px;
    padding-bottom: 8px;
    font-size: 17px;
  }
  .ocr-box {
    margin-bottom: 8px;
    padding-bottom: 8px;
  }
  .ocr-box > .btn {
    min-height: 44px;
    flex-direction: row;
    gap: 8px;
  }
  .ocr-hint {
    margin-top: 4px;
    font-size: 14px;
  }
  .add-form .field {
    margin-bottom: 6px;
  }
  .add-form .field label {
    margin-bottom: 3px;
    font-size: 14px;
  }
  .grid-2 {
    grid-template-columns: 1fr 180px;
    gap: 0 12px;
  }
  .hint {
    margin-top: 4px;
  }
  .add-form > .page-subtitle {
    margin-bottom: 8px !important;
    font-size: 14px;
  }
  .type-grid {
    grid-template-columns: 1fr;
    gap: 8px;
    margin-bottom: 8px;
  }
  .type-row {
    padding: 8px 12px 10px;
    gap: 6px;
  }
  .row-line input {
    height: 40px;
  }
  /* "+ Thêm số" sits in the block header, level with the Đề / Lô label */
  .type-row {
    position: relative;
  }
  .rows-wrap > .btn {
    position: absolute;
    top: 6px;
    right: 10px;
    min-height: 30px;
    padding: 0 10px;
    font-size: 14px;
  }
  .type-row-label {
    min-height: 30px;
    display: flex;
    align-items: center;
  }
  .add-form .field textarea {
    min-height: 52px;
  }
  .add-form > .btn-primary {
    margin-top: 4px;
  }

  .entry-card:not(:has(.grid-2)) {
    padding: 8px 14px;
  }
  .entry-card:not(:has(.grid-2)) .entry-value {
    font-size: 20px;
  }
  .entries-main > .page-subtitle,
  .entries-main > h3 + .page-subtitle {
    margin: 0 0 8px;
    font-size: 14px;
  }
  .entries-main .calc-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 12px;
  }
  .entries-main .calc-card {
    padding: 10px 12px;
  }
  .entries-main .calc-value {
    font-size: 20px;
  }
  .entries-main .calc-label {
    margin-bottom: 2px;
    font-size: 14px;
  }
  .entries-main > .card:not(.add-form):not(.entry-card):not(.list-card) {
    min-height: 0;
    padding: 16px;
  }
}
/* Two-column workspace only when there is room for form + a full-width table side by side */
@media (min-width: 1560px) {
  /* workspace: form | entries + stats */
  .entries-main {
    display: grid;
    /* form column = previous 460px + the width of the "Nhập số" title (~87px) */
    grid-template-columns: minmax(400px, 547px) minmax(0, 1fr);
    /* 5 content rows on the right + a trailing 1fr row that absorbs the form's extra height */
    grid-template-rows: repeat(5, auto) minmax(0, 1fr);
    gap: 0 20px;
    align-items: start;
  }
  .entries-main > :not(.add-form) {
    grid-column: 2;
  }
  .entries-main > .add-form {
    grid-column: 1;
    grid-row: 1 / -1;
  }
  .entries-main:not(:has(.add-form)) > * {
    grid-column: 1 / -1;
  }
  .entries-main > h3 {
    margin: 0 0 8px;
    font-size: 17px;
  }

  /* right column: list scrolls inside, stats stay in view */
  .entry-list {
    max-height: calc(100vh - 400px);
    min-height: 120px;
    overflow-y: auto;
    padding-right: 4px;
  }
}

/* customer picker: side list on desktop, dropdown on phones / small tablets */
.rail-select {
  display: none;
}
@media (max-width: 900px) {
  .rail-select {
    display: block;
  }
  .rail-list {
    display: none;
  }
  .customer-rail .rail-title {
    padding-bottom: 4px;
  }
}
/* ---- Manual entry rows: Hạng mục | Số | Điểm vào ---- */
.manual-rows {
  margin-bottom: 12px;
}
.mr-head,
.mr-row {
  display: grid;
  grid-template-columns: 28px minmax(96px, 1fr) minmax(64px, 1fr) minmax(80px, 1.2fr) 40px;
  gap: 8px;
  align-items: center;
}
.mr-head {
  margin-bottom: 4px;
  font-size: 14px;
  font-weight: 700;
  color: var(--text-secondary);
}
.mr-row {
  margin-bottom: 8px;
}
.mr-row .mr-type {
  --ctl-h: 40px;
}
.mr-input {
  width: 100%;
  min-width: 0;
  height: 40px;
  padding: 0 12px;
  font-family: var(--font-body);
  font-size: 15px;
  color: var(--text-primary);
  background: var(--surface);
  border: 1px solid var(--input-border);
  border-radius: 10px;
  transition: border-color 0.15s ease, box-shadow 0.15s ease;
}
.mr-number {
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.mr-input::placeholder {
  color: var(--text-secondary);
  opacity: 1;
}
.mr-input:hover {
  border-color: var(--input-border-hover);
}
.mr-input:focus {
  outline: none;
  border-color: var(--primary);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--primary) 35%, transparent);
}
.page .mr-remove {
  width: 40px;
  height: 40px;
  min-height: 40px;
  padding: 0;
  font-size: 18px;
  color: var(--text-secondary);
  border: 1px solid var(--border);
  border-radius: 10px;
}
.page .mr-remove:hover:not(:disabled) {
  color: var(--danger-text);
  border-color: var(--danger-text);
  background: var(--danger-soft);
}
.page .mr-remove:disabled {
  opacity: 0.4;
}
.page .mr-add {
  min-height: 36px;
  padding: 0 14px;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
  border: 1px dashed var(--input-border);
  border-radius: 10px;
}
.page .mr-add:hover {
  background: var(--surface);
  border-color: var(--primary);
}

/* ---- Entries table: Ngày | Hạng mục | Số | Điểm vào | Điểm ra | Ghi chú | Sửa | Xoá ---- */
.entries-table-wrap {
  overflow: auto;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: var(--shadow-sm);
}
.entries-table {
  min-width: 0;
  font-size: 14px;
}
.entries-table td:first-child {
  white-space: nowrap;
}
.entries-table th {
  position: sticky;
  top: 0;
  z-index: 1;
  padding: 10px 8px;
  font-size: 14px;
  font-weight: 700;
  letter-spacing: 0.05em;
  white-space: nowrap;
  background: var(--surface);
}
.entries-table td {
  padding: 10px 8px;
  vertical-align: middle;
}
.entries-table tbody tr:hover {
  background: color-mix(in srgb, var(--primary) 5%, transparent);
}
.entries-table .cell-points {
  text-align: right;
  font-variant-numeric: tabular-nums;
}
.entries-table th {
  text-align: center;
}
.entries-table .cell-num {
  font-size: 16px;
  font-weight: 800;
  font-variant-numeric: tabular-nums;
  color: var(--text-primary);
}
.entries-table .cell-note {
  max-width: 130px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--text-secondary);
}
.entries-table .col-btn {
  width: 1%;
  padding-left: 4px;
  padding-right: 4px;
  text-align: center;
  white-space: nowrap;
}
.entries-table .col-btn .btn {
  min-height: 32px;
  padding: 0 10px;
  font-size: 14px;
  font-weight: 600;
  border-radius: 8px;
}
.entries-table .row-error td {
  padding: 0 12px 8px;
}
.entries-table .row-error .alert {
  margin: 0;
}

@media (min-width: 1560px) {
  .entries-table-wrap {
    max-height: calc(100vh - 380px);
    min-height: 120px;
  }
}

/* phones: one card per entry; Sửa / Xoá side by side at the bottom */
@media (max-width: 640px) {
  .entries-table.stack-table tbody tr:not(.row-error) {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0 8px;
  }
  .entries-table.stack-table tbody tr:not(.row-error) td[data-label] {
    grid-column: 1 / -1;
  }
  .entries-table.stack-table tbody tr:not(.row-error) .col-btn {
    display: block;
    width: auto !important;
    padding: 8px 0 4px !important;
    text-align: center !important;
  }
  .entries-table.stack-table .col-btn .btn {
    width: 100%;
    min-height: 40px;
  }
  .entries-table.stack-table .cell-note {
    max-width: none;
    white-space: normal;
  }
  .entries-table-wrap {
    background: transparent;
    border: 0;
    box-shadow: none;
    overflow: visible;
  }
}

/* narrow phones: [tick][hạng mục][x] on the first line, Số + Điểm vào below */
@media (max-width: 480px) {
  .mr-head {
    display: none;
  }
  .mr-row {
    grid-template-columns: 28px minmax(0, 1fr) minmax(0, 1.4fr) 40px;
    gap: 8px;
    padding-bottom: 8px;
    border-bottom: 1px dashed var(--border);
  }
  .mr-row .mr-check {
    grid-column: 1;
    grid-row: 1;
  }
  .mr-row .mr-type {
    grid-column: 2 / 4;
    grid-row: 1;
  }
  .mr-row .mr-remove {
    grid-column: 4;
    grid-row: 1;
  }
  .mr-row .mr-number {
    grid-column: 1 / 3;
  }
  .mr-row .mr-input:not(.mr-number) {
    grid-column: 3 / 5;
  }
}
/* ---- Entries card: title + table + totals in one card, level with the form ---- */
.list-card {
  padding: 12px 16px 14px;
  border-radius: 14px;
}
.list-inner {
  display: flex;
  flex-direction: column;
}
.list-title {
  margin: 0 0 10px;
  padding-bottom: 8px;
  font-size: 17px;
  border-bottom: 1px solid var(--border);
}
.list-empty {
  padding: 28px 16px;
  text-align: center;
  font-size: 15px;
  color: var(--text-secondary);
  background: var(--surface);
  border: 1px dashed var(--input-border);
  border-radius: 12px;
}
.list-stats {
  flex: none;
  margin-top: 12px;
}
.stats-title {
  margin: 0 0 2px;
  font-size: 15px;
}
.list-stats .page-subtitle {
  margin: 0 0 8px !important;
  font-size: 14px;
}
.list-stats .calc-grid {
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  margin-bottom: 0;
}
.list-stats .calc-card {
  padding: 8px 10px;
}
.list-stats .calc-value {
  font-size: 18px;
}
.list-stats .calc-label {
  margin-bottom: 2px;
  font-size: 14px;
}

/* table: fixed column widths (Ghi chú takes the rest) + vertical rules */
.entries-table-wrap {
  flex: 1;
  min-height: 0;
  max-height: 62vh;
  overflow: auto;
  background: transparent;
  border: 1px solid var(--border);
  border-radius: 10px;
  box-shadow: none;
}
.entries-table {
  table-layout: fixed;
  width: 100%;
  min-width: 540px;
  font-size: 14px;
  border-collapse: separate;
  border-spacing: 0;
}
.entries-table th,
.entries-table td {
  border-right: 1px solid var(--border);
}
.entries-table th:last-child,
.entries-table td:last-child {
  border-right: 0;
}
.entries-table th:nth-child(1) { width: 90px; }
.entries-table th:nth-child(2) { width: 76px; }
.entries-table th:nth-child(3) { width: 56px; }
.entries-table th:nth-child(4),
.entries-table th:nth-child(5) { width: 78px; }
.entries-table th:nth-child(7),
.entries-table th:nth-child(8) { width: 54px; }
.entries-table td {
  border-bottom: 1px solid var(--border);
}
.entries-table tbody tr:last-child td {
  border-bottom: 0;
}
.entries-table .cell-note {
  max-width: none;
  overflow: visible;
  white-space: normal;
  overflow-wrap: anywhere;
}
.entries-table .col-btn .btn {
  padding: 0 8px;
}
.entries-table .row-error td {
  border-right: 0;
}

@media (min-width: 1560px) {
  /* form keeps its natural height; the list card grows with its rows and only
     scrolls inside once it would run off the screen */
  .entries-main {
    grid-template-rows: auto;
    align-items: start;
  }
  .entries-main > .add-form {
    grid-row: 1;
  }
  .entries-main > .list-card {
    grid-column: 2;
    grid-row: 1;
    min-height: 0;
  }
  .entries-main:not(:has(.add-form)) > .list-card {
    grid-column: 1 / -1;
  }
  .entries-table-wrap {
    flex: 0 1 auto;
    max-height: calc(100vh - 330px);
  }
}

@media (max-width: 640px) {
  .entries-table.stack-table {
    table-layout: auto;
    min-width: 0;
  }
  .entries-table.stack-table th,
  .entries-table.stack-table td {
    border-right: 0;
  }
  .entries-table.stack-table tbody tr:not(.row-error) {
    border: 1px solid var(--border);
  }
  .list-card {
    padding: 12px;
  }
}

/* no dashed divider under the image-import block */
.ocr-box {
  border-bottom: 0;
  padding-bottom: 0;
}

/* ---- Row selection + bulk edit ---- */
.mr-check {
  width: 28px;
  height: 40px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
}
.mr-head .mr-check {
  height: auto;
}
.mr-check input {
  width: 18px;
  height: 18px;
  margin: 0;
  accent-color: var(--primary);
  cursor: pointer;
}
.mr-row.is-selected .mr-input {
  border-color: color-mix(in srgb, var(--primary) 55%, var(--input-border));
}
.mr-bulk {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
  padding: 8px 10px;
  background: var(--primary-soft);
  border: 1px solid color-mix(in srgb, var(--primary) 30%, transparent);
  border-radius: 10px;
}
.mr-bulk-count {
  flex: none;
  font-size: 13px;
  font-weight: 700;
  color: var(--text-primary);
}
.mr-bulk .mr-bulk-type {
  --ctl-h: 36px;
  flex: 1 1 130px;
  width: auto;
  min-width: 120px;
}
.mr-bulk .mr-bulk-score {
  flex: 1 1 110px;
  width: auto;
  min-width: 100px;
  height: 36px;
}
.mr-bulk-apply,
.mr-bulk-delete {
  flex: none;
  min-height: 36px;
  padding: 0 14px;
  font-weight: 600;
  border-radius: 10px;
}
.form-actions {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}
.form-actions .btn {
  width: 100%;
}
.mr-list {
  max-height: 340px;
  overflow-y: auto;
  padding: 2px 2px 0 0;
}
</style>
