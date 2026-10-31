import { services, authenticate, response, failure, appUrl, customerFor, savedCard } from '../_shared/stripe.ts';
// Kartica se sprema jednom (prije prve ponude), kao na Whatnotu.
//   { action: 'status' } -> { hasCard, brand, last4 }
//   {}                   -> { url } Stripe Checkout (mode=setup) za dodavanje kartice
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return response(200, {});
  if (req.method !== 'POST') return response(405, { error: 'METHOD_NOT_ALLOWED' });
  try {
    const user = await authenticate(req);
    const { stripe, admin } = await services();
    const body = await req.json().catch(() => ({}));
    const customerId = await customerFor(stripe, admin, user);
    if (body?.action === 'status') {
      const card = await savedCard(stripe, customerId);
      return response(200, { hasCard: !!card, brand: card?.brand ?? null, last4: card?.last4 ?? null });
    }
    const session = await stripe.checkout.sessions.create({
      mode: 'setup', customer: customerId, currency: 'eur',
      success_url: appUrl(), cancel_url: appUrl(),
      metadata: { user_id: user.id, purpose: 'save_card' },
    });
    return response(200, { url: session.url, mode: 'test' });
  } catch (error) { return failure(error); }
});
