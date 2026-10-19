export default async ({p,H,site,me,snap,tag})=>{
  console.log(tag,'req',(await H.call('POST','/auth/recovery-request',{username:me.u,note:'Mat ma khoi phuc'})).s)
  await H.go(p,site+'/admin/users'); await snap('with-request'); console.log(tag,(await H.controls(p)).slice(10,22).join(' ; '))
  console.log(tag,(await H.text(p)).replace(/\n+/g,' | ').slice(130,600))
}
