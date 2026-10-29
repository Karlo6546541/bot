import { integrationConfig, adminClient } from './config.ts';
import Stripe from 'npm:stripe@23.0.0';
import { createClient } from 'npm:@supabase/supabase-js@2.49.8';
export async function services() {
  const config = await integrationConfig();
  const secret = config.STRIPE_RESTRICTED_KEY ?? config.STRIPE_SECRET_KEY;
  if (!secret || !/^(rk|sk)_test_/.test(secret)) throw new Error('TEST_MODE_REQUIRED');
  return {
    stripe: new Stripe(secret, { httpClient: Stripe.createFetchHttpClient() }),
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
    console.error('stripe_request_failed', { type: error.type, code: error.code, requestId: error.requestId });
  }

  return response(error instanceof Error && error.message === 'AUTH_REQUIRED' ? 401 : 503,
    { error: error instanceof Error && error.message === 'AUTH_REQUIRED' ? 'AUTH_REQUIRED' : 'PAYMENTS_UNAVAILABLE' });
}
