import * as H from './h.mjs'
const br=await H.launch()
for (const tag of ['next','vue']) {
  const site=H.SITES[tag]; const cx=await br.createBrowserContext(); const p=await cx.newPage(); await p.setViewport({width:390,height:844})
  await p.goto(site+'/login',{waitUntil:'networkidle0'})
  const th=()=>p.evaluate(()=>document.documentElement.dataset.theme||document.documentElement.className)
  const a=await th(); await H.click(p,'',{sel:'button[aria-label*="giao diện"],button[title*="giao diện"]'}); const b=await th()
  await p.reload({waitUntil:'networkidle0'}); const c=await th()
  console.log(tag,'theme',a,'->',b,'reload',c)
  for(const r of ['/login','/register']){ await p.goto(site+r,{waitUntil:'networkidle0'}); console.log(tag,r,'overflow',await p.evaluate(()=>document.documentElement.scrollWidth>document.documentElement.clientWidth)); await p.screenshot({path:`shots/m390-${tag}${r.replace('/','-')}.png`}) }
  console.log(tag,'head',JSON.stringify(await p.evaluate(()=>({manifest:document.querySelector('link[rel=manifest]')?.href,tc:document.querySelector('meta[name=theme-color]')?.content,vp:document.querySelector('meta[name=viewport]')?.content,apple:!!document.querySelector('link[rel=apple-touch-icon]'),title:document.title}))))
  await cx.close()
}
await br.close()
