// Test helper: node serve.mjs <distDir> <listenPort> <backendPort>
// Serves a built frontend (SPA fallback) on 127.0.0.1:<listenPort> and proxies /api to the backend.
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
import net from 'node:net'
const [dist, port, backend] = [process.argv[2], Number(process.argv[3]), Number(process.argv[4])]
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json', '.png': 'image/png', '.gz': 'application/octet-stream' }
const server = http.createServer((req, res) => {
  if (req.url.startsWith('/api/')) {
    const p = http.request({ host: '127.0.0.1', port: backend, path: req.url, method: req.method, headers: { ...req.headers, host: `127.0.0.1:${backend}` } }, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res) })
    p.on('error', () => { res.writeHead(502); res.end('{"error":"backend down"}') })
    return req.pipe(p)
  }
  let file = path.join(dist, decodeURIComponent(req.url.split('?')[0]))
  // Next.js static export writes /entries as entries.html (same rule as the nginx `try_files $uri $uri.html`)
  if (!path.extname(file) && fs.existsSync(file + '.html')) file += '.html'
  if (!file.startsWith(dist) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(dist, 'index.html')
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' })
  fs.createReadStream(file).pipe(res)
})
// WebSocket (/api/ws/calls): pass the upgrade through to the backend as a raw TCP pipe
server.on('upgrade', (req, socket, head) => {
  const up = net.connect(backend, '127.0.0.1', () => {
    const headers = Object.entries({ ...req.headers, host: `127.0.0.1:${backend}` }).map(([k, v]) => `${k}: ${v}`).join('\r\n')
    up.write(`${req.method} ${req.url} HTTP/1.1\r\n${headers}\r\n\r\n`)
    if (head?.length) up.write(head)
    socket.pipe(up); up.pipe(socket)
  })
  up.on('error', () => socket.destroy()); socket.on('error', () => up.destroy())
  up.on('close', () => socket.destroy()); socket.on('close', () => up.destroy())
})
server.listen(port, '127.0.0.1', () => console.log('serving', dist, 'on', port, '->', backend))
