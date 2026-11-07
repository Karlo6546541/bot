import Stripe from 'npm:stripe@23.0.0';
import { services,authenticate,response,failure,customerFor,savedCard } from '../_shared/stripe.ts';
import { authenticationResponse } from '../_shared/charge.ts';
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return response(200,{});
 if(req.method!=='POST')return response(405,{error:'METHOD_NOT_ALLOWED'});
 try{
  const user=await authenticate(req);const body=await req.json();
  if(typeof body.showId!=='string'||!['quick','show'].includes(body.kind)||!Number.isSafeInteger(body.amountCents)||body.amountCents<(body.kind==='show'?300:100)||body.amountCents>5000||!/^[-0-9a-f]{36}$/i.test(body.requestId??''))return response(400,{error:'INVALID_PROMOTION'});
  const svc=await services();const customer=await customerFor(svc.stripe,svc.admin,user);
  const {data:profile}=await svc.admin.from('commerce_customers').select('consent_at').eq('user_id',user.id).single();
  const card=profile?.consent_at?await savedCard(svc.stripe,customer):null;if(!card)return response(409,{error:'CARD_REQUIRED'});
  const {data:p,error}=await svc.admin.rpc('commerce_begin_promotion',{p_user:user.id,p_show:body.showId,p_kind:body.kind,p_amount:body.amountCents,p_request:body.requestId});if(error)throw error;
  if(p.status==='paid')return response(200,{status:'paid',mode:'test'});
  if(p.status==='refunded')return response(409,{error:'PROMOTION_REFUNDED'});
  let intent:Stripe.PaymentIntent;
  if(p.intent_id)intent=await svc.stripe.paymentIntents.retrieve(p.intent_id);
  else{
   intent=await svc.stripe.paymentIntents.create({amount:Number(p.amount_cents),currency:'eur',customer,payment_method:card.id,metadata:{promotion_id:p.id,purpose:'promotion'}},{idempotencyKey:`promotion-intent-${p.id}`});
   const {error:e}=await svc.admin.from('commerce_promotions').update({intent_id:intent.id}).eq('id',p.id);if(e)throw e;
  }
  if(intent.status==='requires_payment_method'&&intent.last_payment_error?.code!=='authentication_required')intent=await svc.stripe.paymentIntents.update(intent.id,{payment_method:card.id});
  if(intent.status==='requires_confirmation'){
   const {error:stateError}=await svc.admin.from('commerce_promotions').update({status:'pending'}).eq('id',p.id);if(stateError)throw stateError;
   try{intent=await svc.stripe.paymentIntents.confirm(intent.id,{off_session:true},{idempotencyKey:`promotion-confirm-${p.id}-${card.id}-${p.attempt}`});}
   catch(error){if(error instanceof Stripe.errors.StripeCardError)intent=await svc.stripe.paymentIntents.retrieve(intent.id);else throw error;}
  }
  if(intent.status==='succeeded'){
   const {error:e}=await svc.admin.rpc('commerce_settle_promotion',{p_id:p.id,p_intent:intent.id,p_amount:intent.amount_received});if(e)throw e;
   return response(200,{status:'paid',mode:'test'});
  }
  if(intent.status==='requires_action'||intent.last_payment_error?.code==='authentication_required')return authenticationResponse(svc,intent,card.id);
  if(intent.status==='processing')return response(200,{status:'processing'});
  await svc.admin.from('commerce_promotions').update({status:'failed',attempt:p.attempt+1}).eq('id',p.id).eq('attempt',p.attempt);
  return response(402,{error:'CARD_DECLINED'});
 }catch(error){return failure(error);}
});
