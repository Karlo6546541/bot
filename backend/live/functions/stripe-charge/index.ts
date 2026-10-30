import Stripe from 'npm:stripe@23.0.0';
import { services, authenticate, response, failure, customerFor, savedCard } from '../_shared/stripe.ts';
// Automatska naplata spremljene kartice (off-session) odmah nakon odabira
// dostave — bez checkouta. Novac ide prodavatelju preko Connecta.
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return response(200, {});
  if (req.method !== 'POST') return response(405, { error: 'METHOD_NOT_ALLOWED' });
  try {
    const user = await authenticate(req);
    const { orderId } = await req.json();
    if (typeof orderId !== 'string') return response(400, { error: 'INVALID_ORDER' });
    const { stripe, admin } = await services();
    const { data: order } = await admin.from('commerce_orders')
      .select('id,buyer_id,seller_id,total_cents,currency,status').eq('id', orderId).single();
    if (!order || order.buyer_id !== user.id) return response(404, { error: 'ORDER_NOT_FOUND' });
    if (order.status !== 'awaiting_payment') return response(409, { error: 'ORDER_NOT_PAYABLE' });
    const { data: shipping } = await admin.from('commerce_shipments').select('order_id').eq('order_id', order.id).maybeSingle();
    if (!shipping) return response(409, { error: 'SHIPPING_REQUIRED' });
    const { data: seller } = await admin.from('commerce_sellers').select('stripe_account_id')
      .eq('user_id', order.seller_id).single();
    if (!seller) return response(409, { error: 'SELLER_NOT_READY' });
    const account = await stripe.v2.core.accounts.retrieve(seller.stripe_account_id, { include: ['configuration.recipient'] });
    if (account.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status !== 'active') {
      return response(409, { error: 'SELLER_NOT_READY' });
    }
    const customerId = await customerFor(stripe, admin, user);
    const card = await savedCard(stripe, customerId);
    if (!card) return response(409, { error: 'CARD_REQUIRED' });
    try {
      const intent = await stripe.paymentIntents.create({
        amount: Number(order.total_cents), currency: order.currency.toLowerCase(),
        customer: customerId, payment_method: card.id, off_session: true, confirm: true,
        metadata: { order_id: order.id },
        transfer_data: { destination: seller.stripe_account_id },
      }, { idempotencyKey: `charge-${order.id}` });
      if (intent.status !== 'succeeded') return response(409, { error: 'PAYMENT_ACTION_REQUIRED' });
      // Isto što radi webhook: zabilježi uplatu (idempotentno po ID-ju događaja).
      const { error } = await admin.rpc('commerce_record_payment', {
        p_event: `pi_${intent.id}`, p_order: order.id,
        p_amount: intent.amount_received, p_currency: intent.currency.toUpperCase(),
      });
      if (error) throw error;
      return response(200, { status: 'paid', last4: card.last4 });
    } catch (error) {
      if (error instanceof Stripe.errors.StripeCardError) {
        console.error('card_declined', { code: error.code, requestId: error.requestId });
        return response(402, { error: error.code === 'authentication_required' ? 'PAYMENT_ACTION_REQUIRED' : 'CARD_DECLINED' });
      }
      throw error;
    }
  } catch (error) { return failure(error); }
});
