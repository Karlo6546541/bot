import { integrationConfig,adminClient } from '../_shared/config.ts';
import { fetchLockerCatalog,normalizeLocker,lockerCountries } from '../_shared/locker_catalog.ts';
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return new Response(null,{status:405});
 const config=await integrationConfig();
 if(!config.STRIPE_RELEASE_JOB_SECRET||req.headers.get('x-subhasto-job')!==config.STRIPE_RELEASE_JOB_SECRET)return new Response(null,{status:401});
 const body=await req.json().catch(()=>({}));
 const countries=body.country?[body.country]:Object.keys(lockerCountries);
 if(countries.some(c=>typeof c!=='string'||!lockerCountries[c]))return Response.json({error:'UNSUPPORTED_COUNTRY'},{status:400});
 const results=[];
 const admin=adminClient();
 for(const country of countries){
  try{
   const raw=await fetchLockerCatalog(country);
   const stamp=new Date().toISOString();
   const locations=raw.map(r=>normalizeLocker(r,country,stamp)).filter(r=>r!==null);
   // Preserve the last usable catalog if the provider returns an error or changes format.
   if(locations.length<10||locations.length<raw.length*.8)throw new Error('INVALID_CATALOG');
   for(let i=0;i<locations.length;i+=200){
    const {error}=await admin.from('commerce_delivery_locations').upsert(locations.slice(i,i+200),{onConflict:'id'});if(error)throw error;
   }
   const {error}=await admin.from('commerce_delivery_locations').update({active:false}).eq('provider','boxnow').eq('country_code',country).lt('updated_at',stamp);if(error)throw error;
   results.push({country,updated:locations.length,ok:true});
  }catch{results.push({country,ok:false});}
 }
 return Response.json({results},{status:results.every(r=>r.ok)?200:503});
});
