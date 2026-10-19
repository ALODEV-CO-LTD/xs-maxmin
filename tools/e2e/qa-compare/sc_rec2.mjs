export default async ({p,H,site,me,snap,tag})=>{
  const nm='Khach '+(tag==='next'?'NX':'VU')
  await H.go(p,site+'/admin/users')
  const ok=await p.evaluate((nm)=>{const e=[...document.querySelectorAll('li,div,tr')].filter(e=>e.innerText&&e.innerText.includes(nm+' (')&&[...e.querySelectorAll('button')].some(b=>b.innerText.includes('Duyệt, cấp mã'))).pop();const b=e&&[...e.querySelectorAll('button')].find(b=>b.innerText.includes('Duyệt, cấp mã'));if(b){b.click();return true}return false},nm); await H.sleep(900)
  console.log(tag,'approve click',ok); await snap('approve-dlg'); console.log(tag,(await H.controls(p)).slice(-5).join(';'))
  await H.mclick(p,'Duyệt',{last:true,wait:1500}); await snap('approved'); console.log(tag,(await H.text(p)).replace(/\n+/g,' | ').slice(130,700))
}
