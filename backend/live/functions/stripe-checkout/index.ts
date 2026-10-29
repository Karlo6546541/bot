import { services, authenticate, response, failure, appUrl } from '../_shared/stripe.ts';
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return response(200, {});
  if (req.method !== 'POST') return response(405, { error: 'METHOD_NOT_ALLOWED' });
  try {
    const user = await authenticate(req);
    const { orderId } = await req.json();
    if (typeof orderId !== 'string') return response(400, { error: 'INVALID_ORDER' });
    const { stripe, admin } = services();
    const { data: order, error: orderError } = await admin.from('commerce_orders')
      .select('id,buyer_id,seller_id,total_cents,currency,status').eq('id', orderId).single();
    if (orderError || !order || order.buyer_id !== user.id) return response(404, { error: 'ORDER_NOT_FOUND' });
    if (order.status !== 'awaiting_payment') return response(409, { error: 'ORDER_NOT_PAYABLE' });
    const { data: shipping } = await admin.from('commerce_shipments').select('order_id').eq('order_id', order.id).maybeSingle();
    if (!shipping) return response(409, { error: 'SHIPPING_REQUIRED' });
    const { data: seller } = await admin.from('commerce_sellers').select('stripe_account_id')
      .eq('user_id', order.seller_id).single();
    if (!seller) return response(409, { error: 'SELLER_NOT_READY' });
    const account = await stripe.accounts.retrieve(seller.stripe_account_id);
    if (!account.charges_enabled || !account.payouts_enabled) return response(409, { error: 'SELLER_NOT_READY' });
    // Persist an order lock before contacting Stripe; cancellation cannot restock it.
    const { error: claimError } = await admin.from('commerce_checkout_sessions').upsert(
      { order_id: order.id }, { onConflict: 'order_id', ignoreDuplicates: true });
    if (claimError) throw claimError;
    const { data: lockedOrder } = await admin.from('commerce_orders').select('status').eq('id', order.id).single();
    if (lockedOrder?.status !== 'awaiting_payment') return response(409, { error: 'ORDER_NOT_PAYABLE' });
    const { data: previous, error: previousError } = await admin.from('commerce_checkout_sessions')
      .select('session_id').eq('order_id', order.id).maybeSingle();
    if (previousError) throw previousError;
    if (previous?.session_id) {
      const session = await stripe.checkout.sessions.retrieve(previous.session_id);
      if (session.status === 'open' && session.url) return response(200, { url: session.url, mode: 'test' });
      if (session.status === 'complete') return response(409, { error: 'PAYMENT_PROCESSING' });
    }
    const session = await stripe.checkout.sessions.create({ mode: 'payment',
      client_reference_id: order.id, customer_email: user.email,
      success_url: appUrl(), cancel_url: appUrl(),
      payment_method_types: ['card'], metadata: { order_id: order.id },
      line_items: [{ quantity: 1, price_data: { currency: order.currency.toLowerCase(),
        unit_amount: Number(order.total_cents), product_data: { name: 'Subhasto narudžba' } } }],
      payment_intent_data: { metadata: { order_id: order.id },
        transfer_data: { destination: seller.stripe_account_id } },
    }, { idempotencyKey: `checkout-${order.id}-${previous?.session_id ?? 'initial'}` });
    const { error } = await admin.from('commerce_checkout_sessions').upsert(
      { order_id: order.id, session_id: session.id }, { onConflict: 'order_id' });
    if (error) throw error;
    return response(200, { url: session.url, mode: 'test' });
  } catch (error) { return failure(error); }
});
