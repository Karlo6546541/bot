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
  // Automatska naplata spremljene kartice: PaymentIntent bez Checkout sesije.
  if (event.type === 'payment_intent.succeeded') {
    const intent = event.data.object as Stripe.PaymentIntent;
    if (!intent.metadata?.order_id) return new Response('Ignored', { status: 200 });
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
