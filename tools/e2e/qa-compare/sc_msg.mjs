export default async ({p,H,site,me,snap,tag})=>{
  const nm='Khach '+(tag==='next'?'NX':'VU')
  await H.go(p,site+'/admin/messages'); await snap('list')
  await H.click(p,nm,{sel:'button'}); await H.sleep(1000); await snap('thread'); console.log(tag,(await H.controls(p)).slice(12).join(' ; '))
  await H.typeIn(p,'input[type=text]','Chao ban, admin tra loi'); await H.click(p,'Gửi',{last:true,wait:1200}); await snap('replied')
  const m=(await H.call('GET','/me/messages',null,me.T)).j; console.log(tag,'user sees',JSON.stringify(m).slice(0,200))
  await H.click(p,'Chưa trả lời',{wait:900}); await snap('unanswered')
  await H.typeIn(p,'input[type=search]','zzz'); await H.sleep(600); await snap('search-none')
  await H.go(p,tag==='next'?site+'/admin/messages?user='+me.id:site+'/admin/messages/'+me.id); await snap('deeplink')
}
