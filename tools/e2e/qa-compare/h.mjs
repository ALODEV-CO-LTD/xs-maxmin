import { createRequire } from 'node:module'
import fs from 'node:fs'
export const puppeteer = createRequire((process.env.PPT||process.cwd())+'/')('puppeteer-core')
export const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
export const B='http://127.0.0.1:8631/api'
export const call = async (m, p, b, t) => { const r = await fetch(B + p, { method: m, headers: { 'content-type': 'application/json', ...(t?{authorization:'Bearer '+t}:{}) }, body: b?JSON.stringify(b):undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
export const SITES={next:'http://127.0.0.1:8632',vue:'http://127.0.0.1:8633'}
export const launch=()=>puppeteer.launch({ executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', headless: true, args: ['--no-sandbox'] })
export const adminToken=async()=>(await call('POST','/auth/login',{username:'1',password:'Next-admin-Pass-1'})).j.token
export async function page(br, site, token, role='admin', w=1200, h=900){
  const cx=await br.createBrowserContext(); const p=await cx.newPage(); await p.setViewport({width:w,height:h})
  p.errs=[]; p.on('pageerror',e=>p.errs.push('pageerror '+e.message)); p.on('console',m=>{if(m.type()==='error'&&!/vibrate/.test(m.text()))p.errs.push(m.text().slice(0,150))})
  await p.goto(site+'/login',{waitUntil:'networkidle0'}); await p.evaluate((t,r)=>{localStorage.setItem('xoso_token',t);localStorage.setItem('xoso_role',r)},token,role)
  return p
}
export const go=async(p,url)=>{await p.goto(url,{waitUntil:'networkidle0'});await sleep(900)}
export const text=async(p)=>(await p.evaluate(()=>document.body.innerText)).replace(/[ \t]+/g,' ')
export const click=async(p,t,opt={})=>{const ok=await p.evaluate((t,opt)=>{const sel=opt.sel||'button,a,[role=tab],[role=button],label';let l=[...document.querySelectorAll(sel)].filter(e=>e.offsetParent!==null&&(opt.exact?e.innerText.trim()===t:e.innerText.includes(t)));const b=opt.last?l[l.length-1]:l[opt.nth||0];if(b){b.click();return true}return false},t,opt);await sleep(opt.wait||900);return ok}
export const typeIn=async(p,sel,v,idx=0)=>{const els=await p.$$(sel);const el=els[idx];if(!el)return false;await el.focus();await el.evaluate(e=>e.select&&e.select());await p.keyboard.press('Backspace');await el.type(v);return true}
export const controls=(p)=>p.evaluate(()=>[...document.querySelectorAll('button,a,input,select,textarea,[role=tab]')].filter(e=>e.offsetParent!==null).map(e=>e.tagName[0]+(e.type?':'+e.type:'')+'|'+(e.placeholder||e.innerText||e.title||e.getAttribute('aria-label')||'').trim().replace(/\s+/g,' ').slice(0,40)))
export const mclick=async(p,t,opt={})=>{const r=await p.evaluate((t,opt)=>{const sel=opt.sel||'button,a,li,[role=option]';let l=[...document.querySelectorAll(sel)].filter(e=>e.offsetParent!==null&&(opt.exact?e.innerText.trim()===t:e.innerText.includes(t)));const b=opt.last?l[l.length-1]:l[opt.nth||0];if(!b)return null;b.scrollIntoView({block:'center'});const q=b.getBoundingClientRect();return {x:q.x+q.width/2,y:q.y+q.height/2}},t,opt);if(!r)return false;await p.mouse.click(r.x,r.y);await sleep(opt.wait||700);return true}
