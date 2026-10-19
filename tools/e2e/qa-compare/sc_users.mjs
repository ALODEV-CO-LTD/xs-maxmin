export default async ({p,H,site,me,snap,tag})=>{
  const nm='Khach '+(tag==='next'?'NX':'VU')
  await H.go(p,site+'/admin/users')
  await H.typeIn(p,'input[type=text]',nm); await H.sleep(900); await snap('search-name')
  await H.typeIn(p,'input[type=text]','zzzzz'); await H.sleep(900); await snap('search-none')
  await H.typeIn(p,'input[type=text]',nm); await H.sleep(900)
  await H.click(p,'Xem chi tiết'); await snap('detail')
  if(process.env.CTL)console.log((await H.controls(p)).slice(12).join(' ; '))
}
