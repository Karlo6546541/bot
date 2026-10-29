import Stripe from 'npm:stripe@17.7.0';
import { createClient } from 'npm:@supabase/supabase-js@2.49.8';
export function services() {
  const secret = Deno.env.get('STRIPE_SECRET_KEY');
  if (!secret?.startsWith('sk_test_')) throw new Error('TEST_MODE_REQUIRED');
  return {
    stripe: new Stripe(secret, { httpClient: Stripe.createFetchHttpClient() }),
    admin: createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } }),
  };
}
export const origin = () => Deno.env.get('APP_ORIGIN') ?? '';
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
  const { data: { user }, error } = await client.auth.getUser();
  if (error || !user) throw new Error('AUTH_REQUIRED');
  return user;
}
export function appUrl() {
  const url = new URL(Deno.env.get('APP_URL')!);
  if (url.origin !== origin() || url.protocol !== 'https:') throw new Error('INVALID_APP_URL');
  url.searchParams.set('cloud', 'orders');
  return url.toString();
}
export function failure(error: unknown) {
  return response(error instanceof Error && error.message === 'AUTH_REQUIRED' ? 401 : 503,
    { error: error instanceof Error && error.message === 'AUTH_REQUIRED' ? 'AUTH_REQUIRED' : 'PAYMENTS_UNAVAILABLE' });
}
