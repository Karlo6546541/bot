import { services } from '../_shared/stripe.ts';
import { integrationConfig,adminClient } from '../_shared/config.ts';
import { reverseSellerTransfer } from '../_shared/reversal.ts';
// Scheduler-only; a browser cannot select destinations or transfer amounts.
Deno.serve(async(req:Request)=>{
 if(req.method!=='POST')return new Response(null,{status:405});
 const config=await integrationConfig();
 if(!config.STRIPE_RELEASE_JOB_SECRET||req.headers.get('x-subhasto-job')!==config.STRIPE_RELEASE_JOB_SECRET)return new Response(null,{status:401});
 const {data:rows,error}=await adminClient().from('commerce_payments').select('order_id').eq('status','paid').eq('disputed',false).eq('refunded_cents',0).is('transfer_id',null).is('payout_id',null).not('picked_up_at','is',null).order('picked_up_at').limit(50);
 if(error)return new Response('Retry later',{status:503});
 const {data:risks,error:riskError}=await adminClient().from('commerce_payments').select('order_id,transfer_id').not('transfer_id','is',null).not('released_at','is',null).or('disputed.eq.true,refunded_cents.gt.0').limit(50);
 if(riskError)return new Response('Retry later',{status:503});
 const {data:stuck}=await adminClient().rpc('commerce_stuck_orders');
 const {count:refundDue}=await adminClient().from('commerce_payments').select('order_id',{count:'exact',head:true}).eq('status','paid').eq('refunded_cents',0).not('refund_requested_at','is',null);
 if(!rows?.length&&!risks?.length&&!stuck?.length&&!refundDue)return Response.json({mode:'test',released:0});
 let svc;
 try{svc=await services();}catch{return new Response('Stripe configuration unavailable',{status:503});}
 // Reconcile risk events that raced with a successful transfer/database write.
 for(const risk of risks??[]){
  try{await reverseSellerTransfer(svc,risk);}catch{console.error('risk_reversal_pending');}
 }
 // Orders whose PaymentIntent never succeeded would keep their listing frozen: ask Stripe, then expire.
 try{
  for(const s of stuck??[]){
   try{
    let intent=await svc.stripe.paymentIntents.retrieve(s.intent_id);
    if(intent.status==='succeeded'||intent.status==='processing')continue;
    if(intent.status!=='canceled')intent=await svc.stripe.paymentIntents.cancel(s.intent_id);
    if(intent.status==='canceled')await svc.admin.rpc('commerce_expire_order',{p_order:s.order_id});
   }catch{console.error('stuck_order_expiry_failed');}
  }
 }catch{console.error('stuck_order_query_failed');}
 // Prihvaćen povrat (spor u aplikaciji): novac se vraća na karticu kupca.
 let refunded=0;
 try{
  const {data:refunds}=await svc.admin.from('commerce_payments').select('order_id,intent_id,destination_account').eq('status','paid').eq('refunded_cents',0).not('refund_requested_at','is',null).not('intent_id','is',null).limit(20);
  for(const r of refunds??[]){
   try{
    await svc.stripe.refunds.create({payment_intent:r.intent_id,...(r.destination_account?{reverse_transfer:true}:{}),metadata:{order_id:r.order_id}},{idempotencyKey:`order-refund-${r.order_id}`});
    refunded++;
   }catch(error){console.error('refund_failed',{type:error instanceof Error?error.name:'unknown'});}
  }
 }catch{console.error('refund_query_failed');}
 let released=0;
 for(const row of rows??[]){
  try{
   const {data:p,error:claimError}=await svc.admin.rpc('commerce_claim_release',{p_order:row.order_id});if(claimError||!p)continue;
   if(p.destination_account){
    // Novac je već na povezanom računu prodavača (drži ga Stripe): isplata na IBAN.
    const charge=await svc.stripe.charges.retrieve(p.source_charge);
    if(charge.livemode||charge.disputed||charge.amount_refunded>0)continue;
    const opts={stripeAccount:p.destination_account};
    // Izgubljen odgovor ranijeg pokušaja: preuzmi postojeću isplatu umjesto dvostruke.
    const recent=await svc.stripe.payouts.list({limit:100},opts);
    let payout=recent.data.find(x=>x.metadata?.order_id===row.order_id&&x.status!=='failed'&&x.status!=='canceled');
    if(!payout){
     const balance=await svc.stripe.balance.retrieve({},opts);
     const available=balance.available.find(b=>b.currency==='eur')?.amount??0;
     if(available<Number(p.seller_cents))continue; // sredstva još nisu raspoloživa; pokušaj kasnije
     payout=await svc.stripe.payouts.create({amount:Number(p.seller_cents),currency:'eur',metadata:{order_id:row.order_id}},{...opts,idempotencyKey:`seller-payout-${row.order_id}-${new Date().toISOString().slice(0,13)}`});
    }
    const {error:saveError}=await svc.admin.from('commerce_payments').update({payout_id:payout.id,paid_out_at:new Date().toISOString(),released_at:new Date().toISOString()}).eq('order_id',row.order_id);
    if(!saveError)released++;
    continue;
   }
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
 return Response.json({mode:'test',released,refunded});
});
