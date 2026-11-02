export const configNames = ['STRIPE_RESTRICTED_KEY', 'STRIPE_SECRET_KEY', 'STRIPE_PUBLISHABLE_KEY', 'STRIPE_WEBHOOK_SECRET', 'STRIPE_RELEASE_JOB_SECRET',
  'LIVEKIT_URL', 'LIVEKIT_API_KEY', 'LIVEKIT_API_SECRET'] as const;
export type Config = Partial<Record<typeof configNames[number], string>>;

/** A Vault Stripe credential replaces the environment credential pair together.
 * Otherwise an old environment RAK could shadow a newly configured Vault key.
 */
export function resolveConfig(env: (name: string) => string | undefined, vault: Record<string, unknown>): Config {
  const stored = (name: string) => typeof vault[name] === 'string' && vault[name] ? vault[name] as string : undefined;
  const vaultStripe = !!(stored('STRIPE_RESTRICTED_KEY') || stored('STRIPE_SECRET_KEY'));
  const value: Config = {};
  for (const name of configNames) {
    const credential = name === 'STRIPE_RESTRICTED_KEY' || name === 'STRIPE_SECRET_KEY';
    const secret = credential && vaultStripe ? stored(name)
      : name === 'STRIPE_PUBLISHABLE_KEY' ? stored(name) || env(name)
      : env(name) || stored(name);
    if (secret) value[name] = secret;
  }
  return value;
}
