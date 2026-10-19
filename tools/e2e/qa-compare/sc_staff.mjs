export default async ({p,H,site,me,snap,tag,A})=>{
  const sn='stf'+(tag==='next'?'n':'v')+Date.now().toString(36).slice(-4)
  await H.go(p,site+'/admin/staff'); await H.click(p,'+ Tạo tài khoản')
  const ins=await p.$$('input[type=text]'); await ins[0].type('Nhan vien '+tag); await ins[1].type(sn); await ins[2].type('Staff-Pass-9xQ'); 
  await H.click(p,'Chăm sóc khách hàng',{exact:true}); await snap('preset')
  await H.click(p,'Tạo tài khoản',{sel:'button[type=submit]',wait:1500}); await snap('created'); console.log(tag,(await H.controls(p)).slice(10).join(' ; ').slice(0,500))
  // login as staff in a fresh context via UI
  const cx=await p.browser().createBrowserContext(); const q=await cx.newPage(); await q.setViewport({width:1200,height:900})
  await q.goto(site+'/login',{waitUntil:'networkidle0'})
  let f=await q.$$('input'); await f[0].type(sn); await f[1].type('Staff-Pass-9xQ'); await q.click('button[type=submit]'); await H.sleep(1500)
  console.log(tag,'staff after login',new URL(q.url()).pathname,(await H.text(q)).replace(/\n+/g,' | ').slice(0,300))
  f=await q.$$('input'); if(f.length&&new URL(q.url()).pathname==='/login'){ await f[0].type('Staff-Pass-9xQ'); await q.click('button[type=submit]'); await H.sleep(1500); console.log(tag,'staff after step2',new URL(q.url()).pathname,(await H.text(q)).replace(/\n+/g,' | ').slice(0,300)) }
  const nav=await q.evaluate(()=>[...document.querySelectorAll('nav a, aside a')].map(a=>a.innerText.trim()+'>'+a.getAttribute('href')))
  console.log(tag,'staff nav',nav.join(' ; '))
  for(const r of ['/admin/settings','/admin/staff','/admin/payment-requests','/admin/users','/entries','/admin/stats','/admin/notices']){ await q.goto(site+r,{waitUntil:'networkidle0'}); await H.sleep(700); console.log(tag,'staff visit',r,'->',new URL(q.url()).pathname) }
  await q.screenshot({path:`shots/staff-${tag}.png`}); await cx.close()
  // edit perms / delete
  await H.go(p,site+'/admin/staff'); console.log(tag,(await H.controls(p)).slice(10).join(' ; ').slice(0,600)); await snap('list')
}
