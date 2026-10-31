import assert from 'node:assert/strict';
import Stripe from 'npm:stripe@23.0.0';
import { failure } from '../functions/_shared/stripe.ts';

Deno.test('Connect activation failure is actionable without leaking Stripe details', async () => {
  const error = new Stripe.errors.StripeInvalidRequestError({
    type: 'invalid_request_error',
    code: 'non_connect_platform_accounts_v2_access_blocked',
    message: 'Internal provider details',
  });
  const result = failure(error);
  assert.equal(result.status, 409);
  assert.deepEqual(await result.json(), { error: 'CONNECT_PLATFORM_REQUIRED' });
});

Deno.test('Unknown failures stay private and auth failures remain distinct', async () => {
  const result = failure(new Error('sensitive internal data'));
  assert.equal(result.status, 503);
  assert.deepEqual(await result.json(), { error: 'PAYMENTS_UNAVAILABLE' });
  const auth = failure(new Error('AUTH_REQUIRED'));
  assert.equal(auth.status, 401);
  assert.deepEqual(await auth.json(), { error: 'AUTH_REQUIRED' });
});
