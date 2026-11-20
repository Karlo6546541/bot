import {readFileSync} from 'node:fs';
// Runs after the order-fix tests: server-settled auctions, card-gated bids,
// 24 h payment deadline, delivery-driven release.
export async function auctionTests(db,assert,as,rpc,rejects,{host,buyer,other}) {
 await db.exec('reset role');
 await db.exec(`create schema if not exists cron; create table cron.job(jobid bigserial primary key,jobname text,schedule text,command text);
 create function cron.schedule(n text,s text,c text) returns bigint language sql as $$ insert into cron.job(jobname,schedule,command) values(n,s,c) returning jobid $$;
 create function cron.unschedule(j bigint) returns boolean language sql as $$ delete from cron.job where jobid=j returning true $$;
 create table public.loop_users(id text primary key,data jsonb);
 create table public.loop_notifications(id text primary key,data jsonb,updated_at timestamptz default now());
 alter table public.loop_auctions add column if not exists updated_at timestamptz default now();
 alter table public.loop_deliveries add column if not exists updated_at timestamptz default now();
 grant all on public.loop_users,public.loop_notifications to authenticated,service_role;`);
 await db.exec(readFileSync(new URL('../migrations/20261111100000_subhasto_auction_settlement.sql',import.meta.url),'utf8'));
 await db.exec(readFileSync(new URL('../migrations/20261116120000_subhasto_auctions_stripe.sql',import.meta.url),'utf8'));
 assert.deepEqual((await db.query('select jobname from cron.job order by 1')).rows.map(r=>r.jobname),['subhasto-auction-settle','subhasto-auto-delivered','subhasto-order-expiry']);
 for(const [id,address] of [[host,''],[buyer,'Ilica 1, Zagreb'],[other,'']]) await db.query('insert into loop_users values($1,$2)',[id,{id,username:'u'+id.slice(-1),address}]);
 await db.query("insert into commerce_sellers(user_id,stripe_account_id,transfers_active) values($1,'acct_host',true) on conflict(user_id) do update set transfers_active=true",[host]);
 const device=(id,extra={})=>db.query('insert into loop_devices(id,data) values($1,$2)',[id,{id,name:'Karta '+id,model:'',ownerId:host,quantity:1,parcelSize:'small',...extra}]);
 const auction=(id,dev,extra={})=>db.query('insert into loop_auctions(id,data) values($1,$2)',[id,{id,deviceId:dev,deviceName:'Karta '+dev,sellerId:host,sellerLabel:'host',startPrice:10,createdAt:new Date(Date.now()-3600e3).toISOString(),endsAt:new Date(Date.now()+3600e3).toISOString(),status:'active',bids:[],kind:'classic',floorPrice:0,...extra}]);
 const bid=(id,user,amount)=>db.query(`update loop_auctions set data=jsonb_set(data,'{bids}',(data->'bids')||$2::jsonb) where id=$1`,[id,JSON.stringify([{userId:user,userLabel:'x',amount,time:new Date().toISOString()}])]);
 const end=id=>db.query(`update loop_auctions set data=data||jsonb_build_object('endsAt',$2::text) where id=$1`,[id,new Date(Date.now()-60e3).toISOString()]);
 const notes=async(user,kind)=>(await rpc("select count(*)::int n from loop_notifications where data->>'userId'=$1 and data->>'kind'=$2",[user,kind])).n;

 // 1: only classic and Dutch; the client cannot publish a sealed or settled auction
 await device('a1');await as(host);
 await rejects('insert into loop_auctions(id,data) values($1,$2)',['bad',{id:'bad',kind:'sealed',status:'active',bids:[],sellerId:host}],'AUCTION_KIND_UNAVAILABLE');
 await rejects('insert into loop_auctions(id,data) values($1,$2)',['bad',{id:'bad',kind:'classic',status:'sold',bids:[],sellerId:host}],'AUCTION_SETTLED_BY_SERVER');
 await auction('auc1','a1');

 // 2: a bid needs a linked card
 await as(buyer);
 await rejects(`update loop_auctions set data=jsonb_set(data,'{bids}',$2::jsonb) where id=$1`,['auc1',JSON.stringify([{userId:buyer,userLabel:'b',amount:25,time:new Date().toISOString()}])],'CARD_REQUIRED');
 await db.exec('reset role');
 await db.query("insert into commerce_customers(user_id,customer_id,consent_at) values($1,'cus_buyer',now()) on conflict(user_id) do update set consent_at=now()",[buyer]);
 await as(buyer);await bid('auc1',buyer,25);
 await rejects(`update loop_auctions set data=data||'{"status":"sold"}'::jsonb where id='auc1'`,[],'AUCTION_SETTLED_BY_SERVER');
 assert.equal((await rpc("select auction_settle('auc1') is null as none")).none,true,'a running auction is not settled');

 // 3: the server settles: order = highest bid + courier shipping, notifications
 await db.exec('reset role');await end('auc1');
 assert.equal((await rpc('select auction_settle_due() n')).n,1);
 const o=await rpc("select id,buyer_id,total_cents t,shipping_cents s,auction_base_cents b,status from commerce_orders where source_auction='auc1'");
 assert.deepEqual({t:o.t,s:o.s,b:o.b,status:o.status,buyer:o.buyer_id},{t:3100,s:600,b:1000,status:'awaiting_payment',buyer});
 assert.equal((await rpc("select data->>'status' s from loop_auctions where id='auc1'")).s,'sold');
 assert.equal(await notes(buyer,'auctionWon'),1);assert.equal(await notes(host,'auctionSold'),1);
 assert.equal((await rpc("select destination->>'address' a from commerce_shipments where order_id=$1",[o.id])).a,'Ilica 1, Zagreb');
 assert.equal((await rpc('select auction_settle_due() n')).n,0,'settling is idempotent');
 await as(host);await rejects(`update loop_auctions set data=data||'{"startPrice":1}'::jsonb where id='auc1'`,[],'AUCTION_CLOSED');

 // 4: commission 10 % of the uplift over the start price; paid order hands the item over
 await db.exec('reset role');await rpc('select commerce_begin_charge($1)',[o.id]);
 assert.deepEqual(await rpc('select item_cents,fee_cents,seller_cents from commerce_payments where order_id=$1',[o.id]),{item_cents:2500,fee_cents:150,seller_cents:2350});
 await db.query("update commerce_payments set intent_id='pi_auc1',destination_account='acct_host' where order_id=$1",[o.id]);
 await rpc("select commerce_settle_intent('ev_auc1',$1,'pi_auc1','ch_auc1',3100,'EUR')",[o.id]);
 assert.equal((await rpc("select data->>'ownerId' o from loop_devices where id='a1'")).o,buyer);
 const del='del-stripe-sale-'+o.id;
 const d=(await rpc('select data from loop_deliveries where id=$1',[del])).data;
 assert.equal(d.fromAuction,true);assert.equal(d.destination,'Ilica 1, Zagreb');assert.equal(d.cost,6);

 // 5: money stays held until the buyer confirms receipt (or 48 h after delivery)
 await rejects('select commerce_claim_release($1)',[o.id],'RELEASE_NOT_READY');
 await as(buyer);await rpc(`select commerce_choose_shipping($1,'courier','{"address":"Vukovarska 5, Split"}')`,[o.id]);
 assert.equal((await rpc('select data->>\'destination\' a from loop_deliveries where id=$1',[del])).a,'Vukovarska 5, Split');
 await rejects(`select commerce_choose_shipping($1,'pickup','{}')`,[o.id],'SHIPPING_METHOD_LOCKED');
 await rejects(`update loop_deliveries set data=data||jsonb_build_object('handedOverAt',now()) where id=$1`,[del],'SELLER_ONLY');
 await as(host);
 await db.query(`update loop_deliveries set data=data||jsonb_build_object('handedOverAt',now()) where id=$1`,[del]);
 await rejects(`update loop_deliveries set data=data||jsonb_build_object('confirmedAt',now()) where id=$1`,[del],'BUYER_ONLY');
 await db.exec('reset role');
 assert.equal((await rpc('select status from commerce_orders where id=$1',[o.id])).status,'shipped');
 await rejects('select commerce_claim_release($1)',[o.id],'RELEASE_NOT_READY');
 await as(buyer);await db.query(`update loop_deliveries set data=data||jsonb_build_object('confirmedAt',now()) where id=$1`,[del]);
 await db.exec('reset role');
 assert.equal((await rpc('select status from commerce_orders where id=$1',[o.id])).status,'delivered');
 assert.equal((await rpc('select (commerce_claim_release($1)).seller_cents c',[o.id])).c,2350);
 await db.query("update commerce_payments set payout_id='po_1' where order_id=$1",[o.id]);
 await rejects('select commerce_claim_release($1)',[o.id],'RELEASE_NOT_READY');

 // 5b: no confirmation: delivered 5 days after handover, then the 48 h window; a dispute holds the money
 await device('a5');await as(host);await auction('auc5','a5');await as(buyer);await bid('auc5',buyer,20);
 await db.exec('reset role');await end('auc5');await rpc('select auction_settle_due()');
 const o5=(await rpc("select id from commerce_orders where source_auction='auc5'")).id;
 await rpc('select commerce_begin_charge($1)',[o5]);await db.query("update commerce_payments set intent_id='pi_auc5' where order_id=$1",[o5]);
 await rpc("select commerce_settle_intent('ev_auc5',$1,'pi_auc5','ch_auc5',2600,'EUR')",[o5]);
 const del5='del-stripe-sale-'+o5;
 await db.query(`update loop_deliveries set data=data||jsonb_build_object('handedOverAt',now()-interval '6 days') where id=$1`,[del5]);
 assert.equal((await rpc('select commerce_auto_delivered() n')).n,1);
 await rejects('select commerce_claim_release($1)',[o5],'RELEASE_NOT_READY');
 await db.query("update commerce_payments set picked_up_at=now()-interval '49 hours' where order_id=$1",[o5]);
 await as(buyer);await db.query(`update loop_deliveries set data=data||'{"dispute":{"status":"open","reason":"notAuthentic"}}'::jsonb where id=$1`,[del5]);
 await rejects(`update loop_deliveries set data=jsonb_set(data,'{dispute,status}','"refunded"') where id=$1`,[del5],'SELLER_OR_SUPPORT_ONLY');
 await db.exec('reset role');await rejects('select commerce_claim_release($1)',[o5],'RELEASE_NOT_READY');
 await as(host);await db.query(`update loop_deliveries set data=jsonb_set(data,'{dispute,status}','"refunded"') where id=$1`,[del5]);
 await db.exec('reset role');
 assert.equal((await rpc('select refund_requested_at is not null r from commerce_payments where order_id=$1',[o5])).r,true);

 // 5c: a paid order of a seller without a verified payout account notifies the seller (once)
 await device('a9');await as(host);await auction('auc9','a9');await as(buyer);await bid('auc9',buyer,20);
 await db.exec('reset role');await db.query("update commerce_sellers set transfers_active=false where user_id=$1",[host]);
 await end('auc9');await rpc('select auction_settle_due()');
 const o9=(await rpc("select id from commerce_orders where source_auction='auc9'")).id;
 await rpc('select commerce_begin_charge($1)',[o9]);await db.query("update commerce_payments set intent_id='pi_auc9' where order_id=$1",[o9]);
 await rpc("select commerce_settle_intent('ev_auc9',$1,'pi_auc9','ch_auc9',2600,'EUR')",[o9]);
 assert.equal(await notes(host,'payoutSetup'),1);
 assert.equal((await rpc('select destination_account da from commerce_payments where order_id=$1',[o9])).da,null);
 await db.query("update commerce_sellers set transfers_active=true where user_id=$1",[host]);

 // 6: unpaid win: 24 h, then cancelled; the item stays with the seller; strike for the buyer
 for(const n of [2,3]){
  await device('a'+n);await as(host);await auction('auc'+n,'a'+n);await as(buyer);await bid('auc'+n,buyer,30);
  await db.exec('reset role');await end('auc'+n);await rpc('select auction_settle_due()');
 }
 const o2=(await rpc("select id from commerce_orders where source_auction='auc2'")).id;
 await db.query("update commerce_orders set created_at=now()-interval '2 hours' where source_auction in ('auc2','auc3')");
 assert.equal((await rpc('select commerce_expire_orders() n')).n,0,'an auction order is kept for 24 h');
 await rpc('select auction_payment_due($1)',[o2]);await rpc('select auction_payment_due($1)',[o2]);
 assert.equal(await notes(buyer,'auctionPaymentDue'),1);
 await db.query("update commerce_orders set created_at=now()-interval '25 hours' where source_auction='auc2'");
 assert.equal((await rpc('select commerce_expire_orders() n')).n,1);
 assert.equal((await rpc('select status from commerce_orders where id=$1',[o2])).status,'cancelled');
 assert.deepEqual(await rpc("select data->>'status' s,data->>'unpaid' u from loop_auctions where id='auc2'"),{s:'unsold',u:'true'});
 assert.equal((await rpc("select data->>'ownerId' o from loop_devices where id='a2'")).o,host);
 assert.equal(await notes(host,'auctionUnpaid'),1);assert.equal(await notes(buyer,'bidStrike'),1);
 // an order with a failed PaymentIntent is "stuck" only after 24 h
 const o3=(await rpc("select id from commerce_orders where source_auction='auc3'")).id;
 await rpc('select commerce_begin_charge($1)',[o3]);await db.query("update commerce_payments set intent_id='pi_auc3' where order_id=$1",[o3]);
 assert.equal((await db.query('select * from commerce_stuck_orders()')).rows.length,0);
 await db.query("update commerce_orders set created_at=now()-interval '25 hours' where id=$1",[o3]);
 assert.equal((await db.query('select * from commerce_stuck_orders()')).rows.length,1);
 assert.equal((await rpc('select commerce_expire_order($1) x',[o3])).x,true);
 // two unpaid wins in 90 days: no more bids
 await device('a4');await as(host);await auction('auc4','a4');await as(buyer);
 await rejects(`update loop_auctions set data=jsonb_set(data,'{bids}',$2::jsonb) where id=$1`,['auc4',JSON.stringify([{userId:buyer,userLabel:'b',amount:12,time:new Date().toISOString()}])],'BIDDING_SUSPENDED');

 // 7: Dutch: first buyer with a card takes it at the server price
 await db.exec('reset role');await device('d1');await as(host);
 await rejects('insert into loop_auctions(id,data) values($1,$2)',['bad2',{id:'bad2',kind:'dutch',status:'active',bids:[],sellerId:host}],'AUCTION_KIND_UNAVAILABLE');
 // Stara nizozemska aukcija (od prije) i dalje radi do kraja.
 await db.exec('reset role');
 await auction('dutch1','d1',{kind:'dutch',startPrice:100,floorPrice:50});
 await as(other);await rejects("select auction_take_dutch('dutch1',100)",[],'CARD_REQUIRED');
 await rejects(`update loop_auctions set data=jsonb_set(data,'{bids}',$2::jsonb) where id=$1`,['dutch1',JSON.stringify([{userId:other,userLabel:'o',amount:60,time:new Date().toISOString()}])],'NOT_DUTCH_BID');
 await db.exec('reset role');
 await db.query("insert into commerce_customers(user_id,customer_id,consent_at) values($1,'cus_other',now())",[other]);
 await as(other);await rejects("select auction_take_dutch('dutch1',10)",[],'PRICE_CHANGED');
 const dt=await rpc("select (auction_take_dutch('dutch1',100)).total_cents t");
 assert.ok(dt.t>=5000+600&&dt.t<=10000+600,'price between floor and start, plus shipping');
 await rejects("select auction_take_dutch('dutch1',100)",[],'ALREADY_SOLD');
 await db.exec('reset role');
 assert.equal((await rpc("select auction_base_cents b from commerce_orders where source_auction='dutch1'")).b,5000);

 // 8: "buy now" on a classic auction settles at once
 await device('b1');await as(host);await auction('bn1','b1',{buyNowPrice:40});
 await as(other);await bid('bn1',other,40);
 await db.exec('reset role');
 assert.equal((await rpc('select auction_settle_due() n')).n,1,'the scheduler also settles a reached buy-now price');
 assert.equal((await rpc("select total_cents t from commerce_orders where source_auction='bn1'")).t,4600);
 console.log('PASS: server-settled auctions, card-gated bids, 24 h deadline, strikes, Dutch, delivery-driven release');
}
