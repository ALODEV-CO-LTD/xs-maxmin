import puppeteer from 'puppeteer-core'
const B='http://127.0.0.1:4173'
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms))
const b=await puppeteer.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--no-sandbox']})
try{const p=await b.newPage();await p.setViewport({width:1280,height:900})
await p.goto(B+'/login',{waitUntil:'domcontentloaded'})
await p.evaluate(async()=>{const j=(x,y)=>fetch('/api'+x,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(y)}).then(r=>r.json());const l=await j('/auth/login',{username:'histk3pca',password:'Smoke#Test123'});const s=await j('/auth/step2',{pendingToken:l.pendingToken,password:'2468'});localStorage.setItem('xoso_token',s.token);localStorage.setItem('xoso_role','user')})
await p.goto(B+'/account',{waitUntil:'networkidle0'});await sleep(800)
const vis=()=>p.evaluate(()=>[...document.querySelectorAll('[role=tabpanel]')].map(x=>x.id.replace('acct-panel-','')+':'+(x.offsetParent?'show':'hide')).join(' '))
console.log('default',await vis(), 'h:',await p.evaluate(()=>document.body.scrollHeight))
for(const k of ['security','devices','data','profile']){await p.click('#acct-tab-'+k);await sleep(300);console.log(k,await vis(),'h:',await p.evaluate(()=>document.body.scrollHeight),p.url().split('?')[1])}
await p.click('#acct-tab-security');await p.keyboard.press('ArrowRight');await sleep(200);console.log('arrow ->',await vis())
await p.setViewport({width:390,height:844});await sleep(300);console.log('overflow390',await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1))
await p.screenshot({path:'tabs-m.png'})
}finally{await b.close()}
