// Test helper: node serve.mjs <distDir> <listenPort> <backendPort>
// Serves a built frontend (SPA fallback) on 127.0.0.1:<listenPort> and proxies /api to the backend.
import http from 'node:http'
import fs from 'node:fs'
import path from 'node:path'
const [dist, port, backend] = [process.argv[2], Number(process.argv[3]), Number(process.argv[4])]
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.json': 'application/json', '.png': 'image/png', '.gz': 'application/octet-stream' }
http.createServer((req, res) => {
  if (req.url.startsWith('/api/')) {
    const p = http.request({ host: '127.0.0.1', port: backend, path: req.url, method: req.method, headers: { ...req.headers, host: `127.0.0.1:${backend}` } }, (r) => { res.writeHead(r.statusCode, r.headers); r.pipe(res) })
    p.on('error', () => { res.writeHead(502); res.end('{"error":"backend down"}') })
    return req.pipe(p)
  }
  let file = path.join(dist, decodeURIComponent(req.url.split('?')[0]))
  if (!file.startsWith(dist) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(dist, 'index.html')
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' })
  fs.createReadStream(file).pipe(res)
}).listen(port, '127.0.0.1', () => console.log('serving', dist, 'on', port, '->', backend))
