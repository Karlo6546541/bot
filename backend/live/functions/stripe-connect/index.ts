import { services, authenticate, response, failure, appUrl } from '../_shared/stripe.ts';
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return response(200, {});
  if (req.method !== 'POST') return response(405, { error: 'METHOD_NOT_ALLOWED' });
  try {
    const user = await authenticate(req);
    const { stripe, admin } = services();
    const { data: existing, error: readError } = await admin.from('commerce_sellers')
      .select('stripe_account_id').eq('user_id', user.id).maybeSingle();
    if (readError) throw readError;
    let accountId = existing?.stripe_account_id;
    if (!accountId) {
      const account = await stripe.accounts.create({ type: 'express', email: user.email,
        capabilities: { card_payments: { requested: true }, transfers: { requested: true } },
        metadata: { user_id: user.id } }, { idempotencyKey: `seller-${user.id}` });
      accountId = account.id;
      const { error } = await admin.from('commerce_sellers').upsert(
        { user_id: user.id, stripe_account_id: accountId }, { onConflict: 'user_id' });
      if (error) throw error;
    }
    const account = await stripe.accounts.retrieve(accountId);
    const ready = account.charges_enabled && account.payouts_enabled;
    // The browser supplies no return URLs or account IDs.
    const link = await stripe.accountLinks.create({ account: accountId, type: 'account_onboarding',
      return_url: appUrl(), refresh_url: appUrl() });
    return response(200, { url: link.url, ready, mode: 'test' });
  } catch (error) { return failure(error); }
});
