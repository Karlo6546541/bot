export const lockerCountries: Record<string,string> = {HR:'croatia',SI:'slovenia',GR:'greece',BG:'bulgaria',CY:'cyprus'};
export function lockerSource(country:string) {
 const slug=lockerCountries[country];
 if(!slug)throw new Error('UNSUPPORTED_COUNTRY');
 return `https://globallockersprod.z28.web.core.windows.net/PROD/${slug}/lockers/all.json`;
}
export async function fetchLockerCatalog(country:string) {
 const response=await fetch(lockerSource(country),{signal:AbortSignal.timeout(20000)});
 if(!response.ok)throw new Error('SOURCE_UNAVAILABLE');
 const bytes=new Uint8Array(await response.arrayBuffer());
 const text=bytes[0]===31&&bytes[1]===139
  ?await new Response(new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'))).text()
  :new TextDecoder().decode(bytes);
 const parsed=JSON.parse(text);
 if(!parsed||typeof parsed!=='object')throw new Error('INVALID_CATALOG');
 return Array.isArray(parsed)?parsed:Object.values(parsed);
}
export function normalizeLocker(raw:Record<string,unknown>,country:string,stamp:string) {
 const id=typeof raw.id==='string'||typeof raw.id==='number'?String(raw.id).trim():'';
 const lat=Number(raw.lat),lng=Number(raw.lng);
 const fullAddress=typeof raw.address==='string'?raw.address.trim():'';
 const postal=typeof raw.postalCode==='string'||typeof raw.postalCode==='number'?String(raw.postalCode).trim():'';
 const sizes=raw.sizes;
 if(!id||!fullAddress||raw.lat==null||raw.lng==null||!Number.isFinite(lat)||!Number.isFinite(lng)||Math.abs(lat)>90||Math.abs(lng)>180||!Array.isArray(sizes)||!sizes.some(s=>['1','2','3'].includes(String(s))))return null;
 const parts=fullAddress.split(',').map(s=>s.trim()).filter(Boolean);
 let cityIndex=parts.length-1;
 if(postal&&parts[cityIndex]?.replaceAll(' ','')===postal.replaceAll(' ',''))cityIndex--;
 const city=cityIndex>0?parts[cityIndex].replace(postal,'').trim():'';
 const address=cityIndex>0?parts.slice(0,cityIndex).join(', '):fullAddress;
 const title=typeof raw.title==='string'&&raw.title.trim()?raw.title.trim():`BOX NOW · ${address}`;
 return{id:`boxnow:${country}:${id}`,provider:'boxnow',provider_id:id,name:title,address,postal_code:postal,city,country_code:country,latitude:lat,longitude:lng,active:true,is_demo:false,source_url:lockerSource(country),updated_at:stamp};
}
