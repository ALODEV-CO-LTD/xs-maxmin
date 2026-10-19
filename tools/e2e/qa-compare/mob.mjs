import * as H from './h.mjs'
const br=await H.launch(); const A=await H.adminToken()
const adm=['/admin/users','/admin/stats','/admin/settings','/admin/payment-requests','/admin/messages','/admin/notices','/admin/staff','/account']
for (const theme of ['dark','light']) for (const tag of ['next','vue']) {
  const res=[]
  const p=await H.page(br,H.SITES[tag],A,'admin',390,844)
  await p.evaluate((t)=>{localStorage.setItem('theme',t);localStorage.setItem('xoso_theme',t)},theme)
  for(const r of adm){ await H.go(p,H.SITES[tag]+r); const o=await p.evaluate(()=>({sw:document.documentElement.scrollWidth,cw:document.documentElement.clientWidth,bg:getComputedStyle(document.body).backgroundColor, th:document.documentElement.dataset.theme||document.documentElement.className})); res.push(r+':'+(o.sw>o.cw?'OVERFLOW '+o.sw:'ok')+' '+o.bg+' '+o.th); await p.screenshot({path:`shots/mob-${tag}-${theme}-${r.replace(/\W/g,'_')}.png`}) }
  console.log(tag,theme,res.join('\n   '))
}
await br.close()
