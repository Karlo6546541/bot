import { services, authenticate, response, failure, appUrl, customerFor, savedCard } from '../_shared/stripe.ts';
Deno.serve(async (req: Request) => {
 if(req.method==='OPTIONS')return response(200,{});
 if(req.method!=='POST')return response(405,{error:'METHOD_NOT_ALLOWED'});
 try{
  const user=await authenticate(req);const {stripe,admin,config}=await services();const body=await req.json().catch(()=>({}));
  const customer=await customerFor(stripe,admin,user);
  if(body.action==='status'){
   const {data:profile,error}=await admin.from('commerce_customers').select('consent_at').eq('user_id',user.id).single();if(error)throw error;
   const card=profile?.consent_at?await savedCard(stripe,customer):null;
   return response(200,{hasCard:!!card,brand:card?.brand??null,last4:card?.last4??null,mode:'test'});
  }
  if(body.consent!==true)return response(400,{error:'CONSENT_REQUIRED'});
  const key=config.STRIPE_PUBLISHABLE_KEY;if(!key?.startsWith('pk_test_'))return response(503,{error:'PAYMENT_FORM_NOT_CONFIGURED'});
  const {error}=await admin.from('commerce_customers').update({consent_at:new Date().toISOString(),consent_version:'subhasto-off-session-v1'}).eq('user_id',user.id);if(error)throw error;
  const intent=await stripe.setupIntents.create({customer,usage:'off_session',metadata:{user_id:user.id,purpose:'save_card',consent_version:'subhasto-off-session-v1'}});
  return response(200,{clientSecret:intent.client_secret,publishableKey:key,returnUrl:appUrl(),mode:'test'});
 }catch(error){return failure(error);}
});

