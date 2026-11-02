import assert from 'node:assert/strict';
import { chargeOrder } from '../functions/_shared/charge.ts';

Deno.test('off-session charge persists one platform intent before confirmation and fulfills once',async()=>{
 const steps:string[]=[];let params:Record<string,unknown>={};
 const svc={config:{},stripe:{paymentIntents:{
  create:async(body:Record<string,unknown>,options:{idempotencyKey:string})=>{steps.push('create');params=body;assert.equal(options.idempotencyKey,'order-intent-v2-order');return{id:'pi_test',status:'requires_confirmation',payment_method:'pm_test'};},
  confirm:async(_id:string,body:{off_session:boolean})=>{steps.push('confirm');assert.equal(body.off_session,true);return{id:'pi_test',status:'succeeded',amount_received:1900,currency:'eur',latest_charge:'ch_test'};},
 }},admin:{
  rpc:async(name:string)=>{steps.push(name);return name==='commerce_begin_charge'?{data:{attempt:1},error:null}:{error:null};},
  from:()=>({update:()=>({eq:async()=>{steps.push('persist');return{error:null};}})}),
 }} as unknown as Parameters<typeof chargeOrder>[0];
 const response=await chargeOrder(svc,{id:'order',total_cents:1900,currency:'EUR'},'cus_test','pm_test',true);
 assert.equal(response.status,200);assert.equal((await response.json()).status,'paid');
 assert.equal(params.transfer_data,undefined);assert.equal(params.application_fee_amount,undefined);
 assert.deepEqual(steps,['commerce_begin_charge','create','persist','confirm','commerce_settle_intent']);
});

Deno.test('authentication decline resumes the same intent without another off-session attempt',async()=>{
 let confirms=0;
 const svc={config:{STRIPE_PUBLISHABLE_KEY:'pk_test_example'},admin:{rpc:async()=>({data:{intent_id:'pi_saved',attempt:2}})},stripe:{paymentIntents:{
  retrieve:async()=>({id:'pi_saved',status:'requires_payment_method',client_secret:'test_secret',last_payment_error:{code:'authentication_required'}}),
  confirm:async()=>{confirms++;},
 }}} as unknown as Parameters<typeof chargeOrder>[0];
 const response=await chargeOrder(svc,{id:'order',total_cents:1900,currency:'EUR'},'cus_test','pm_test',true);
 assert.equal(confirms,0);const result=await response.json();
 assert.equal(result.status,'requires_action');assert.equal(result.confirmationRequired,true);assert.equal(result.paymentMethod,'pm_test');
});
