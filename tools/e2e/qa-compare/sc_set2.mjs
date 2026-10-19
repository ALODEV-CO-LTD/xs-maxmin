export default async ({p,H,site,me,snap,tag,A})=>{
  await H.go(p,site+'/admin/settings')
  await H.click(p,'Sửa',{exact:true}); await snap('bank-edit'); console.log(tag,(await H.controls(p)).slice(18).join(';').slice(0,400))
  await H.click(p,'Ngân hàng',{sel:'label',wait:300});
  const tr=await p.$('.app-select-trigger'); await tr.click(); await H.sleep(400); await snap('bank-menu'); await H.mclick(p,'Vietcombank',{sel:'li,[role=option]'})
  const f=await p.$$('input[placeholder="Số tài khoản"]'); await f[0].type('0123456789'); const g=await p.$$('input[placeholder="Chủ tài khoản"]'); await g[0].type('NGUYEN VAN TEST')
  await H.mclick(p,'Lưu cấu hình thanh toán',{wait:1500}); await snap('bank-saved')
  console.log(tag,'api',JSON.stringify((await H.call('GET','/me/payment-info',null,me.T)).j).slice(0,200))
  await H.click(p,'Gói dịch vụ',{exact:true,wait:1000}); await snap('pkg'); console.log(tag,(await H.controls(p)).slice(18).join(';').slice(0,500))
  await H.click(p,'Chính sách bảo mật',{exact:true,wait:1000}); await H.click(p,'Sửa',{exact:true}); await snap('pol-edit')
  const n=await p.$$('input[type=number]'); await n[0].focus(); await n[0].evaluate(e=>e.select()); await n[0].type('4'); await H.mclick(p,'Lưu',{sel:'button[type=submit]',wait:1500}); await snap('pol-saved')
  console.log(tag,'policy',JSON.stringify((await H.call('GET','/me/policy',null,me.T)).j).slice(0,200))
  await H.click(p,'Sao lưu',{exact:true,wait:1000}); await snap('backups'); console.log(tag,(await H.controls(p)).slice(18).join(';').slice(0,300))
}
