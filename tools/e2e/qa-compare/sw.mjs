import * as H from './h.mjs'
const br=await H.launch(); const A=await H.adminToken()
const reg=JSON.parse((await import('node:fs')).readFileSync('seed.json'))
for (const tag of ['next','vue']) {
  const site=H.SITES[tag]
  const p=await H.page(br,site,A,'admin'); await H.go(p,site+'/admin/stats')
  await p.evaluate(()=>navigator.serviceWorker.ready); await H.sleep(1500)
  const st=await p.evaluate(async()=>({ctl:!!navigator.serviceWorker.controller,keys:await caches.keys(),n:(await (await caches.open((await caches.keys())[0])).keys()).map(r=>new URL(r.url).pathname)}))
  console.log(tag,'sw',JSON.stringify(st))
  await H.go(p,site+'/admin/users'); await H.go(p,site+'/admin/stats'); await H.sleep(500)
  await p.setOfflineMode(true)
  for (const r of ['/admin/stats','/admin/users','/admin/settings','/']) {
    try{ await p.goto(site+r,{waitUntil:'load',timeout:8000}); await H.sleep(1500); const t=(await H.text(p)).replace(/\n+/g,' | ').slice(0,120); console.log(tag,'OFFLINE',r,'->',new URL(p.url()).pathname,'|',t)}catch(e){console.log(tag,'OFFLINE',r,'ERR',e.message.slice(0,80))}
  }
  await p.setOfflineMode(false)
}
await br.close()
