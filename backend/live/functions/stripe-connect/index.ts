import { services, authenticate, response, failure, appUrl } from '../_shared/stripe.ts';
import { createOnboardingLink } from '../_shared/connect.ts';
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return response(200, {});
  if (req.method !== 'POST') return response(405, { error: 'METHOD_NOT_ALLOWED' });
  try {
    const user = await authenticate(req);
    const { stripe, admin } = await services();
    const { data: existing, error: readError } = await admin.from('commerce_sellers')
      .select('stripe_account_id').eq('user_id', user.id).maybeSingle();
    if (readError) throw readError;
    let accountId = existing?.stripe_account_id;
    if (!accountId) {
      const account = await stripe.v2.core.accounts.create({
        contact_email: user.email,
        dashboard: 'express',
        defaults: { responsibilities: { fees_collector: 'application', losses_collector: 'application' } },
        identity: { country: Deno.env.get('CONNECT_DEFAULT_COUNTRY') ?? 'hr' },
        configuration: { recipient: { capabilities: { stripe_balance: { stripe_transfers: { requested: true } } } } },
        metadata: { user_id: user.id },
      }, { idempotencyKey: `seller-v2-${user.id}` });
      accountId = account.id;
      const { error } = await admin.from('commerce_sellers').upsert(
        { user_id: user.id, stripe_account_id: accountId }, { onConflict: 'user_id' });
      if (error) throw error;
    }
    const account = await stripe.v2.core.accounts.retrieve(accountId, { include: ['configuration.recipient'] });
    const ready = account.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status === 'active';
    // The browser supplies no return URLs or account IDs.
    const link = await createOnboardingLink(stripe, accountId, appUrl());
    return response(200, { url: link.url, ready, mode: 'test' });
  } catch (error) { return failure(error); }
});
