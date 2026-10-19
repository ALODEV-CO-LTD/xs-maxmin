export default async ({p,H,site,me,snap,tag})=>{
  const nm='Khach '+(tag==='next'?'NX':'VU')
  const L=async(w)=>console.log(tag,w,(await H.call('POST','/auth/login',{username:me.u,password:me.pw||'Pass-1234x'})).s)
  await H.go(p,site+'/admin/users')
  await H.typeIn(p,'input[type=text]',nm); await H.sleep(900)
  await H.click(p,'Xem chi tiết')
  await H.click(p,'Khoá tài khoản',{exact:true}); await H.click(p,'Khoá',{exact:true,last:true}); await H.sleep(800); await snap('locked'); await L('locked login')
  console.log(tag,(await H.controls(p)).filter(x=>/khoá|Khoá/.test(x)).join(';'))
  await H.click(p,'Mở khoá tài khoản',{exact:true}); await H.sleep(500); await snap('unlock-dlg'); 
  console.log(tag,(await H.controls(p)).slice(-4).join(';'))
}
