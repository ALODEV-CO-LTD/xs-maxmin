export default async ({p,H,site,me,snap,tag,A})=>{
  await H.go(p,site+'/admin/notices')
  await H.click(p,'Gửi thông báo',{sel:'[role=tab]'})
  await H.typeIn(p,'#an-title','Tieu de bao tri thu'); await H.typeIn(p,'textarea','Noi dung thu nghiem')
  await H.click(p,'Gửi thông báo',{sel:'button[type=submit]',wait:600}); await snap('send-confirm'); await H.click(p,'Gửi',{exact:true,last:true,wait:1500}); await snap('sent')
  const u=await H.page((await import('./h.mjs')).launchedBr||p.browser(),site,me.T,'user'); await H.go(u,site+'/entries'); await H.sleep(800)
  const bt=(await H.text(u)).replace(/\n+/g,' | '); console.log(tag,'user banner:',/Tieu de bao tri thu/.test(bt), bt.slice(0,150)); await u.screenshot({path:`shots/banner-${tag}.png`})
  // dismiss banner?
  console.log(tag,'banner controls',(await H.controls(u)).filter(x=>/Đóng|Ẩn|×|✕/.test(x)).join(';'))
  await H.click(p,'Đã gửi',{sel:'[role=tab]'}); await snap('list'); console.log(tag,(await H.controls(p)).slice(11).join(' ; '))
  await H.click(p,'Xoá',{exact:true}); await H.sleep(500); await snap('del-dlg'); await H.click(p,'Xoá',{exact:true,last:true,wait:1200}); await snap('deleted')
  await H.click(p,'Chế độ bảo trì',{sel:'[role=tab]'}); await H.click(p,'',{sel:'input[type=checkbox]'}); await H.typeIn(p,'textarea','He thong bao tri tu 23h'); await H.click(p,'Lưu cấu hình bảo trì',{wait:1500}); await snap('maint-saved')
  const u2=await H.page(p.browser(),site,me.T,'user'); await H.go(u2,site+'/account'); const t2=(await H.text(u2)).replace(/\n+/g,' | '); console.log(tag,'user sees maintenance:',/bao tri tu 23h/.test(t2)); await u2.screenshot({path:`shots/maint-${tag}.png`})
  await H.click(p,'',{sel:'input[type=checkbox]'}); await H.click(p,'Lưu cấu hình bảo trì',{wait:1200}); await snap('maint-off')
}
