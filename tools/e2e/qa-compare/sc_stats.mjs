export default async ({p,H,site,snap})=>{
  await H.go(p,site+'/admin/stats'); await snap('init')
  for(const t of ['Tuần','Tháng','Năm','Ngày']){ await H.click(p,t,{exact:true,wait:1000}); await snap('p-'+t)
    const pts=await p.$$('svg circle, svg rect, .chart-point, svg path'); }
  // hover over chart
  const box=await p.evaluate(()=>{const s=document.querySelector('svg');const r=s&&s.getBoundingClientRect();return r?{x:r.x+r.width*0.6,y:r.y+r.height*0.5}:null})
  if(box){ await p.mouse.move(box.x,box.y); await H.sleep(400); await snap('hover') }
}
