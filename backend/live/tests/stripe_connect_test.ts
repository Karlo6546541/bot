import assert from 'node:assert/strict';
import Stripe from 'npm:stripe@23.0.0';
import { createOnboardingLink } from '../functions/_shared/connect.ts';

const url = 'https://example.test/?cloud=orders';
function client(createV2: (params: unknown) => Promise<unknown>, createV1: (params: unknown) => Promise<unknown>) {
  return {v2:{core:{accountLinks:{create:createV2}}},accountLinks:{create:createV1}} as unknown as Stripe;
}
function providerError(message: string, code = 'invalid_fields') {
  return new Stripe.errors.StripeInvalidRequestError({type:'invalid_request_error',code,message});
}
Deno.test('v2 onboarding remains primary and never invokes the compatibility path on success',async()=>{
  let fallback = false;
  const stripe = client(async(params)=>{
    const p=params as {account:string;use_case:{account_onboarding:{return_url:string}}};
    assert.equal(p.account,'acct_existing');
    assert.equal(p.use_case.account_onboarding.return_url,url);
    return {url:'https://connect.stripe.com/v2-link'};
  },async()=>{fallback=true;throw Error('unexpected');});
  assert.equal((await createOnboardingLink(stripe,'acct_existing',url)).url,'https://connect.stripe.com/v2-link');
  assert.equal(fallback,false);
});
Deno.test('shared test mode recipient restriction uses the same account and trusted return URL',async()=>{
  let calls=0;
  const stripe=client(async()=>{throw providerError('Cannot create a v2 account link with recipient config capabilities other than stripe_balance.stripe_transfers requested in testmode. Please switch to a sandbox.');},async(params)=>{
    calls++;
    assert.deepEqual(params,{account:'acct_existing',type:'account_onboarding',return_url:url,refresh_url:url,collection_options:{fields:'eventually_due'}});
    return {url:'https://connect.stripe.com/compatible-link'};
  });
  assert.equal((await createOnboardingLink(stripe,'acct_existing',url)).url,'https://connect.stripe.com/compatible-link');
  assert.equal(calls,1);
});
Deno.test('unrelated invalid fields, permissions, network and live errors do not fall back',async()=>{
  for(const error of [providerError('Invalid account'),providerError('Invalid recipient in livemode'),new Error('network'),new Stripe.errors.StripePermissionError({type:'invalid_request_error',message:'Not permitted'})]){
    let fallback=false;
    const stripe=client(async()=>{throw error;},async()=>{fallback=true;return {url:'unsafe'};});
    await assert.rejects(()=>createOnboardingLink(stripe,'acct_existing',url),e=>e===error);
    assert.equal(fallback,false);
  }
});
Deno.test('failure from the compatibility endpoint propagates and cannot report success',async()=>{
  const fallbackError=new Error('provider unavailable');
  const stripe=client(async()=>{throw providerError('recipient config capabilities other than stripe_balance.stripe_transfers requested in testmode');},async()=>{throw fallbackError;});
  await assert.rejects(()=>createOnboardingLink(stripe,'acct_existing',url),e=>e===fallbackError);
});
