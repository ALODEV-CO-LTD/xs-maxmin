import * as H from './h.mjs'
import fs from 'node:fs'
const seed=JSON.parse(fs.readFileSync('seed.json'))
const br=await H.launch(); const A=await H.adminToken()
const pol=(await H.call('GET','/admin/security-policy',null,A)).j; console.log(JSON.stringify(pol).slice(0,300))
const cur=pol.policy||pol
await H.call('PUT','/admin/security-policy',{...cur,blurOnHideEnabled:true,watermarkEnabled:true},A)
for (const tag of ['next','vue']) {
  const me=tag==='next'?seed.nx:seed.vu; const site=H.SITES[tag]
  const l=(await H.call('POST','/auth/login',{username:me.u,password:'Pass-1234x'})).j; const T=(await H.call('POST','/auth/step2',{pendingToken:l.pendingToken,password:'Second-1234'})).j.token
  const p=await H.page(br,site,T,'user'); await p.evaluate(()=>{localStorage.removeItem('xoso_privacy');localStorage.removeItem('xoso_locked')}); await H.go(p,site+'/customers'); await H.sleep(1000)
  console.log(tag,'watermark?',await p.evaluate(()=>!!document.querySelector('.sw-root,.watermark,[class*=watermark]')))
  await p.evaluate(()=>window.dispatchEvent(new Event('blur'))); await H.sleep(400)
  console.log(tag,'away class',await p.evaluate(()=>document.documentElement.className),'veil',await p.evaluate(()=>!!document.querySelector('.pl-veil')))
  await p.screenshot({path:`shots/blur-${tag}.png`})
  await p.evaluate(()=>window.dispatchEvent(new Event('focus'))); await H.sleep(400); console.log(tag,'after focus',await p.evaluate(()=>document.documentElement.className))
}
await H.call('PUT','/admin/security-policy',{...cur},A)
await br.close()
