import { createRequire } from 'node:module'
const puppeteer = createRequire((process.env.PPT||process.cwd())+'/')('puppeteer-core')
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const br = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-sandbox'] })
const call = async (m, p, b, t) => { const r = await fetch('http://127.0.0.1:8631/api' + p, { method: m, headers: { 'content-type': 'application/json', ...(t?{authorization:'Bearer '+t}:{}) }, body: b?JSON.stringify(b):undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
const txt = async (p) => (await p.evaluate(() => document.body.innerText)).replace(/\s+/g, ' ').slice(0, 220)
const loc = (p) => decodeURIComponent(new URL(p.url()).pathname + new URL(p.url()).search)
const setv = async (p, el, v) => { await el.focus(); await el.evaluate(e=>e.select()); await p.keyboard.press('Backspace'); await el.type(v) }
const clickText = async (p, t, last) => { const ok = await p.evaluate((t,last) => { const l=[...document.querySelectorAll('button,a')].filter(e=>e.innerText.trim().includes(t)); const b=last?l[l.length-1]:l[0]; const _f=(f)=>f; void _f; const b2=b; if(0)[].find(e=>e.innerText.trim().includes(t)); if(b){b.click();return true}return false }, t, last); await sleep(1000); return ok }
const submit = async (p) => { await p.click('button[type=submit]'); await sleep(1500) }
for (const [tag, site] of [['next','http://127.0.0.1:8632'],['vue','http://127.0.0.1:8633']]) {
  console.log('=====', tag)
  const u='f'+tag+Date.now().toString(36).slice(-5)
  let reg; for(;;){reg=(await call('POST','/auth/register',{name:'L',username:u,password:'Pass-1234x',secondPassword:'Second-1234'})).j; if(!reg.retryAfter)break; console.log('wait',reg.retryAfter); await sleep(Math.min(reg.retryAfter,60)*1000+500)}
  const st=(await call('POST','/auth/step2',{pendingToken:reg.pendingToken,password:'Second-1234'})).j
  const rc = st.recoveryCode || reg.recoveryCode; if(!rc) console.log('keys',Object.keys(st),Object.keys(reg)); const _x=1
  const q = await (await br.createBrowserContext()).newPage(); await q.setViewport({width:1000,height:800})
  await q.goto(site+'/customers',{waitUntil:'networkidle0'}); await sleep(500); console.log('anon /customers ->', loc(q))
  let ins=await q.$$('input'); await ins[0].type(u); await ins[1].type('bad-pass-1'); await submit(q)
  console.log('wrong pw:', (await txt(q)).slice(0,150))
  ins=await q.$$('input'); await setv(q,ins[1],'Pass-1234x'); await submit(q)
  console.log('2nd stage:', (await txt(q)).slice(0,150))
  ins=await q.$$('input'); await ins[0].type('wrong2'); await submit(q); console.log('bad 2nd:', (await txt(q)).slice(0,160))
  console.log('back btn', await clickText(q,'Quay lại'), loc(q), (await txt(q)).slice(0,80))
  ins=await q.$$('input'); await setv(q,ins[0],u); await setv(q,ins[1],'Pass-1234x'); await submit(q)
  ins=await q.$$('input'); await ins[0].type('Second-1234'); await submit(q); await sleep(800)
  console.log('logged in ->', loc(q))
  await q.goto(site+'/admin/users',{waitUntil:'networkidle0'}); await sleep(800); console.log('user at /admin/users ->', loc(q))
  await q.goto(site+'/login',{waitUntil:'networkidle0'}); await sleep(800); console.log('user at /login ->', loc(q))
  // reload session persists
  await q.goto(site+'/account',{waitUntil:'networkidle0'}); await sleep(800); console.log('reload /account ->', loc(q))
  // 401 via server revoke: change token by logging out via api
  const tok = await q.evaluate(()=>localStorage.getItem('xoso_token'))
  const A=(await call('POST','/auth/login',{username:'1',password:'Next-admin-Pass-1'})).j.token; const uid=(await call('GET','/admin/users',null,A)).j.subscribers.find(x=>x.username===u).id; await call('PATCH','/admin/users/'+uid,{locked:true},A); await call('PATCH','/admin/users/'+uid,{locked:false},A)
  await q.goto(site+'/friends',{waitUntil:'networkidle0'}); await sleep(1500); console.log('revoked token /friends ->', loc(q), await q.evaluate(()=>localStorage.getItem('xoso_token')))
  // login with redirect param
  ins=await q.$$('input'); await ins[0].type(u); await ins[1].type('Pass-1234x'); await submit(q); ins=await q.$$('input'); await ins[0].type('Second-1234'); await submit(q); await sleep(800)
  console.log('after redirect login ->', loc(q))
  // logout button
  const lo=await clickText(q,'Đăng xuất'); console.log('after click logout text:', (await txt(q)).slice(0,200)); console.log('dialog btns', await q.evaluate(()=>[...document.querySelectorAll('dialog button,[role=dialog] button,.modal button')].map(b=>b.innerText.trim()))); await clickText(q,'Đăng xuất',true); console.log('logout:', lo, loc(q), await q.evaluate(()=>[localStorage.getItem('xoso_token'),localStorage.getItem('xoso_role'), Object.keys(localStorage).join(',')]))
  // forgot password
  await q.goto(site+'/login',{waitUntil:'networkidle0'}); await clickText(q,'Quên mật khẩu')
  console.log('forgot:', loc(q), (await txt(q)).slice(0,300))
  const fi = await q.$$('input'); console.log('forgot inputs', fi.length)
  await fi[0].type(u); await fi[1].type(rc); await fi[2].type('New-Pass-5678q'); if(fi[3]) await fi[3].type('New-Pass-5678q')
  await submit(q); await sleep(500); console.log('recover result:', (await txt(q)).slice(0,300), loc(q))
  await q.close()
}
await br.close()
