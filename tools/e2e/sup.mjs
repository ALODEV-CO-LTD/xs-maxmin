import puppeteer from 'puppeteer-core'
const B='http://127.0.0.1:4173',AP=B+'/api';const sleep=ms=>new Promise(r=>setTimeout(r,ms))
const call=async(m,p,b,t)=>{const r=await fetch(AP+p,{method:m,headers:{'content-type':'application/json',...(t?{authorization:'Bearer '+t}:{})},body:b?JSON.stringify(b):undefined});let j=null;try{j=await r.json()}catch{};return{s:r.status,j}}
let pass=0,fail=0;const ok=(c,n,e='')=>{c?pass++:fail++;console.log((c?'PASS ':'FAIL ')+n+(c?'':' -> '+e))}
const adm=await call('POST','/auth/login',{username:'1',password:'1'});const AT=adm.j.token
const u='sp'+Date.now().toString(36).slice(-5)
const br0=null
const br=await puppeteer.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--no-sandbox']})
try{const p=await br.newPage();await p.setViewport({width:1280,height:800})
await p.goto(B+'/login',{waitUntil:'domcontentloaded'})
const r=await p.evaluate(async(u)=>{const j=(x,y)=>fetch('/api'+x,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(y)}).then(r=>r.json());const g=await j('/auth/register',{name:'Khach SP',username:u,password:'Smoke#Test123',secondPassword:'2468'});const s=await j('/auth/step2',{pendingToken:g.pendingToken,password:'2468'});localStorage.setItem('xoso_token',s.token);localStorage.setItem('xoso_role','user');const me=await fetch('/api/me',{headers:{authorization:'Bearer '+s.token}}).then(r=>r.json());return me.id},u)
const uid=r
await p.goto(B+'/entries',{waitUntil:'networkidle0'});await sleep(800)
ok(await p.$('.support-btn')!==null,'support button in the top bar')
ok(await p.evaluate(()=>!document.body.innerText.split('\n').some(l=>l.trim()==='Phản hồi')),'no "Phản hồi" item left in the side menu')
// admin writes first -> badge
await call('POST','/admin/messages/'+uid,{content:'Chào bạn, Admin đây'},AT)
await sleep(11000)
const badge=await p.$eval('.support-badge',e=>e.innerText.trim()).catch(()=>null);ok(badge==='1','red badge 1 on the button',badge)
await p.click('.support-btn');await sleep(1200)
ok(await p.$('.support-pop')!==null,'popover opens at the button')
const box=await p.$eval('.support-pop',e=>{const r=e.getBoundingClientRect();return[r.right,r.top,r.width,r.height]});const bb=await p.$eval('.support-btn',e=>{const r=e.getBoundingClientRect();return[r.right,r.bottom]});console.log('pop',box,'btn',bb)
ok(Math.abs(box[0]-bb[0])<4&&box[1]>=bb[1],'popover anchored under the button')
ok(await p.$('.support-badge')===null,'badge cleared on open')
await p.type('.sp-form input','Cảm ơn Admin');await p.keyboard.press('Enter');await sleep(800)
await call('POST','/admin/messages/'+uid,{content:'Tin thứ hai'},AT);await sleep(9500)
const texts=await p.$$eval('.sp-text',e=>e.map(x=>x.innerText));console.log(texts)
ok(texts[0]==='Tin thứ hai','newest message on top',texts[0])
await p.screenshot({path:'sup-desktop.png',clip:{x:700,y:0,width:580,height:620}})
await p.keyboard.press('Escape');await sleep(200);ok(await p.$('.support-pop')===null,'Esc closes')
await p.click('.support-btn');await sleep(500);await p.mouse.click(300,400);await sleep(200);ok(await p.$('.support-pop')===null,'click outside closes')
await p.setViewport({width:390,height:844});await sleep(300);await p.click('.support-btn');await sleep(600);await p.screenshot({path:'sup-mobile.png'})
ok(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'no horizontal overflow on phone')
}finally{await br.close()}
console.log(pass+' pass '+fail+' fail');process.exit(0)
