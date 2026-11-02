import assert from 'node:assert/strict';
import { resolveConfig } from '../functions/_shared/config_values.ts';

const environment: Record<string, string> = {
  STRIPE_RESTRICTED_KEY: 'environment-restricted',
  STRIPE_SECRET_KEY: 'environment-secret',
  STRIPE_PUBLISHABLE_KEY: 'environment-public',
  LIVEKIT_API_SECRET: 'environment-streaming',
};
const env = (name: string) => environment[name];

Deno.test('Vault Stripe secret suppresses stale environment restricted key', () => {
  const config = resolveConfig(env, { STRIPE_SECRET_KEY: 'vault-secret' });
  assert.equal(config.STRIPE_SECRET_KEY, 'vault-secret');
  assert.equal(config.STRIPE_RESTRICTED_KEY, undefined);
});
Deno.test('Vault restricted key remains preferred when the pair is configured there', () => {
  const config = resolveConfig(env, { STRIPE_SECRET_KEY: 'vault-secret', STRIPE_RESTRICTED_KEY: 'vault-restricted' });
  assert.equal(config.STRIPE_RESTRICTED_KEY, 'vault-restricted');
  assert.equal(config.STRIPE_SECRET_KEY, 'vault-secret');
});
Deno.test('environment fallback and streaming settings are preserved', () => {
  const config = resolveConfig(env, { STRIPE_SECRET_KEY: '', LIVEKIT_API_SECRET: 'vault-streaming' });
  assert.equal(config.STRIPE_RESTRICTED_KEY, 'environment-restricted');
  assert.equal(config.LIVEKIT_API_SECRET, 'environment-streaming');
});
Deno.test('the public Stripe key can be updated in Vault', () => {
  assert.equal(resolveConfig(env, { STRIPE_PUBLISHABLE_KEY: 'vault-public' }).STRIPE_PUBLISHABLE_KEY, 'vault-public');
});
