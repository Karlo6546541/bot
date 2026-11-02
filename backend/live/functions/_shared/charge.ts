import Stripe from 'npm:stripe@23.0.0';
import { services,response } from './stripe.ts';
type Services=Awaited<ReturnType<typeof services>>;
// Persist one intent per order before confirmation. Funds remain on the platform.
export async function chargeOrder(svc:Services,order:{id:string;total_cents:number;currency:string},customer:string,method:string,resume:boolean){
 const {data:payment,error}=await svc.admin.rpc('commerce_begin_charge',{p_order:order.id});if(error)throw error;
 let intent:Stripe.PaymentIntent;
 if(payment.intent_id){intent=await svc.stripe.paymentIntents.retrieve(payment.intent_id);}
 else{
  intent=await svc.stripe.paymentIntents.create({amount:Number(order.total_cents),currency:order.currency.toLowerCase(),customer,payment_method:method,metadata:{order_id:order.id,purpose:'marketplace'},transfer_group:`order_${order.id}`},{idempotencyKey:`order-intent-v2-${order.id}`});
  const {error:saveError}=await svc.admin.from('commerce_payments').update({intent_id:intent.id}).eq('order_id',order.id);if(saveError)throw saveError;
 }
 if(intent.status==='requires_payment_method')intent=await svc.stripe.paymentIntents.update(intent.id,{payment_method:method});
 if(intent.status==='requires_confirmation'||intent.status==='requires_payment_method'){
  try{intent=await svc.stripe.paymentIntents.confirm(intent.id,{off_session:true},{idempotencyKey:`order-confirm-${order.id}-${intent.payment_method}-${payment.attempt}`});}
  catch(error){if(error instanceof Stripe.errors.StripeCardError)intent=await svc.stripe.paymentIntents.retrieve(intent.id);else throw error;}
 }
 if(intent.status==='succeeded'){
  const {error:settleError}=await svc.admin.rpc('commerce_settle_intent',{p_event:`intent:${intent.id}`,p_order:order.id,p_intent:intent.id,p_charge:typeof intent.latest_charge==='string'?intent.latest_charge:null,p_amount:intent.amount_received,p_currency:intent.currency.toUpperCase()});if(settleError)throw settleError;
  return response(200,{status:'paid',mode:'test'});
 }
 if(intent.status==='requires_action'&&svc.config.STRIPE_PUBLISHABLE_KEY?.startsWith('pk_test_'))return response(200,{status:'requires_action',clientSecret:intent.client_secret,publishableKey:svc.config.STRIPE_PUBLISHABLE_KEY,action:'authenticate',mode:'test'});
 if(intent.status==='processing')return response(200,{status:'processing'});
 if(resume)await svc.admin.from('commerce_payments').update({attempt:payment.attempt+1}).eq('order_id',order.id).eq('attempt',payment.attempt);
 return response(402,{error:intent.last_payment_error?.code==='authentication_required'?'PAYMENT_ACTION_REQUIRED':'CARD_DECLINED'});
}
