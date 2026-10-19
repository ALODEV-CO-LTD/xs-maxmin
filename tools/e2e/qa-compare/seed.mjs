import fs from 'node:fs'
const B='http://127.0.0.1:8631/api'
const call = async (m, p, b, t) => { const r = await fetch(B + p, { method: m, headers: { 'content-type': 'application/json', ...(t?{authorization:'Bearer '+t}:{}) }, body: b?JSON.stringify(b):undefined }); return { s: r.status, j: await r.json().catch(() => null) } }
const A=(await call('POST','/auth/login',{username:'1',password:'Next-admin-Pass-1'})).j.token
const pk=(await call('GET','/admin/packages',null,A)).j; console.log(JSON.stringify(pk).slice(0,300))
const out={}
for (const tag of ['nx','vu']) {
  const u=tag+Date.now().toString(36).slice(-5)
  const reg=(await call('POST','/auth/register',{name:'Khach '+tag.toUpperCase(),username:u,password:'Pass-1234x',secondPassword:'Second-1234'})).j
  const T=(await call('POST','/auth/step2',{pendingToken:reg.pendingToken,password:'Second-1234'})).j.token
  const pkgs=(await call('GET','/me/packages',null,T)).j
  const code=(pkgs.packages||pkgs)[0]?.code||(pkgs.packages||pkgs)[0]?.type
  console.log(tag,u,'pkg',code, JSON.stringify(await call('POST','/me/packages/purchase',{packageType:code},T)).slice(0,100))
  console.log(JSON.stringify(await call('POST','/me/messages',{content:'Xin chao admin tu '+tag},T)).slice(0,100))
  out[tag]={u,T}
}
fs.writeFileSync('seed.json',JSON.stringify(out))
