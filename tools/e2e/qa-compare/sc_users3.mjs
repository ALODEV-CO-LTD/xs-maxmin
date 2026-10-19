export default async ({p,H,site,me,snap,tag})=>{
  const nm='Khach '+(tag==='next'?'NX':'VU')
  const L=async(w,pw)=>console.log(tag,w,(await H.call('POST','/auth/login',{username:me.u,password:pw})).s)
  await H.go(p,site+'/admin/users')
  await H.typeIn(p,'input[type=text]',nm); await H.sleep(900)
  await H.click(p,'Xem chi tiết')
  await H.click(p,'Mở khoá tài khoản',{exact:true}); await H.click(p,'Mở khoá',{exact:true,last:true}); await H.sleep(800); await snap('unlocked'); await L('unlocked login','Pass-1234x')
  await H.click(p,'Đặt lại mật khẩu',{exact:true}); 
  await H.typeIn(p,'input[type=password],input[type=text]','123',1); await H.click(p,'Lưu',{exact:true}); await H.sleep(700); await snap('reset-weak')
  await H.click(p,'Tạo ngẫu nhiên',{exact:true}); await H.sleep(300); await snap('random')
  await H.typeIn(p,'input[type=password],input[type=text]','Mk-Moi-9xQzA',1); await H.click(p,'Lưu',{exact:true,wait:1500}); await snap('reset-done'); await L('new pw login','Mk-Moi-9xQzA')
  await H.click(p,'Cấp lại mã khôi phục',{exact:true}); await H.sleep(500); await snap('reissue-dlg'); console.log(tag,(await H.controls(p)).slice(-3).join(';'))
  await H.click(p,'Cấp lại',{exact:true,last:true,wait:1500}); await snap('reissue-done')
  await H.click(p,'Gỡ khoá đăng nhập',{exact:true}); await H.sleep(500); await snap('clearlock-dlg'); console.log(tag,(await H.controls(p)).slice(-3).join(';'))
  await H.click(p,'Xoá tài khoản',{exact:true}); await H.sleep(500); await snap('delete-dlg'); console.log(tag,(await H.controls(p)).slice(-4).join(';'))
}
