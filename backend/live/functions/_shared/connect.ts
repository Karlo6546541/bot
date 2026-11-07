import Stripe from 'npm:stripe@23.0.0';

/** The shared Stripe test mode rejects v2 links when Express also requests payouts.
 * Keep v2 account creation and retrieval; use the compatible hosted link only for
 * this documented provider rejection, preserving the same account and return URL.
 */
export async function createOnboardingLink(stripe: Stripe, account: string, url: string) {
  try {
    return await stripe.v2.core.accountLinks.create({
      account,
      use_case: {
        type: 'account_onboarding',
        account_onboarding: {
          return_url: url, refresh_url: url,
          collection_options: { fields: 'eventually_due' },
        },
      },
    });
  } catch (error) {
    if (!(error instanceof Stripe.errors.StripeInvalidRequestError) ||
        error.code !== 'invalid_fields' ||
        !error.message.includes('recipient config capabilities other than stripe_balance.stripe_transfers requested in testmode')) {
      throw error;
    }
    return await stripe.accountLinks.create({
      account, type: 'account_onboarding',
      return_url: url, refresh_url: url,
      collection_options: { fields: 'eventually_due' },
    });
  }
}
