import Stripe from 'npm:stripe@23.0.0';
import { services } from '../_shared/stripe.ts';
Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });
  const signature = req.headers.get('stripe-signature');
  if (!signature) return new Response('Missing signature', { status: 400 });
  let event: Stripe.Event;
  let svc;
  try {
    svc = await services();
    event = await svc.stripe.webhooks.constructEventAsync(await req.text(), signature,
      svc.config.STRIPE_WEBHOOK_SECRET!, undefined, Stripe.createSubtleCryptoProvider());
  } catch { return new Response('Invalid webhook or configuration', { status: 400 }); }
  if (event.livemode) return new Response('Test mode only', { status: 400 });
  if (['charge.refunded','charge.dispute.created'].includes(event.type)) {
    const object=event.data.object as unknown as {id:string;charge?:string;payment_intent?:string;amount_refunded?:number};
    const charge=event.type==='charge.refunded'
      ? object as unknown as Stripe.Charge : await svc.stripe.charges.retrieve(object.charge!);
    const intent=typeof charge.payment_intent==='string'?charge.payment_intent:null;
    if(!intent)return new Response('Ignored');
    const {error}=await svc.admin.rpc('commerce_record_refund',{p_intent:intent,p_refunded:charge.amount_refunded,p_disputed:charge.disputed});
    if(error)return new Response('Retry later',{status:503});
    const {data:p}=await svc.admin.from('commerce_payments').select('transfer_id').eq('intent_id',intent).maybeSingle();
    if(p?.transfer_id){
      try{
        const t=await svc.stripe.transfers.retrieve(p.transfer_id);
        if(t.amount>t.amount_reversed)await svc.stripe.transfers.createReversal(t.id,{amount:t.amount-t.amount_reversed},{idempotencyKey:`risk-reversal-${t.id}`});
      }catch{return new Response('Retry later',{status:503});}
    }
    const {data:promo}=await svc.admin.from('commerce_promotions').select('id,amount_cents').eq('intent_id',intent).maybeSingle();
    if(promo&&(charge.disputed||charge.amount_refunded>0)){
      const {error:e}=await svc.admin.rpc('commerce_refund_promotion',{p_id:promo.id,p_amount:charge.disputed?charge.amount:charge.amount_refunded});
      if(e)return new Response('Retry later',{status:503});
    }
    return new Response('OK');
  }
  // Saved-card payments are fulfilled only after verified Stripe success.
  if (event.type === 'payment_intent.succeeded') {
    const intent = event.data.object as Stripe.PaymentIntent;
    if(intent.metadata?.promotion_id){
      const {error}=await svc.admin.rpc('commerce_settle_promotion',{p_id:intent.metadata.promotion_id,p_intent:intent.id,p_amount:intent.amount_received});
      return new Response(error?'Retry later':'OK',{status:error?503:200});
    }
    if (!intent.metadata?.order_id) return new Response('Ignored', { status: 200 });
    const {data:payment}=await svc.admin.from('commerce_payments').select('intent_id').eq('order_id',intent.metadata.order_id).maybeSingle();
    if(payment){
      const {error}=await svc.admin.rpc('commerce_settle_intent',{p_event:event.id,p_order:intent.metadata.order_id,p_intent:intent.id,p_charge:typeof intent.latest_charge==='string'?intent.latest_charge:null,p_amount:intent.amount_received,p_currency:intent.currency.toUpperCase()});
      return new Response(error?'Retry later':'OK',{status:error?503:200});
    }
    const { error } = await svc.admin.rpc('commerce_record_payment', {
      p_event: event.id, p_order: intent.metadata.order_id,
      p_amount: intent.amount_received, p_currency: intent.currency.toUpperCase(),
    });
    return new Response(error ? 'Retry later' : 'OK', { status: error ? 503 : 200 });
  }
  if (!['checkout.session.completed', 'checkout.session.async_payment_succeeded', 'checkout.session.async_payment_failed'].includes(event.type)) return new Response('Ignored', { status: 200 });
  const session = event.data.object as Stripe.Checkout.Session;
  if (!session.metadata?.order_id || !session.currency || session.amount_total === null) {
    return new Response('Ignored', { status: 200 });
  }
  // Confirm this session was created for this order by our checkout endpoint.
  const { data: saved, error: savedError } = await svc.admin.from('commerce_checkout_sessions').select('session_id')
    .eq('order_id', session.metadata.order_id).maybeSingle();
  if (savedError || !saved || saved.session_id !== session.id) return new Response('Session not yet recorded', { status: 503 });
  if (event.type === 'checkout.session.async_payment_failed') {
    const { error } = await svc.admin.rpc('commerce_record_failure', {
      p_event: event.id, p_order: session.metadata.order_id, p_session: session.id,
    });
    return new Response(error ? 'Retry later' : 'OK', { status: error ? 503 : 200 });
  }
  if (session.payment_status !== 'paid') return new Response('Ignored', { status: 200 });
  const { error } = await svc.admin.rpc('commerce_record_payment', {
    p_event: event.id, p_order: session.metadata.order_id,
    p_amount: session.amount_total, p_currency: session.currency.toUpperCase(),
  });
  return new Response(error ? 'Retry later' : 'OK', { status: error ? 503 : 200 });
});

