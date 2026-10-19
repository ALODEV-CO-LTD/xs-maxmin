import * as H from './h.mjs'
const br=await H.launch(); const A=await H.adminToken()
const staff=(await H.call('GET','/admin/staff',null,A)).j
const st=(staff.staff||staff.items||staff)[0]; console.log(Object.keys(st))
for (const tag of ['next','vue']) {
  const site=H.SITES[tag]
  const u=st.username; await H.call('PATCH','/admin/staff/'+st.id,{password:'Staff-Pass-9xQ',locked:false},A)
  const l=(await H.call('POST','/auth/login',{username:u,password:'Staff-Pass-9xQ'})).j; const T=l.token
  const p=await H.page(br,site,T,'admin'); await H.go(p,site+'/admin/users'); 
  console.log(tag,'start',new URL(p.url()).pathname)
  const r=await H.call('PATCH','/admin/staff/'+st.id,{locked:true},A); console.log(tag,'lock',r.s)
  await H.click(p,'Phản hồi',{sel:'a',wait:1800}); console.log(tag,'after nav ->',decodeURIComponent(new URL(p.url()).pathname+new URL(p.url()).search),await p.evaluate(()=>localStorage.getItem('xoso_token')))
  console.log(tag,'login screen says:',(await H.text(p)).replace(/\n+/g,' | ').slice(0,200))
  await H.call('PATCH','/admin/staff/'+st.id,{locked:false},A)
}
await br.close()
