import assert from 'node:assert/strict';
import { chargeOrder } from '../functions/_shared/charge.ts';
import { reverseSellerTransfer } from '../functions/_shared/reversal.ts';

const schedules:string[]=[];
const sellerAccount=(status:string)=>({balanceSettings:{update:async(body:{payments:{payouts:{schedule:{interval:string}}}},o:{stripeAccount:string})=>{schedules.push(`${o.stripeAccount}:${body.payments.payouts.schedule.interval}`);}},v2:{core:{accounts:{retrieve:async()=>({configuration:{recipient:{capabilities:{stripe_balance:{stripe_transfers:{status}}}}}})}}}});
function table(steps:string[],payment:Record<string,unknown>|null){
 return (name:string)=>({
  select:()=>({eq:()=>({maybeSingle:async()=>({data:name==='commerce_sellers'?{stripe_account_id:'acct_seller'}:payment})})}),
  update:(values:Record<string,unknown>)=>({eq:async()=>{if(name==='commerce_payments'){steps.push('persist');assert.equal(values.destination_account,'acct_seller');}return{error:null};}}),
 });
}
Deno.test('off-session charge sends the seller share to the connected account and fulfills once',async()=>{
 const steps:string[]=[];let params:Record<string,unknown>={};
 const svc={config:{},stripe:{...sellerAccount('active'),paymentIntents:{
  create:async(body:Record<string,unknown>,options:{idempotencyKey:string})=>{steps.push('create');params=body;assert.equal(options.idempotencyKey,'order-intent-v3-order');return{id:'pi_test',status:'requires_confirmation',payment_method:'pm_test'};},
  confirm:async(_id:string,body:{off_session:boolean})=>{steps.push('confirm');assert.equal(body.off_session,true);return{id:'pi_test',status:'succeeded',amount_received:1900,currency:'eur',latest_charge:'ch_test'};},
 }},admin:{
  rpc:async(name:string)=>{steps.push(name);return name==='commerce_begin_charge'?{data:{attempt:1,seller_cents:1805},error:null}:{error:null};},
  from:table(steps,null),
 }} as unknown as Parameters<typeof chargeOrder>[0];
 const response=await chargeOrder(svc,{id:'order',seller_id:'seller',total_cents:1900,currency:'EUR'},'cus_test','pm_test',true);
 assert.equal(response.status,200);assert.equal((await response.json()).status,'paid');
 // The platform keeps only its commission (and shipping); the rest is held by Stripe on the seller's account.
 assert.deepEqual(params.transfer_data,{destination:'acct_seller',amount:1805});
 assert.deepEqual(steps,['commerce_begin_charge','create','persist','confirm','commerce_settle_intent']);
 // Money held on the seller's account is paid out only by stripe-release after delivery.
 assert.deepEqual(schedules,['acct_seller:manual']);
});

Deno.test('an unverified seller never blocks the purchase: the money waits at Stripe until payout setup',async()=>{
 const steps:string[]=[];let params:Record<string,unknown>={};
 const svc={config:{},stripe:{...sellerAccount('pending'),paymentIntents:{
  create:async(body:Record<string,unknown>)=>{steps.push('create');params=body;return{id:'pi_wait',status:'requires_confirmation',payment_method:'pm_test'};},
  confirm:async()=>({id:'pi_wait',status:'succeeded',amount_received:1900,currency:'eur',latest_charge:'ch_wait'}),
 }},admin:{
  rpc:async(name:string)=>{steps.push(name);return name==='commerce_begin_charge'?{data:{attempt:1,seller_cents:1805},error:null}:{error:null};},
  from:(name:string)=>({
   select:()=>({eq:()=>({maybeSingle:async()=>({data:name==='commerce_sellers'?{stripe_account_id:'acct_seller'}:null})})}),
   update:(values:Record<string,unknown>)=>({eq:async()=>{if(name==='commerce_payments'){assert.equal(values.destination_account,null);}return{error:null};}}),
  }),
 }} as unknown as Parameters<typeof chargeOrder>[0];
 const response=await chargeOrder(svc,{id:'order',seller_id:'seller',total_cents:1900,currency:'EUR'},'cus_test','pm_test',false);
 assert.equal(response.status,200);assert.equal((await response.json()).status,'paid');
 assert.equal(params.transfer_data,undefined,'no transfer to an account that cannot receive money yet');
});

Deno.test('authentication decline resumes the same intent without another off-session attempt',async()=>{
 let confirms=0;
 const svc={config:{STRIPE_PUBLISHABLE_KEY:'pk_test_example'},admin:{rpc:async()=>({data:{intent_id:'pi_saved',attempt:2}}),from:table([],{intent_id:'pi_saved'})},stripe:{paymentIntents:{
  retrieve:async()=>({id:'pi_saved',status:'requires_payment_method',client_secret:'test_secret',last_payment_error:{code:'authentication_required'}}),
  confirm:async()=>{confirms++;},
 }}} as unknown as Parameters<typeof chargeOrder>[0];
 const response=await chargeOrder(svc,{id:'order',seller_id:'seller',total_cents:1900,currency:'EUR'},'cus_test','pm_test',true);
 assert.equal(confirms,0);const result=await response.json();
 assert.equal(result.status,'requires_action');assert.equal(result.confirmationRequired,true);assert.equal(result.paymentMethod,'pm_test');
});

Deno.test('risk reversal retries do not reverse the seller transfer twice',async()=>{
 let reversed=0,calls=0,writes=0;
 const svc={stripe:{transfers:{
  retrieve:async()=>({id:'tr_test',amount:1786,amount_reversed:reversed}),
  createReversal:async(_id:string,body:{amount:number},options:{idempotencyKey:string})=>{assert.equal(options.idempotencyKey,'risk-reversal-tr_test');reversed+=body.amount;calls++;},
 }},admin:{from:()=>({update:()=>({eq:async()=>{writes++;return{error:null};}})})}} as unknown as Parameters<typeof reverseSellerTransfer>[0];
 await reverseSellerTransfer(svc,{order_id:'order',transfer_id:'tr_test'});
 await reverseSellerTransfer(svc,{order_id:'order',transfer_id:'tr_test'});
 assert.equal(reversed,1786);assert.equal(calls,1);assert.equal(writes,2);
});
