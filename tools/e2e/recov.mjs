const ADMIN_PW = process.env.E2E_ADMIN_PASSWORD
if (!ADMIN_PW) { console.error('Set E2E_ADMIN_PASSWORD (the XOSO_ADMIN_PASSWORD the throw-away backend was started with)'); process.exit(2) }
const B='http://localhost:8291/api'
const call=async(m,p,b,t)=>{const r=await fetch(B+p,{method:m,headers:{'content-type':'application/json',...(t?{authorization:'Bearer '+t}:{})},body:b?JSON.stringify(b):undefined});let j=null;try{j=await r.json()}catch{};return{s:r.status,j}}
let pass=0,fail=0;const ok=(c,n,e='')=>{c?pass++:fail++;console.log((c?'PASS ':'FAIL ')+n+(c?'':' -> '+e))}
const adm=await call('POST','/auth/login',{username:'1',password:ADMIN_PW});console.log('admin login',adm.s,Object.keys(adm.j||{}))
const AT=adm.j.token||(await call('POST','/auth/step2',{pendingToken:adm.j.pendingToken,password:ADMIN_PW})).j?.token
const x=Date.now().toString(36);const u='rc'+x
const reg=await call('POST','/auth/register',{name:'RC',username:u,password:'Smoke#Test123',secondPassword:'2468'})
const s2=await call('POST','/auth/step2',{pendingToken:reg.j.pendingToken,password:'2468'});const me=await call('GET','/me',null,s2.j.token)
const id=me.j.id
const rc=await call('POST','/me/recovery-code',{password:'Smoke#Test123'},s2.j.token);console.log('own recovery',rc.s,Object.keys(rc.j||{}))
const oldCode=rc.j.code||rc.j.recoveryCode
for(let i=0;i<6;i++)await call('POST','/auth/login',{username:u,password:'sai'})
const lk=await call('POST','/auth/login',{username:u,password:'Smoke#Test123'});ok(lk.s===429,'user is locked out after wrong tries',lk.s)
let r=await call('PATCH','/admin/users/'+id,{newPassword:'12345'},AT);ok(r.s===400,'weak password rejected',JSON.stringify(r.j))
r=await call('PATCH','/admin/users/'+id,{newPassword:'Mk-Moi-9xQz'},AT);ok(r.s===200&&r.j.recoveryCode,'admin reset returns new recovery code',JSON.stringify(r.j).slice(0,80))
const newCode=r.j.recoveryCode
let l=await call('POST','/auth/login',{username:u,password:'Mk-Moi-9xQz'});ok(l.s===200,'user can log in right after reset (lock cleared)',l.s)
const old=await call('GET','/me',null,s2.j.token);ok(old.s===401,'old session revoked',old.s)
r=await call('PATCH','/admin/users/'+id,{reissueRecoveryCode:true},AT);ok(r.s===200&&r.j.recoveryCode&&r.j.recoveryCode!==newCode,'reissue gives another code')
r=await call('PATCH','/admin/users/'+id,{clearLockouts:true},AT);ok(r.s===200&&!r.j.recoveryCode,'clearLockouts works')
r=await call('PATCH','/admin/users/'+id,{},AT);ok(r.s===400,'empty body rejected')
const ev=await call('GET','/admin/security-events',null,AT);console.log('events',ev.s,JSON.stringify(ev.j).match(/admin_[a-z_]+/g))
console.log(pass+' pass '+fail+' fail')
