import { createClient } from 'npm:@supabase/supabase-js@2.49.8';
const names = ['STRIPE_RESTRICTED_KEY', 'STRIPE_SECRET_KEY', 'STRIPE_WEBHOOK_SECRET',
  'LIVEKIT_URL', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET'] as const;
type Config = Partial<Record<typeof names[number], string>>;
let cached: { until: number; value: Config } | undefined;
export function adminClient() {
  return createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } });
}
export async function integrationConfig(): Promise<Config> {
  if (cached && cached.until > Date.now()) return cached.value;
  const { data, error } = await adminClient().rpc('subhasto_integration_secrets');
  if (error) throw new Error('CONFIG_UNAVAILABLE');
  const value: Config = {};
  for (const name of names) {
    const secret = Deno.env.get(name) || data?.[name];
    if (typeof secret === 'string' && secret) value[name] = secret;
  }
  cached = { until: Date.now() + 30000, value };
  return value;
}
