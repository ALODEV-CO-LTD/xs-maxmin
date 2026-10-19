export default async ({p,H,site,me,snap,tag})=>{
  await H.go(p,site+'/admin/settings')
  const tabs=await p.evaluate(()=>[...document.querySelectorAll('[role=tab],.tabs button, .tab')].filter(e=>e.offsetParent).map(e=>e.innerText.trim()))
  console.log(tag,'tabs',tabs.join('|'))
  for(const t of tabs){ await H.click(p,t,{exact:true,wait:1300}); await snap('tab-'+t) }
}
