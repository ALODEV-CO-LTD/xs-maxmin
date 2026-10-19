// The viewer-watermark tile and the exact style text of ScreenWatermark (see components/ScreenWatermark.tsx).
const pad = (n) => String(n).padStart(2, '0')
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[c])

// Tile: name · username on one line, minute + id tail on the next, rotated.
export function watermarkTile(u, d, dark) {
  if (!u) return ''
  const when = `${pad(d.getHours())}:${pad(d.getMinutes())} ${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()}`
  const who = `${u.name || ''} · ${u.username || ''}`.slice(0, 40)
  const tail = String(u.id || '').slice(-4)
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" width="380" height="210">` +
    `<g transform="rotate(-24 190 105)" fill="${dark ? 'rgba(255,255,255,0.15)' : 'rgba(30,41,59,0.20)'}" font-family="system-ui,sans-serif" font-size="15" font-weight="600" text-anchor="middle">` +
    `<text x="190" y="98">${esc(who)}</text><text x="190" y="120" font-size="13" font-weight="500">${esc(when)} · ${esc(tail)}</text></g></svg>`
  return `url("data:image/svg+xml;utf8,${encodeURIComponent(svg)}")`
}

export function watermarkStyle(tile) {
  return (
    `position:fixed!important;inset:0!important;z-index:2147483000!important;pointer-events:none!important;display:block!important;` +
    `visibility:visible!important;opacity:1!important;background-image:${tile}!important;background-repeat:repeat!important;`
  )
}

