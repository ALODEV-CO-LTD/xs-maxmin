import * as H from './h.mjs'
import fs from 'node:fs'
const seed=JSON.parse(fs.readFileSync('seed.json'))
const br=await H.launch(); const A=await H.adminToken()
let t0; const reqs=(await H.call('GET','/admin/recovery-requests',null,A)).j; const list=reqs.requests||reqs
for (const tag of (process.argv[2]||'next,vue').split(',')) {
  const me=tag==='next'?seed.nx:seed.vu; const site=H.SITES[tag]
  const rq=list.find(r=>r.username===me.u); const ap=(await H.call('POST','/admin/recovery-requests/'+rq.id,{action:'approve'},A)); const ticket=ap.j.ticket; console.log(tag,'ticket',ap.s,!!ticket)
  const cx=await br.createBrowserContext(); const p=await cx.newPage(); await p.setViewport({width:1000,height:800}); await p.goto(site+'/login',{waitUntil:'networkidle0'})
  await H.click(p,'Quên mật khẩu'); await H.click(p,'Tôi đã có mã hỗ trợ'); 
  console.log(tag,(await H.controls(p)).slice(-6).join(';'))
  const ins=await p.$$('input'); console.log(tag,'inputs',ins.length)
  await ins[0].type(me.u); await ins[1].type(ticket); await ins[2].type('weak'); await ins[3].type('weak'); await p.click('button[type=submit]'); await H.sleep(900); console.log(tag,'weak ->',(await H.text(p)).replace(/\n+/g,' | ').slice(60,260))
  if(/Đặt lại mật khẩu.*Quay lại đăng nhập/.test(t0=(await H.text(p)).replace(/\n+/g,' | '))) for (const i of [2,3]) { const e=(await p.$$('input'))[i]; await e.focus(); await e.evaluate(x=>x.select()); await p.keyboard.press('Backspace'); await e.type('Tick-New-Pass-77x') }
  await p.click('button[type=submit]'); await H.sleep(1500); const t=(await H.text(p)).replace(/\n+/g,' | '); console.log(tag,'ok ->',t.slice(60,300))
  console.log(tag,'login new pw',(await H.call('POST','/auth/login',{username:me.u,password:'Tick-New-Pass-77x'})).s)
  await H.call('PATCH','/admin/users/'+me.id,{newPassword:'Pass-1234x'},A)
  await cx.close()
}
await br.close()
