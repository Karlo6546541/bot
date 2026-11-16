import { services, authenticate, response, failure, appUrl } from '../_shared/stripe.ts';
import { prepareSeller } from '../_shared/seller_onboarding.ts';
// Račun prodavača. Potvrda identiteta i IBAN-a ide ugrađenom Stripe komponentom
// unutar aplikacije (Account Session) — nikad preusmjeravanjem na Stripe.
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return response(200, {});
  if (req.method !== 'POST') return response(405, { error: 'METHOD_NOT_ALLOWED' });
  try {
    const user = await authenticate(req);
    const body = await req.json();
    if(body.expectedUserId!==undefined&&body.expectedUserId!==user.id)return response(401,{error:'AUTH_REQUIRED'});
    if(body.action!==undefined && !['ensure','prepare','session'].includes(body.action))return response(400,{error:'INVALID_ACTION'});
    if(body.seller!==undefined && (!body.seller || typeof body.seller!=='object' || Array.isArray(body.seller)))return response(400,{error:'INVALID_PROFILE'});
    const { stripe, admin, config } = await services();
    const result=await prepareSeller(stripe,admin,user,appUrl(),body.seller,typeof body.country==='string'?body.country:undefined);
    await admin.from('commerce_sellers').update({transfers_active:result.ready,checked_at:new Date().toISOString()}).eq('user_id',user.id);
    // Isplate na IBAN pokreće samo poslužitelj nakon dostave: raspored je ručni.
    try{
      await stripe.balanceSettings.update({payments:{payouts:{schedule:{interval:'manual'}}}},{stripeAccount:result.accountId});
    }catch(error){console.error('payout_schedule_failed',{type:error instanceof Error?error.name:'unknown',message:error instanceof Error?error.message.slice(0,200):''});}
    if(body.action==='prepare' || result.ready)return response(200,{ready:result.ready,mode:'test'});
    // Kratkotrajna sesija samo za račun prijavljenog korisnika.
    const key=config.STRIPE_PUBLISHABLE_KEY;
    if(!key?.startsWith('pk_test_'))return response(503,{error:'PAYMENT_FORM_NOT_CONFIGURED'});
    const session=await stripe.accountSessions.create({account:result.accountId,components:{account_onboarding:{enabled:true}}});
    return response(200,{ready:false,clientSecret:session.client_secret,publishableKey:key,mode:'test'});
  } catch (error) { return failure(error); }
});
