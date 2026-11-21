import { integrationConfig, adminClient } from './config.ts';
import Stripe from 'npm:stripe@23.0.0';
import { createClient } from 'npm:@supabase/supabase-js@2.49.8';
export async function services() {
  const config = await integrationConfig();
  const secret = config.STRIPE_RESTRICTED_KEY ?? config.STRIPE_SECRET_KEY;
  if (!secret || !/^(rk|sk)_test_/.test(secret)) throw new Error('TEST_MODE_REQUIRED');
  const stripe = new Stripe(secret, { httpClient: Stripe.createFetchHttpClient() });
  const platform = await stripe.accounts.retrieve(null);
  if (platform.id !== 'acct_1UVqd9PdLAWyn74E') throw new Error('WRONG_TEST_PLATFORM');
  return {
    stripe,
    admin: adminClient(), config,
  };
}
export const origin = () => Deno.env.get('APP_ORIGIN') ?? 'https://karlo6546541.github.io';
export function response(status: number, body: unknown) {
  return new Response(JSON.stringify(body), { status, headers: {
    'Content-Type': 'application/json', 'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': origin(), 'Vary': 'Origin',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  } });
}
export async function authenticate(req: Request) {
  const auth = req.headers.get('Authorization');
  if (!auth?.startsWith('Bearer ')) throw new Error('AUTH_REQUIRED');
  const client = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: auth } }, auth: { persistSession: false } });
  const { data: { user }, error } = await client.auth.getUser(auth.slice(7));
  if (error || !user) throw new Error('AUTH_REQUIRED');
  return user;
}
export function appUrl() {
  const url = new URL(Deno.env.get('APP_URL') ?? 'https://karlo6546541.github.io/bot/');
  if (url.origin !== origin() || url.protocol !== 'https:') throw new Error('INVALID_APP_URL');
  url.searchParams.set('cloud', 'orders');
  return url.toString();
}
export function failure(error: unknown) {
  if (error instanceof Stripe.errors.StripeError) {
    console.error('stripe_request_failed', { type: error.type, code: error.code, status: error.statusCode,
      param: (error as { param?: string }).param, message: error.message, requestId: error.requestId });
  } else if (error instanceof Error && error.message !== 'AUTH_REQUIRED') {
    // Reason for a 503 (configuration, database, ...). Messages hold no secrets.
    console.error('payments_unavailable', { name: error.name, message: error.message });
  } else if (!(error instanceof Error)) {
    console.error('payments_unavailable', { detail: JSON.stringify(error)?.slice(0, 300) });
  }

  if (error instanceof Stripe.errors.StripeError &&
      error.code === 'non_connect_platform_accounts_v2_access_blocked') {
    return response(409, { error: 'CONNECT_PLATFORM_REQUIRED' });
  }

  return response(error instanceof Error && error.message === 'AUTH_REQUIRED' ? 401 : 503,
    { error: error instanceof Error && error.message === 'AUTH_REQUIRED' ? 'AUTH_REQUIRED' : 'PAYMENTS_UNAVAILABLE' });
}

/** Stripe kupac po korisniku (ID u app_metadata, bez nove tablice). */
export async function customerFor(stripe: Stripe,
  admin: ReturnType<typeof adminClient>,
  user: { id: string; email?: string | null; app_metadata?: Record<string, unknown> }) {
  const existing = user.app_metadata?.stripe_customer_id as string | undefined;
  const { data: profile, error: readError } = await admin.from('commerce_customers').select('customer_id').eq('user_id', user.id).maybeSingle();
  if (readError) throw readError;
  if (profile) return profile.customer_id as string;
  if (existing) {
    const customer = await stripe.customers.retrieve(existing);
    if (!customer.deleted && !customer.livemode && customer.metadata.user_id === user.id) {
      const { error } = await admin.from('commerce_customers').upsert({user_id:user.id,customer_id:existing},{onConflict:'user_id'});
      if (error) throw error;
      return existing;
    }
  }
  const customer = await stripe.customers.create(
    { email: user.email ?? undefined, metadata: { user_id: user.id } },
    { idempotencyKey: `customer-${user.id}` });
  const { error } = await admin.from('commerce_customers').upsert({user_id:user.id,customer_id:customer.id},{onConflict:'user_id'});
  if (error) throw error;
  return customer.id;
}

/** Zadnja spremljena kartica kupca (ili null). */
export async function savedCard(stripe: Stripe, customerId: string) {
  const list = await stripe.customers.listPaymentMethods(customerId, { type: 'card', limit: 1 });
  const card = list.data[0];
  return card ? { id: card.id, brand: card.card?.brand ?? 'card', last4: card.card?.last4 ?? '' } : null;
}

