import {readFileSync} from 'node:fs';
export async function deliveryTests(db,assert,as,rpc,rejects,{host,buyer,other}) {
 await db.exec('reset role');
 await db.exec(readFileSync(new URL('../migrations/20261102214615_subhasto_delivery_locations.sql',import.meta.url),'utf8'));
 for(const [id,city,postal,country,active] of [['sesvete','Sesvete','10360','HR',true],['zagreb','Zagreb','10000','HR',true],['cakovec','Čakovec','40000','HR',true],['closed','Sesvete','10360','HR',false],['lj','Ljubljana','1000','SI',true]]) {
  await db.query(`insert into commerce_delivery_locations(id,provider,provider_id,name,address,postal_code,city,country_code,active,source_url) values($1,'boxnow',$1,$2,'Test street 1',$3,$2,$4,$5,'https://example.test')`,[id,city,postal,country,active]);
 }
 await db.exec('set role anon');
 assert.equal((await db.query('select * from commerce_delivery_locations')).rows.length,4);
 await rejects("insert into commerce_delivery_locations(id) values ('forged')",[],'permission denied');
 assert.equal((await db.query("select id from commerce_search_lockers('Kupac 7, 10360 Sesvete','hr',30)")).rows[0].id,'sesvete');
 assert.equal((await db.query("select id from commerce_search_lockers('cakovec','HR',30)")).rows[0].id,'cakovec');
 assert.equal((await db.query("select id from commerce_search_lockers('1000','SI',30)")).rows[0].id,'lj');
 assert.equal((await db.query("select id from commerce_search_lockers('','HR',1)")).rows.length,1);
 assert.equal((await db.query("select id from commerce_search_lockers('unknown','HR',30)")).rows.length,0);
 await as(host);
 const product=(await rpc("select (commerce_publish('Delivery choice',900,1)).id")).id;
 await as(buyer);
 const order=(await rpc('select (commerce_reserve($1,1,gen_random_uuid())).id',[product])).id;
 await rejects("update commerce_delivery_locations set active=false",[],'permission denied');
 await rejects(`select commerce_choose_shipping($1,'boxnow','{"locker_id":"closed"}')`,[order],'LOCKER_UNAVAILABLE');
 await rejects(`select commerce_choose_shipping($1,'boxnow','{"locker_id":"missing"}')`,[order],'LOCKER_UNAVAILABLE');
 await rpc(`select commerce_choose_shipping($1,'boxnow','{"locker_id":"sesvete","address":"forged"}')`,[order]);
 const destination=(await rpc('select destination from commerce_shipments where order_id=$1',[order])).destination;
 assert.equal(destination.address,'Test street 1');
 assert.equal(destination.city,'Sesvete');
 assert.equal(destination.provider_location_id,'sesvete');
 await as(other);
 await rejects(`select commerce_choose_shipping($1,'courier','{"address":"Someone"}')`,[order],'BUYER_ONLY');
 await as(buyer);
 await rejects(`select commerce_choose_shipping($1,'courier','{"address":" "}')`,[order],'ADDRESS_REQUIRED');
 await rpc(`select commerce_choose_shipping($1,'courier','{"address":" Kupac 7, Sesvete "}')`,[order]);
 assert.equal((await rpc('select destination from commerce_shipments where order_id=$1',[order])).destination.address,'Kupac 7, Sesvete');
 await rpc('select commerce_cancel($1)',[order]);
 await rejects(`select commerce_choose_shipping($1,'courier','{"address":"Another"}')`,[order],'ORDER_LOCKED');
 console.log('PASS: locker search ranking, country, diacritics, RLS, canonical destinations, ownership and courier validation');
}
