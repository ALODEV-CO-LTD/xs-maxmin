import * as H from './h.mjs'
import fs from 'node:fs'
const seed=JSON.parse(fs.readFileSync('seed.json'))
const br=await H.launch(); const A=await H.adminToken()
for (const tag of ['next','vue']) {
  const me=tag==='next'?seed.nx:seed.vu; const site=H.SITES[tag]
  const l=(await H.call('POST','/auth/login',{username:me.u,password:'Pass-1234x'})).j; const T=(await H.call('POST','/auth/step2',{pendingToken:l.pendingToken,password:'Second-1234'})).j.token
  const p=await H.page(br,site,T,'user')
  await p.evaluate(()=>{localStorage.setItem('xoso_privacy',JSON.stringify({autoLockMinutes:1,hideLockSeconds:0,blurOnHide:true}));localStorage.setItem('xoso_last_active',String(Date.now()-120000))})
  await H.go(p,site+'/customers'); await H.sleep(800)
  const t=(await H.text(p)).replace(/\n+/g,' | ').slice(0,200); console.log(tag,'locked view:',t)
  await p.screenshot({path:`shots/lock-${tag}.png`})
  console.log(tag,'locked flag',await p.evaluate(()=>localStorage.getItem('xoso_locked')), 'inert app', await p.evaluate(()=>document.getElementById('app')?.inert))
  const pw=await p.$('input[type=password]'); if(pw){ await pw.type('wrong-pw'); await p.keyboard.press('Enter'); await H.sleep(1200); console.log(tag,'wrong:',(await H.text(p)).replace(/\n+/g,' | ').slice(0,200)); await p.keyboard.down('Control'); await p.evaluate(()=>{document.querySelector('input[type=password]').select()}); await p.keyboard.up('Control'); await p.keyboard.press('Backspace'); await p.type('input[type=password]','Pass-1234x'); await p.keyboard.press('Enter'); await H.sleep(1500); console.log(tag,'after right:',(await H.text(p)).replace(/\n+/g,' | ').slice(0,120),'locked',await p.evaluate(()=>localStorage.getItem('xoso_locked'))) }
  // reload persists lock
  await p.evaluate(()=>{localStorage.setItem('xoso_locked','1')}); await H.go(p,site+'/customers'); console.log(tag,'reload locked?',/mở khoá|Mở khoá|đã khoá|Nhập mật khẩu/i.test(await H.text(p)))
  // logout from lock screen?
  console.log(tag,'controls',(await H.controls(p)).filter(x=>/Đăng xuất|Mở|Xác nhận/.test(x)).join(';'))
}
await br.close()
