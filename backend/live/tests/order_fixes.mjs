import {readFileSync} from 'node:fs';
// Runs after the delivery-locations tests (needs commerce_delivery_locations).
export async function orderFixTests(db,assert,as,rpc,rejects,{host,buyer,other}) {
 await db.exec('reset role');
 await db.exec(readFileSync(new URL('../migrations/20261103000000_subhasto_order_fixes.sql',import.meta.url),'utf8'));
 const owner=async id=>(await rpc("select data->>'ownerId' o from loop_devices where id=$1",[id])).o;
 const device=(id,extra={})=>db.query('insert into loop_devices(id,data) values($1,$2)',[id,{id,name:'Item '+id,model:'',ownerId:host,listPrice:19,quantity:1,parcelSize:'medium',...extra}]);

 // 4 + 2: 5 % commission, server-priced shipping, delivery record
 await device('fix-item');
 await as(buyer);
 const o=(await rpc("select (commerce_reserve_device('fix-item',gen_random_uuid())).id")).id;
 await rpc(`select commerce_choose_shipping($1,'boxnow','{"locker_id":"sesvete"}')`,[o]);
 assert.deepEqual(await rpc('select shipping_cents s,total_cents t from commerce_orders where id=$1',[o]),{s:600,t:2500});
 await rpc(`select commerce_choose_shipping($1,'courier','{"address":"Ilica 1, Zagreb"}')`,[o]);
 assert.deepEqual(await rpc('select shipping_cents s,total_cents t from commerce_orders where id=$1',[o]),{s:900,t:2800});
 await db.exec('reset role');await rpc('select commerce_begin_charge($1)',[o]);
 assert.deepEqual(await rpc('select item_cents,fee_cents,seller_cents from commerce_payments where order_id=$1',[o]),{item_cents:1900,fee_cents:95,seller_cents:1805});
 await as(buyer);await rpc(`select commerce_choose_shipping($1,'pickup','{}')`,[o]);
 assert.equal((await rpc('select total_cents t from commerce_orders where id=$1',[o])).t,2800,'price is fixed once a charge started');
 await rpc(`select commerce_choose_shipping($1,'courier','{"address":"Ilica 1, Zagreb"}')`,[o]);
 await db.exec('reset role');
 await db.query("update commerce_payments set intent_id='pi_fix' where order_id=$1",[o]);
 await rpc("select commerce_settle_intent('ev_fix',$1,'pi_fix','ch_fix',2800,'EUR')",[o]);
 const del=await rpc("select data from loop_deliveries where id=$1",['del-stripe-sale-'+o]);
 assert.equal(del.data.method,'courier');assert.equal(del.data.cost,9);assert.equal(del.data.buyerId,buyer);assert.equal(del.data.sellerId,host);
 assert.equal(Number((await rpc("select data->>'fee' f from loop_transactions where id=$1",['stripe-sale-'+o])).f),0.95);
 await rpc("select commerce_record_refund('pi_fix',2800,false)");
 assert.equal(Number((await rpc('select sum(amount_cents) a from commerce_platform_ledger where order_id=$1',[o])).a),0);
 await db.exec('reset role');
 await device('big-item',{parcelSize:'large'});await as(buyer);
 const big=(await rpc("select (commerce_reserve_device('big-item',gen_random_uuid())).id")).id;
 await rejects(`select commerce_choose_shipping($1,'boxnow','{"locker_id":"sesvete"}')`,[big],'PARCEL_TOO_LARGE');

 // 1: unpaid orders expire; the listing is released
 await db.exec('reset role');await device('exp-item');await as(buyer);
 const e=(await rpc("select (commerce_reserve_device('exp-item',gen_random_uuid())).id")).id;
 await as(host);await rejects("update loop_devices set data=data||'{\"listPrice\":1}'::jsonb where id='exp-item'",[],'ORDER_IN_PROGRESS');
 await db.exec('reset role');
 assert.equal((await rpc('select commerce_expire_orders() n')).n,0,'a fresh order is kept');
 await db.query("update commerce_orders set created_at=now()-interval '31 minutes' where id=$1",[e]);
 assert.equal((await rpc('select commerce_expire_orders() n')).n,1);
 assert.equal((await rpc('select status from commerce_orders where id=$1',[e])).status,'cancelled');
 await as(host);await db.query("update loop_devices set data=data||'{\"listPrice\":18}'::jsonb where id='exp-item'");
 assert.equal((await rpc("select data->>'listPrice' p from loop_devices where id='exp-item'")).p,'18');
 await as(buyer);await rejects('select commerce_expire_orders()',[],'permission denied');
 // an order with a PaymentIntent is left to the Stripe-aware job
 await db.exec('reset role');await device('stuck-item');await as(other);
 const s=(await rpc("select (commerce_reserve_device('stuck-item',gen_random_uuid())).id")).id;
 await rpc(`select commerce_choose_shipping($1,'pickup','{}')`,[s]);
 await db.exec('reset role');await rpc('select commerce_begin_charge($1)',[s]);
 await db.query("update commerce_payments set intent_id='pi_stuck' where order_id=$1",[s]);
 await db.query("update commerce_orders set created_at=now()-interval '3 hours' where id=$1",[s]);
 assert.equal((await rpc('select commerce_expire_orders() n')).n,0);
 assert.deepEqual(await rpc('select order_id,intent_id from commerce_stuck_orders()'),{order_id:s,intent_id:'pi_stuck'});
 assert.equal((await rpc('select commerce_expire_order($1) ok',[s])).ok,true);
 assert.equal((await rpc('select status from commerce_payments where order_id=$1',[s])).status,'failed');
 assert.equal((await rpc('select status from commerce_orders where id=$1',[s])).status,'cancelled');
 assert.equal((await rpc('select commerce_expire_order($1) ok',[o])).ok,false,'a paid order is never expired');

 // 3: auction winner takes the item over; nobody else can
 await device('auc-item');
 const sale=(id,deviceId,price,extra={})=>db.query('insert into loop_transactions(id,data) values($1,$2)',[id,{id,type:'sell',userId:host,sellerId:host,buyerId:buyer,deviceId,price,isAuction:true,...extra}]);
 await as(buyer);
 await db.query("update loop_devices set data=data||jsonb_build_object('ownerId',$1::text,'listPrice',null) where id='auc-item'",[buyer]);
 assert.equal(await owner('auc-item'),host,'no sale yet');
 await db.query('insert into loop_auctions(id,data) values($1,$2)',['a1',{id:'a1',deviceId:'auc-item',sellerId:host,endsAt:new Date(Date.now()-1000).toISOString(),buyNowPrice:null,bids:[{userId:other,amount:20},{userId:buyer,amount:25}]}]);
 await sale('auction-a1','auc-item',25);
 await rejects("update loop_devices set data=data||'{\"name\":\"stolen\"}'::jsonb where id='auc-item'",[],'AWARD_FIELDS');
 await db.query("update loop_devices set data=data||jsonb_build_object('ownerId',$1::text,'listPrice',null,'listedAt',null) where id='auc-item'",[buyer]);
 assert.equal(await owner('auc-item'),buyer);
 await as(other);
 await db.exec('reset role');await device('auc-item2');await sale('auction-a1b','auc-item2',25);
 await db.query('insert into loop_auctions(id,data) values($1,$2)',['a1b',{id:'a1b',deviceId:'auc-item2',sellerId:host,endsAt:new Date(Date.now()+3600000).toISOString(),bids:[{userId:buyer,amount:25}]}]);
 await as(buyer);
 await db.query("update loop_devices set data=data||jsonb_build_object('ownerId',$1::text) where id='auc-item2'",[buyer]);
 assert.equal(await owner('auc-item2'),host,'auction has not ended yet');
 // live winner of one piece out of stock
 await db.exec('reset role');await device('live-item',{quantity:3});
 await db.query('insert into loop_live_shows(id,data) values($1,$2)',['show-1',{id:'show-1',hostId:host}]);
 await db.query('insert into loop_live_events(id,data) values($1,$2)',['ev1',{id:'ev1',showId:'show-1',type:'bid',userId:buyer,lot:2,amount:12}]);
 await sale('live-show-1-2','live-item',12);
 await as(buyer);
 await rejects("update loop_devices set data=data||'{\"quantity\":1}'::jsonb where id='live-item'",[],'AWARD_FORBIDDEN');
 assert.equal((await rpc("select data->>'quantity' q from loop_devices where id='live-item'")).q,'3','only one piece at a time');
 await db.query("update loop_devices set data=data||'{\"quantity\":2}'::jsonb where id='live-item'");
 assert.equal((await rpc("select data->>'quantity' q from loop_devices where id='live-item'")).q,'2');
 await as(other);
 await db.query("update loop_devices set data=data||jsonb_build_object('ownerId',$1::text) where id='live-item'",[other]);
 assert.equal(await owner('live-item'),host,'a bystander gets nothing');

 // refund: the seller takes the item back
 await db.exec('reset role');
 await db.query("update loop_devices set data=data||jsonb_build_object('ownerId',$1::text) where id='fix-item'",[buyer]);
 await as(host);
 await db.query("update loop_devices set data=data||jsonb_build_object('ownerId',$1::text) where id='fix-item'",[host]);
 assert.equal(await owner('fix-item'),buyer,'no refund yet');
 await db.exec('reset role');
 await db.query("insert into loop_deliveries(id,data) values('del-r',$1)",[{id:'del-r',deviceId:'fix-item',sellerId:host,buyerId:buyer,dispute:{status:'refunded'}}]);
 await as(host);
 await db.query("update loop_devices set data=data||jsonb_build_object('ownerId',$1::text) where id='fix-item'",[host]);
 assert.equal(await owner('fix-item'),host);
 // 5: an accepted price offer is the order price; it is spent by the purchase
 await db.exec('reset role');await device('offer-item',{listPrice:30,parcelSize:'small'});
 await db.query('insert into loop_bargains(id,data) values($1,$2)',['b1',{id:'b1',deviceId:'offer-item',buyerId:buyer,sellerId:host,amount:20,counterAmount:25,status:'accepted',updatedAt:new Date().toISOString(),validUntil:new Date(Date.now()+3600000).toISOString()}]);
 await as(other);
 const full=(await rpc("select (commerce_reserve_device('offer-item',gen_random_uuid())).total_cents t")).t;
 assert.equal(Number(full),3000,'another buyer pays the listing price');
 await db.exec('reset role');await db.query("update commerce_orders set status='cancelled' where source_device='offer-item'");
 await as(buyer);
 const ob=(await rpc("select (commerce_reserve_device('offer-item',gen_random_uuid())).id")).id;
 assert.equal(Number((await rpc('select total_cents t from commerce_orders where id=$1',[ob])).t),2500,'the offer price, not the listing price');
 await rpc(`select commerce_choose_shipping($1,'courier','{"address":"Ilica 1, Zagreb"}')`,[ob]);
 assert.equal(Number((await rpc('select total_cents t from commerce_orders where id=$1',[ob])).t),3100);
 await db.exec('reset role');await rpc('select commerce_begin_charge($1)',[ob]);
 await db.query("update commerce_payments set intent_id='pi_offer' where order_id=$1",[ob]);
 await rpc("select commerce_settle_intent('ev_offer',$1,'pi_offer','ch_offer',3100,'EUR')",[ob]);
 assert.equal((await rpc("select data->>'status' s from loop_bargains where id='b1'")).s,'used');
 console.log('PASS: 5% fee, server shipping price, delivery record, order expiry, stuck orders, auction/live takeover and refund return');
}
