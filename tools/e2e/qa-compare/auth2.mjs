import { createRequire } from 'node:module'
const puppeteer = createRequire((process.env.PPT||process.cwd())+'/')('puppeteer-core')
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const br = await puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-sandbox'] })
const txt = async (p) => (await p.evaluate(() => document.body.innerText)).replace(/\s+/g, ' ').slice(0, 300)
const path = (p) => new URL(p.url()).pathname + new URL(p.url()).search
const clickText = async (p, t) => { const ok = await p.evaluate((t) => { const b=[...document.querySelectorAll('button,a,label')].find(e=>e.innerText.trim().includes(t)); if(b){b.click();return true}return false }, t); await sleep(900); return ok }
const PW='Pass-1234x', SP='Second-1234'
for (const [tag, site] of [['next','http://127.0.0.1:8632'],['vue','http://127.0.0.1:8633']]) {
  console.log('=====', tag)
  const p = await br.newPage(); await p.setViewport({width:1000,height:800})
  const u = 'r' + tag + Date.now().toString(36).slice(-5)
  await p.goto(site + '/register', { waitUntil: 'networkidle0' })
  let ins = await p.$$('input')
  await ins[0].type('Khach QA'); await ins[1].type(u); await ins[2].type(PW); await ins[3].type(PW)
  await p.click('button[type=submit]'); await sleep(1200)
  ins = await p.$$('input'); await ins[0].type(SP)
  await p.click('button[type=submit]'); await sleep(1800)
  const code = await p.evaluate(()=>document.body.innerText.match(/[A-Z0-9]{4}(-[A-Z0-9]{4}){3}/)?.[0])
  console.log('code', !!code)
  // continue without ticking? 
  console.log('cont disabled?', await p.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.innerText.trim()==='Tiếp tục')?.disabled))
  await clickText(p, 'Tôi đã lưu')
  console.log('cont disabled after tick?', await p.evaluate(()=>[...document.querySelectorAll('button')].find(b=>b.innerText.trim()==='Tiếp tục')?.disabled))
  await clickText(p, 'Tiếp tục'); await sleep(1500)
  console.log('landing', path(p), '|', await txt(p))
  ins = await p.$$('input'); await ins[0].type(SP); await p.click('button[type=submit]'); await sleep(2000)
  console.log('registered ->', path(p), '|', await txt(p))
  console.log('token?', await p.evaluate(()=>[localStorage.getItem('xoso_token')?'tok':null, localStorage.getItem('xoso_role')]))
  await p.reload({waitUntil:'networkidle0'}); await sleep(800)
  console.log('after reload code visible?', await p.evaluate(()=>/[A-Z0-9]{4}(-[A-Z0-9]{4}){3}/.test(document.body.innerText)), path(p))
  // logout: find logout control
  console.log('buttons', await p.evaluate(()=>[...document.querySelectorAll('button,a')].map(b=>(b.innerText||b.title||b.getAttribute('aria-label')||'').trim()).filter(Boolean).slice(0,30).join(' | ')))
  await p.close()
  // login 2 step
  const cx = await br.createBrowserContext(); const q = await cx.newPage(); await q.goto(site+'/login',{waitUntil:'networkidle0'})
  ins = await q.$$('input'); await ins[0].type(u); await ins[1].type('wrongpass1'); await q.click('button[type=submit]'); await sleep(1200)
  console.log('wrong pw:', await txt(q))
  ins = await q.$$('input'); await ins[1].focus(); await q.keyboard.down('Meta'); await q.keyboard.press('a'); await q.keyboard.up('Meta'); await q.keyboard.press('Backspace'); await ins[1].type(PW); await q.click('button[type=submit]'); await sleep(1500)
  console.log('step2 screen:', await txt(q))
  ins = await q.$$('input'); await ins[ins.length-1].type('badsecond'); await q.click('button[type=submit]'); await sleep(1200)
  console.log('bad second:', await txt(q))
  ins = await q.$$('input'); await ins[ins.length-1].focus(); await q.keyboard.down('Meta'); await q.keyboard.press('a'); await q.keyboard.up('Meta'); await q.keyboard.press('Backspace'); await ins[ins.length-1].type(SP); await q.click('button[type=submit]'); await sleep(2000)
  console.log('after login', path(q), '|', await txt(q))
  console.log('has logout btn', await clickText(q,'Đăng xuất'), path(q), await q.evaluate(()=>[localStorage.getItem('xoso_token')]))
  // 401: login again with token tampering
  await q.goto(site+'/login',{waitUntil:'networkidle0'}); 
  console.log('login page after logout', path(q))
  await q.evaluate(()=>{localStorage.setItem('xoso_token','bad.token.x');localStorage.setItem('xoso_role','user')})
  await q.goto(site+'/customers',{waitUntil:'networkidle0'}); await sleep(1500)
  console.log('bad token on /customers ->', path(q), await q.evaluate(()=>[localStorage.getItem('xoso_token')]))
  await q.close()
}
await br.close()
