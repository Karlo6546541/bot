import Stripe from 'npm:stripe@23.0.0';
import { services,response,appUrl } from './stripe.ts';
type Services=Awaited<ReturnType<typeof services>>;
/** Povezani Stripe račun prodavača koji smije primiti novac, ili null. Usput osvježi zastavicu u bazi. */
export async function sellerDestination(svc:Services,sellerId:string):Promise<string|null>{
 const {data:seller}=await svc.admin.from('commerce_sellers').select('stripe_account_id').eq('user_id',sellerId).maybeSingle();
 if(!seller)return null;
 const account=await svc.stripe.v2.core.accounts.retrieve(seller.stripe_account_id,{include:['configuration.recipient']});
 const active=account.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status==='active';
 await svc.admin.from('commerce_sellers').update({transfers_active:active,checked_at:new Date().toISOString()}).eq('user_id',sellerId);
 return active?seller.stripe_account_id as string:null;
}
// Jedan PaymentIntent po narudžbi. Novac ne ostaje na platformi: naplata odmah
// prenosi prodavačev dio na njegov povezani Stripe račun (destination charge),
// gdje ga drži Stripe do isplate (stripe-release). Platformi ostaju provizija i dostava.
export async function chargeOrder(svc:Services,order:{id:string;seller_id:string;total_cents:number;currency:string},customer:string,method:string,resume:boolean){
 const {data:existing}=await svc.admin.from('commerce_payments').select('intent_id').eq('order_id',order.id).maybeSingle();
 // Kao na Vintedu: kupnja nikad ne čeka prodavačevu potvrdu. Ako prodavač već može primati novac,
 // naplata ide izravno na njegov račun; inače novac čeka kod Stripea (saldo platforme) dok prodavač
 // ne dovrši potvrdu — tada ga stripe-release prebacuje i isplaćuje na IBAN.
 let destination:string|null=null;
 if(!existing?.intent_id)destination=await sellerDestination(svc,order.seller_id);
 const {data:payment,error}=await svc.admin.rpc('commerce_begin_charge',{p_order:order.id});if(error)throw error;
 let intent:Stripe.PaymentIntent;
 if(payment.intent_id){intent=await svc.stripe.paymentIntents.retrieve(payment.intent_id);}
 else{
  intent=await svc.stripe.paymentIntents.create({amount:Number(order.total_cents),currency:order.currency.toLowerCase(),customer,payment_method:method,metadata:{order_id:order.id,purpose:'marketplace'},transfer_group:`order_${order.id}`,...(destination?{transfer_data:{destination,amount:Number(payment.seller_cents)}}:{})},{idempotencyKey:`order-intent-v3-${order.id}`});
  const {error:saveError}=await svc.admin.from('commerce_payments').update({intent_id:intent.id,destination_account:destination}).eq('order_id',order.id);if(saveError)throw saveError;
 }
 if(intent.status==='requires_payment_method'&&intent.last_payment_error?.code==='authentication_required')return authenticationResponse(svc,intent,method);
 if(intent.status==='requires_payment_method')intent=await svc.stripe.paymentIntents.update(intent.id,{payment_method:method});
 if(intent.status==='requires_confirmation'||intent.status==='requires_payment_method'){
  try{intent=await svc.stripe.paymentIntents.confirm(intent.id,{off_session:true},{idempotencyKey:`order-confirm-${order.id}-${intent.payment_method}-${payment.attempt}`});}
  catch(error){if(error instanceof Stripe.errors.StripeCardError)intent=await svc.stripe.paymentIntents.retrieve(intent.id);else throw error;}
 }
 if(intent.status==='succeeded'){
  const {error:settleError}=await svc.admin.rpc('commerce_settle_intent',{p_event:`intent:${intent.id}`,p_order:order.id,p_intent:intent.id,p_charge:typeof intent.latest_charge==='string'?intent.latest_charge:null,p_amount:intent.amount_received,p_currency:intent.currency.toUpperCase()});if(settleError)throw settleError;
  return response(200,{status:'paid',mode:'test'});
 }
 if(intent.status==='requires_action'||intent.last_payment_error?.code==='authentication_required')return authenticationResponse(svc,intent,method);
 if(intent.status==='processing')return response(200,{status:'processing'});
 if(resume)await svc.admin.from('commerce_payments').update({attempt:payment.attempt+1}).eq('order_id',order.id).eq('attempt',payment.attempt);
 return response(402,{error:intent.last_payment_error?.code==='authentication_required'?'PAYMENT_ACTION_REQUIRED':'CARD_DECLINED'});
}
export function authenticationResponse(svc:Services,intent:Stripe.PaymentIntent,method:string){
 if(!svc.config.STRIPE_PUBLISHABLE_KEY?.startsWith('pk_test_'))return response(503,{error:'PAYMENT_FORM_NOT_CONFIGURED'});
 return response(200,{status:'requires_action',clientSecret:intent.client_secret,publishableKey:svc.config.STRIPE_PUBLISHABLE_KEY,paymentMethod:method,confirmationRequired:intent.status==='requires_payment_method',returnUrl:appUrl(),action:'authenticate',mode:'test'});
}
