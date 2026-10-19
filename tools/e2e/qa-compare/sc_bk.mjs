export default async ({p,H,site,snap,tag,A})=>{
  await H.go(p,site+'/admin/settings'); await H.click(p,'Sao lưu',{exact:true,wait:1000}); await snap('before')
  await H.mclick(p,'Tạo bản sao lưu mới',{wait:3000}); await snap('created'); console.log(tag,(await H.controls(p)).slice(18).join(';').slice(0,400))
  console.log(tag,'api',JSON.stringify((await H.call('GET','/admin/backups',null,A)).j).slice(0,300))
  await H.click(p,'Giới hạn ID',{exact:true,wait:1000}); await snap('idlimit'); console.log(tag,(await H.controls(p)).slice(18).join(';').slice(0,400))
  await H.click(p,'Gói dịch vụ',{exact:true,wait:1000}); await H.mclick(p,'+ Thêm gói'); await snap('addpkg'); console.log(tag,(await H.controls(p)).slice(18).join(';').slice(0,500))
}
