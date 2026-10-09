import puppeteer from 'puppeteer-core'
const A_='http://127.0.0.1:4173',B='http://127.0.0.1:4173/api'
const post=async(p,b,t)=>(await fetch(B+p,{method:'POST',headers:{'content-type':'application/json',...(t?{authorization:'Bearer '+t}:{})},body:JSON.stringify(b)})).json()
const get=async(p,t)=>(await fetch(B+p,{headers:{authorization:'Bearer '+t}})).json()
async function mk(u){const r=await post('/auth/register',{name:u.toUpperCase(),username:u,password:'Smoke#Test123',secondPassword:'2468'});const s=await post('/auth/step2',{pendingToken:r.pendingToken,password:'2468'});const me=await get('/me',s.token);const c=await get('/me/customer-codes',s.token);return{tok:s.token,id:me.id,code:c.codes[0].code,name:u.toUpperCase()}}
const x=Date.now().toString(36).slice(-5);const U=await mk('ma'+x),V=await mk('mb'+x),W=await mk('mc'+x)
console.log(JSON.stringify(await post('/me/friends',{code:V.code},U.tok)).slice(0,120),JSON.stringify(await post('/me/friends',{code:W.code},U.tok)).slice(0,120))
console.log('ME',JSON.stringify(await get('/me',U.tok)).slice(0,80),'FR',JSON.stringify(await get('/me/friends',U.tok)).slice(0,80));const sleep=ms=>new Promise(r=>setTimeout(r,ms));let pass=0,fail=0;const ok=(c,n,e='')=>{c?pass++:fail++;console.log((c?'PASS ':'FAIL ')+n+(c?'':' -> '+e))}
const br=await puppeteer.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--no-sandbox']})
try{const p=await br.newPage();await p.setViewport({width:1280,height:900})
await p.goto(A_+'/login',{waitUntil:'domcontentloaded'})
await p.evaluate((t)=>{localStorage.setItem('xoso_token',t);localStorage.setItem('xoso_role','user')},U.tok)
p.on('console',m=>{if(m.type()==='error')console.log('CONSOLE',m.text().slice(0,200))});p.on('response',r=>{if(r.status()===401)r.text().then(t=>console.log('401',r.url(),t.slice(0,120)))});p.on('pageerror',e=>console.log('PAGEERR',e.message.slice(0,200)));await p.goto(A_+'/friends',{waitUntil:'networkidle0'});await sleep(1000)
const items=()=>p.$$eval('.friend-item, .friend-row, [class*=friend-item]',e=>e.map(x=>x.innerText.replace(/\s+/g,' ')))
console.log('list:',JSON.stringify(await items()))
// W and V send messages while U watches the list (no thread open)
console.log(JSON.stringify(await post(`/me/friends/${U.id}/messages`,{content:'tin 1 từ V'},V.tok)).slice(0,150));await sleep(300)
await post(`/me/friends/${U.id}/messages`,{content:'tin 2 từ V'},V.tok);await sleep(300)
await post(`/me/friends/${U.id}/messages`,{content:'tin từ W'},W.tok);await sleep(12000)
console.log('after:',JSON.stringify(await items()))
const badges=await p.$$eval('.unread-badge',e=>e.map(x=>x.innerText.trim()));console.log('badges',badges)
ok(badges.length===2&&badges.includes('2')&&badges.includes('1'),'red unread numbers per conversation')
const first=(await items())[0]||'';ok(first.includes(W.name)||first.toLowerCase().includes('mc'+x),'newest conversation (W) on top',first)
const col=await p.$eval('.unread-badge',e=>getComputedStyle(e).backgroundColor);console.log('badge colour',col)
// open V thread
await p.evaluate((n)=>{[...document.querySelectorAll('[class*=friend-item]')].find(e=>e.innerText.includes(n))?.click()},V.name);await sleep(1500)
const msgs=await p.$$eval('[class*=bubble], [class*=message-item], [class*=msg]',e=>e.map(x=>x.innerText.trim()).filter(Boolean));console.log('thread:',JSON.stringify(msgs.slice(0,6)))
await post(`/me/friends/${U.id}/messages`,{content:'tin 3 từ V'},V.tok);await sleep(12000)
const msgs2=await p.$$eval('[class*=bubble], [class*=message-item], [class*=msg]',e=>e.map(x=>x.innerText.trim()).filter(Boolean));console.log('thread2:',JSON.stringify(msgs2.slice(0,6)))
await p.screenshot({path:'msgui.png'})
}finally{await br.close()}
console.log(`${pass} pass ${fail} fail`);process.exit(0)
