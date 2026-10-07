// "Today" as the user's own calendar date (YYYY-MM-DD from the browser's
// local time). toISOString() would give the UTC date, which in Vietnam
// (UTC+7) is still "yesterday" between 0h and 7h.
export function localDateString(d = new Date()) {
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${m}-${day}`
}
export const today = () => localDateString()
