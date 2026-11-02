import { services } from '../_shared/stripe.ts';
import { integrationConfig,adminClient } from '../_shared/config.ts';
import { reverseSellerTransfer } from '../_shared/reversal.ts';
// Scheduler-only; a browser cannot select destinations or transfer amounts.
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return new Response(null,{status:405});
 const config=await integrationConfig();
 if(!config.STRIPE_RELEASE_JOB_SECRET||req.headers.get('x-subhasto-job')!==config.STRIPE_RELEASE_JOB_SECRET)return new Response(null,{status:401});
 const {data:rows,error}=await adminClient().from('commerce_payments').select('order_id').eq('status','paid').eq('disputed',false).eq('refunded_cents',0).is('transfer_id',null).not('picked_up_at','is',null).order('picked_up_at').limit(50);
 if(error)return new Response('Retry later',{status:503});
 const {data:risks,error:riskError}=await adminClient().from('commerce_payments').select('order_id,transfer_id').not('transfer_id','is',null).not('released_at','is',null).or('disputed.eq.true,refunded_cents.gt.0').limit(50);
 if(riskError)return new Response('Retry later',{status:503});
 if(!rows?.length&&!risks?.length)return Response.json({mode:'test',released:0});
 let svc;
 try{svc=await services();}catch{return new Response('Stripe configuration unavailable',{status:503});}
 // Reconcile risk events that raced with a successful transfer/database write.
 for(const risk of risks??[]){
  try{await reverseSellerTransfer(svc,risk);}catch{console.error('risk_reversal_pending');}
 }
 let released=0;
 for(const row of rows??[]){
  try{
   const {data:p,error:claimError}=await svc.admin.rpc('commerce_claim_release',{p_order:row.order_id});if(claimError||!p)continue;
   const {data:order}=await svc.admin.from('commerce_orders').select('seller_id').eq('id',row.order_id).single();if(!order)continue;
   const {data:seller}=await svc.admin.from('commerce_sellers').select('stripe_account_id').eq('user_id',order.seller_id).single();if(!seller)continue;
   const account=await svc.stripe.v2.core.accounts.retrieve(seller.stripe_account_id,{include:['configuration.recipient']});
   if(account.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status!=='active')continue;
   const charge=await svc.stripe.charges.retrieve(p.source_charge);
   if(charge.livemode||charge.disputed||charge.amount_refunded>0)continue;
   const {data:current}=await svc.admin.from('commerce_payments').select('disputed,refunded_cents').eq('order_id',row.order_id).single();
   if(!current||current.disputed||current.refunded_cents>0)continue;
   const transfer=await svc.stripe.transfers.create({amount:Number(p.seller_cents),currency:'eur',destination:seller.stripe_account_id,source_transaction:p.source_charge,transfer_group:`order_${row.order_id}`,metadata:{order_id:row.order_id}},{idempotencyKey:`seller-release-${row.order_id}`});
   const {error:saveError}=await svc.admin.from('commerce_payments').update({transfer_id:transfer.id,released_at:new Date().toISOString()}).eq('order_id',row.order_id);
   if(!saveError)released++;
  }catch(error){console.error('release_failed',{type:error instanceof Error?error.name:'unknown'});}
 }
 return Response.json({mode:'test',released});
});
