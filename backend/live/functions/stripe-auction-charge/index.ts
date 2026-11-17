import { services, savedCard } from '../_shared/stripe.ts';
import { integrationConfig } from '../_shared/config.ts';
import { chargeOrder } from '../_shared/charge.ts';
// Scheduler-only (cron svake minute): pobjedniku završene aukcije jednom
// automatski naplati narudžbu (najviša ponuda + dostava) sa spremljene kartice.
// Ako naplata ne prođe (nedovoljno sredstava, banka traži potvrdu), narudžba
// ostaje "awaiting_payment": kupac dobiva obavijest i plaća iz aplikacije u
// roku od 24 h, nakon čega je commerce_expire_orders poništava.
Deno.serve(async (req: Request) => {
 if (req.method !== 'POST') return new Response(null, { status: 405 });
 const config = await integrationConfig();
 if (!config.STRIPE_RELEASE_JOB_SECRET || req.headers.get('x-subhasto-job') !== config.STRIPE_RELEASE_JOB_SECRET) return new Response(null, { status: 401 });
 let svc;
 try { svc = await services(); } catch { return new Response('Stripe configuration unavailable', { status: 503 }); }
 const { data: orders, error } = await svc.admin.from('commerce_orders')
  .select('id,buyer_id,seller_id,total_cents,currency').eq('status', 'awaiting_payment')
  .not('source_auction', 'is', null).order('created_at').limit(20);
 if (error) return new Response('Retry later', { status: 503 });
 let charged = 0, due = 0, waiting = 0;
 for (const order of orders ?? []) {
  try {
   // Samo jedan automatski pokušaj: nakon nastanka PaymentIntenta plaća kupac ručno.
   const { data: payment } = await svc.admin.from('commerce_payments').select('intent_id').eq('order_id', order.id).maybeSingle();
   if (payment?.intent_id) { waiting++; continue; }
   const { data: profile } = await svc.admin.from('commerce_customers').select('customer_id,consent_at').eq('user_id', order.buyer_id).maybeSingle();
   const card = profile?.consent_at ? await savedCard(svc.stripe, profile.customer_id) : null;
   if (!card) { await svc.admin.rpc('auction_payment_due', { p_order: order.id }); due++; continue; }
   const res = await chargeOrder(svc, order, profile!.customer_id, card.id, false);
   const body = await res.json().catch(() => ({}));
   if (res.status === 200 && body.status === 'paid') { charged++; continue; }
   if (body.status === 'processing') { waiting++; continue; }
   await svc.admin.rpc('auction_payment_due', { p_order: order.id }); due++;
  } catch (e) { waiting++; console.error('auction_charge_failed', { type: e instanceof Error ? e.name : 'unknown', message: e instanceof Error ? e.message.slice(0, 200) : '' }); }
 }
 return Response.json({ mode: 'test', charged, due, waiting });
});
