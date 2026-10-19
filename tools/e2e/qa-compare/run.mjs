// usage: node run.mjs scenarioFile [mobile]
import * as H from './h.mjs'
import fs from 'node:fs'
const seed=JSON.parse(fs.readFileSync('seed.json'))
const file=process.argv[2]; const mod=await import('./'+file)
const br=await H.launch(); const A=await H.adminToken()
const res={}
for(const k of ['nx','vu']){const u=seed[k]; const id=(await H.call('GET','/admin/users',null,A)).j.subscribers.find(x=>x.username===u.u).id; await H.call('PATCH','/admin/users/'+id,{newPassword:'Pass-1234x',locked:false},A); await H.call('PATCH','/admin/users/'+id,{clearLockouts:true},A); const l=(await H.call('POST','/auth/login',{username:u.u,password:'Pass-1234x'})).j; u.T=(await H.call('POST','/auth/step2',{pendingToken:l.pendingToken,password:'Second-1234'})).j.token; u.id=id}
for(const tag of ['next','vue']){
  const me=tag==='next'?seed.nx:seed.vu
  const p=await H.page(br,H.SITES[tag],A,'admin',Number(process.env.W)||1200,Number(process.env.HT)||900)
  const snaps=[]; const snap=async(name)=>{let t=(await H.text(p)); const other=tag==='next'?seed.vu:seed.nx; if(process.env.FILTER) t=t.split('\n').filter(l=>!l.includes(other.u)&&!/^\d+$|đ$|^Tổng \(|^Hiển thị|^Khach (VU|NX)$/.test(l.trim())).join('\n'); t=t.replace(new RegExp(me.u,'g'),'<U>').replace(/Khach (NX|VU)/g,'Khach <X>').replace(/\d\d:\d\d:\d\d/g,'<t>').replace(/[0-9A-Z]{4}(-[0-9A-Z]{4}){3}/g,'<CODE>').replace(/XS[0-9A-Z]{6}/g,'<REF>').replace(/tu (nx|vu)\b/g,'tu <x>').replace(/\d\d:\d\d(?!:)/g,'<hm>'); snaps.push([name,t]); if(process.env.SHOW&&tag==='next')console.log('['+name+']',t.replace(/\n+/g,' | ').slice(0,Number(process.env.SHOW))); try{await p.screenshot({path:`shots/${file}-${tag}-${snaps.length}-${name.replace(/\W/g,'_')}.png`})}catch{}}
  try{ await mod.default({p,H,site:H.SITES[tag],me,A,snap,tag,seed}) }catch(e){ console.log(tag,'THROW',e.message) }
  if(p.errs.length)console.log(tag,'ERRS',[...new Set(p.errs)].slice(0,5))
  res[tag]=snaps
}
const n=Math.max(res.next.length,res.vue.length)
for(let i=0;i<n;i++){ const a=res.next[i],b=res.vue[i]; if(!a||!b){console.log('MISSING step',i,a?.[0],b?.[0]);continue}
  if(a[1]===b[1])console.log('SAME ',a[0]); else { console.log('DIFF ',a[0]); const al=a[1].split('\n'),bl=b[1].split('\n'); const sa=new Set(al),sb=new Set(bl); console.log('  next-only:',al.filter(x=>!sb.has(x)).slice(0,8)); console.log('  vue-only :',bl.filter(x=>!sa.has(x)).slice(0,8)) } }
await br.close()
