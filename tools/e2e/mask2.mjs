import puppeteer from 'puppeteer-core'
const B='http://127.0.0.1:4173',U='histk3pca'
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms))
let pass=0,fail=0
const ok=(c,n,e='')=>{c?pass++:fail++;console.log((c?'PASS ':'FAIL ')+n+(c?'':'  -> '+e))}
const browser=await puppeteer.launch({executablePath:'/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',headless:true,args:['--no-sandbox']})
try{
const page=await browser.newPage();await page.setViewport({width:1280,height:900})
await page.goto(B+'/login',{waitUntil:'domcontentloaded'})
await page.evaluate(async(u)=>{const j=(p,b)=>fetch('/api'+p,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(b)}).then(r=>r.json());const l=await j('/auth/login',{username:u,password:'Smoke#Test123'});const s=await j('/auth/step2',{pendingToken:l.pendingToken,password:'2468'});localStorage.setItem('xoso_token',s.token);localStorage.setItem('xoso_role','user');localStorage.removeItem('xoso_mask_enabled')},U)
const clickBtn=(t,exact)=>page.evaluate((t,exact)=>{const b=[...document.querySelectorAll('button')].find(x=>x.offsetParent&&(exact?x.innerText.trim()===t:x.innerText.replace(/\s+/g,' ').includes(t)));b?.click();return !!b},t,exact)
async function reveal(){await clickBtn('Hiện số liệu');await sleep(500);await page.focus('input[type=password]');await page.type('input[type=password]','Smoke#Test123');await clickBtn('Xác nhận');await sleep(900)}
const body=()=>page.evaluate(()=>document.querySelector('.page')?.innerText||'')
// ---- Khách hàng
await page.goto(B+'/customers',{waitUntil:'networkidle0'});await sleep(800)
const t0=await body();ok(/\d{3,}/.test(t0),'customers: figures visible before mask',t0.slice(0,300))
await clickBtn('Bật ẩn số liệu');await sleep(400)
const t1=await body();const rows=(await page.$$eval('tbody tr',r=>r.map(x=>x.innerText)))
ok(rows.length>0&&rows.every(r=>!/\d/.test(r.replace(/^\s*\d+\s/,''))),'customers: table figures hidden',JSON.stringify(rows.slice(0,2)))
await reveal();ok(/\d{2,}/.test(await body()),'customers: reveal shows figures')
await page.screenshot({path:'mask-bar-shown.png',clip:{x:0,y:0,width:900,height:200}});await clickBtn('Che lại');await sleep(300)
await page.screenshot({path:'mask-bar-covered.png',clip:{x:0,y:0,width:900,height:200}})
await page.click('.mb-icon');await sleep(200);await page.screenshot({path:'mask-bar-menu.png',clip:{x:0,y:0,width:900,height:300}});ok(await page.$('.mb-menu select')!==null,'settings menu opens');await page.mouse.click(700,500);await sleep(200);ok(await page.$('.mb-menu')===null,'menu closes on outside click')
// ---- Nhập số
await page.goto(B+'/entries',{waitUntil:'networkidle0'});await sleep(1200)
await clickBtn('Khach A');await sleep(1500)
ok(await page.$('.mask-bar')!==null,'entries: mask bar present')
const en=await page.evaluate(()=>localStorage.getItem('xoso_mask_enabled'));console.log('   persisted mask flag:',en)
const t2=await page.$$eval('tbody tr',r=>r.map(x=>x.innerText))
console.log('   entries rows sample:',JSON.stringify(t2.slice(0,2)))
const cells=await page.$$eval('.cell-num,.cell-points',e=>e.map(x=>x.innerText))
ok(cells.length>0&&cells.every(c=>!/\d/.test(c)),'entries: values/score/result hidden',JSON.stringify(cells.slice(0,4)))
const dis=await page.$$eval('.copy-bar button',b=>b[0]?.disabled);ok(dis===true,'entries: copy disabled while masked')
await reveal();const cells2=await page.$$eval('.cell-num,.cell-points',e=>e.map(x=>x.innerText))
ok(cells2.some(c=>/\d/.test(c)),'entries: reveal shows values')
await page.setViewport({width:390,height:844});await sleep(300)
ok(await page.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth+1),'entries: no horizontal overflow at 390px')
}finally{await browser.close()}
console.log(`\n${pass} pass, ${fail} fail`);process.exit(0)
