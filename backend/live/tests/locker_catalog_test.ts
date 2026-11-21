import assert from 'node:assert/strict';
import { normalizeLocker,lockerSource } from '../functions/_shared/locker_catalog.ts';
const raw={id:'1692',lat:'45.827136',lng:'16.081514',address:'Zagrebačka cesta 162b, Sesvete, 10360',title:'BOX NOW Dubec',postalCode:'10360',sizes:['3','2','1']};
Deno.test('provider location produces a stable ID and a human-readable street and city',()=>{
 const row=normalizeLocker(raw,'HR','2026-11-02T00:00:00Z');
 assert.equal(row?.id,'boxnow:HR:1692');assert.equal(row?.city,'Sesvete');assert.equal(row?.address,'Zagrebačka cesta 162b');assert.equal(row?.postal_code,'10360');assert.equal(row?.is_demo,false);
});
Deno.test('the country forms part of the identity and only known public sources are allowed',()=>{
 assert.notEqual(normalizeLocker(raw,'HR','')?.id,normalizeLocker(raw,'SI','')?.id);
 assert.throws(()=>lockerSource('invalid'));assert.ok(lockerSource('HR').startsWith('https://globallockersprod.z28.web.core.windows.net/'));
});
Deno.test('malformed or unavailable locations are excluded',()=>{
 assert.equal(normalizeLocker({...raw,lat:'not-a-number'},'HR',''),null);
 assert.equal(normalizeLocker({...raw,sizes:[]},'HR',''),null);
 assert.equal(normalizeLocker({...raw,id:''},'HR',''),null);
});
