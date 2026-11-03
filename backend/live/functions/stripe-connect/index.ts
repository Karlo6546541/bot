import { services, authenticate, response, failure, appUrl } from '../_shared/stripe.ts';
import { createOnboardingLink } from '../_shared/connect.ts';
import { prepareSeller } from '../_shared/seller_onboarding.ts';
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return response(200, {});
  if (req.method !== 'POST') return response(405, { error: 'METHOD_NOT_ALLOWED' });
  try {
    const user = await authenticate(req);
    const body = await req.json();
    if(body.action!==undefined && !['ensure','prepare'].includes(body.action))return response(400,{error:'INVALID_ACTION'});
    if(body.seller!==undefined && (!body.seller || typeof body.seller!=='object' || Array.isArray(body.seller)))return response(400,{error:'INVALID_PROFILE'});
    const { stripe, admin } = await services();
    const result=await prepareSeller(stripe,admin,user,appUrl(),body.seller,typeof body.country==='string'?body.country:undefined);
    if(body.action==='prepare' || (body.action==='ensure' && result.ready))return response(200,{ready:result.ready,mode:'test'});
    // Account IDs, credentials and redirect URLs always come from the server.
    const link = await createOnboardingLink(stripe, result.accountId, appUrl());
    return response(200, { url: link.url, ready: result.ready, mode: 'test' });
  } catch (error) { return failure(error); }
});

