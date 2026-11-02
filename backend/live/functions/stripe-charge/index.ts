import { services, authenticate, response, failure, customerFor, savedCard } from '../_shared/stripe.ts';
import { chargeOrder } from '../_shared/charge.ts';
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return response(200,{});
 if(req.method!=='POST')return response(405,{error:'METHOD_NOT_ALLOWED'});
 try{
  const user=await authenticate(req);const body=await req.json();
  if(typeof body.orderId!=='string')return response(400,{error:'INVALID_ORDER'});
  const svc=await services();
  const {data:order,error}=await svc.admin.from('commerce_orders').select('*').eq('id',body.orderId).single();
  if(error||!order||order.buyer_id!==user.id)return response(404,{error:'ORDER_NOT_FOUND'});
  if(['paid','shipped','delivered'].includes(order.status))return response(200,{status:'paid'});
  if(order.status!=='awaiting_payment')return response(409,{error:'ORDER_NOT_PAYABLE'});
  const {data:shipping}=await svc.admin.from('commerce_shipments').select('order_id').eq('order_id',order.id).maybeSingle();
  if(!shipping)return response(409,{error:'SHIPPING_REQUIRED'});
  const {data:seller}=await svc.admin.from('commerce_sellers').select('stripe_account_id').eq('user_id',order.seller_id).maybeSingle();
  if(!seller)return response(409,{error:'SELLER_NOT_READY'});
  const account=await svc.stripe.v2.core.accounts.retrieve(seller.stripe_account_id,{include:['configuration.recipient']});
  if(account.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status!=='active')return response(409,{error:'SELLER_NOT_READY'});
  const customer=await customerFor(svc.stripe,svc.admin,user);
  const {data:profile}=await svc.admin.from('commerce_customers').select('consent_at').eq('user_id',user.id).single();
  const card=profile?.consent_at?await savedCard(svc.stripe,customer):null;
  if(!card)return response(409,{error:'CARD_REQUIRED'});
  return await chargeOrder(svc,order,customer,card.id,body.action==='resume');
 }catch(error){return failure(error);}
});

