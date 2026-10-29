import { integrationConfig } from '../_shared/config.ts';
Deno.serve(async (req: Request) => {
  const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': Deno.env.get('APP_ORIGIN') ?? 'https://karlo6546541.github.io',
    'Access-Control-Allow-Methods': 'GET, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info' };
  if (req.method === 'OPTIONS') return new Response(null, { headers });
  if (req.method !== 'GET') return new Response(null, { status: 405, headers });
  let config;
  try { config = await integrationConfig(); } catch { return new Response(JSON.stringify({ configured: false }), { status: 503, headers }); }
  const key = config.STRIPE_RESTRICTED_KEY ?? config.STRIPE_SECRET_KEY ?? '';
  // Configuration indicators only. Never return environment values or credentials.
  return new Response(JSON.stringify({
    paymentsConfigured: /^(rk|sk)_test_/.test(key),
    webhookConfigured: !!config.STRIPE_WEBHOOK_SECRET,
    streamingConfigured: !!config.LIVEKIT_URL && !!config.LIVEKIT_API_KEY && !!config.LIVEKIT_API_SECRET,
  }), { headers });
});
