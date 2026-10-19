export default async ({p,H,site,me,snap,tag,seed})=>{
  const nm='Khach '+(tag==='next'?'NX':'VU'); const T=me.T
  const row=async(label)=>{const ok=await p.evaluate((nm,label)=>{const r=[...document.querySelectorAll('tr')].find(r=>r.innerText.includes(nm));const b=r&&[...r.querySelectorAll('button')].find(b=>b.innerText.trim()===label);if(b){b.click();return true}return false},nm,label);await H.sleep(800);return ok}
  console.log(tag,'seed req',(await H.call('POST','/me/packages/purchase',{packageType:'1m'},T)).s)
  await H.go(p,site+'/admin/payment-requests'); await snap('pending')
  await H.typeIn(p,'input[type=search]',me.u); await H.sleep(800); await snap('search'); await H.typeIn(p,'input[type=search]','x',0); await H.typeIn(p,'input[type=search]','',0); await H.sleep(500)
  console.log(tag,'approve click',await row('Duyệt')); await snap('approve-dlg'); console.log(tag,(await H.controls(p)).slice(-4).join(';'))
  await H.click(p,'Duyệt',{exact:true,last:true,wait:1500}); await snap('approved')
  console.log(tag,'user pkg after approve',JSON.stringify((await H.call('GET','/me',null,T)).j).slice(0,200))
  await H.click(p,'Lịch sử gia hạn',{exact:true,wait:1200}); await snap('renewals')
  const r=await H.call('POST','/me/packages/purchase',{packageType:'3m'},T); console.log(tag,'new req',r.s)
  await H.go(p,site+'/admin/payment-requests'); await snap('pending2')
  console.log(tag,'reject click',await row('Từ chối')); await snap('reject-dlg'); console.log(tag,(await H.controls(p)).slice(-5).join(';'))
  await H.click(p,'Từ chối',{exact:true,last:true,wait:1500}); await snap('rejected')
  await p.evaluate(()=>{}); 
  const ss=await H.call('GET','/admin/payment-requests',null,H.A||undefined)
}
