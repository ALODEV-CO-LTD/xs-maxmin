// What the Tính toán pages share (web): the customer and day chosen in Nhập số. Tính điểm opens on them, so the person only picks a
// customer and a day once. Kept in sessionStorage (this tab only, gone when it closes); never sent anywhere.
const KEY = 'calc-sync'

export function writeCalcSync({ customer = '', date = '' } = {}) {
  try {
    sessionStorage.setItem(KEY, JSON.stringify({ customer, date }))
  } catch {
    /* private mode */
  }
}

export function readCalcSync() {
  try {
    const v = JSON.parse(sessionStorage.getItem(KEY) || 'null')
    return { customer: typeof v?.customer === 'string' ? v.customer : '', date: typeof v?.date === 'string' ? v.date : '' }
  } catch {
    return { customer: '', date: '' }
  }
}
