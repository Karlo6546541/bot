import assert from 'node:assert/strict';
import Stripe from 'npm:stripe@23.0.0';
import { sellerPrefill, publicSellerUrl, prepareSeller } from '../functions/_shared/seller_onboarding.ts';
const account=(data:Record<string,unknown>={})=>({id:'acct_owned',object:'v2.core.account',metadata:{user_id:'seller-one'},identity:{country:'HR'},...data}) as unknown as Stripe.V2.Core.Account;
const info={legalName:'Test Seller',kind:'private',birthDate:'1990-01-02T00:00:00.000',address:'Ulica 1, 10000 Zagreb',iban:'PRIVATE_BANK',oib:'PRIVATE_TAX',attestations:{terms_of_service:'forged'}};
Deno.test('private seller prefill copies name, birth date and address without bank, tax or consent claims',()=>{
 const patch=sellerPrefill(account(),info,{country:'HR'},'seller@example.test');
 assert.deepEqual(patch.identity,{entity_type:'individual',individual:{given_name:'Test',surname:'Seller',email:'seller@example.test',date_of_birth:{year:1990,month:1,day:2},address:{country:'HR',line1:'Ulica 1',postal_code:'10000',city:'Zagreb'}}});
 assert.ok(!JSON.stringify(patch).includes('PRIVATE_'));assert.ok(!JSON.stringify(patch).includes('attestation'));
});
Deno.test('provider identity values and existing entity type cannot be overwritten',()=>{
 const patch=sellerPrefill(account({identity:{country:'HR',entity_type:'individual',individual:{given_name:'Verified',surname:'Person',email:'verified@example.test',date_of_birth:{year:1980,month:1,day:1},address:{country:'HR',line1:'Verified street',city:'Split',postal_code:'21000'}}},contact_email:'verified@example.test'}),info,{},'other@example.test');
 assert.deepEqual(patch,{});
 const changed=sellerPrefill(account({identity:{country:'HR',entity_type:'company',business_details:{registered_name:'Existing'}}}),info,{});
 assert.equal(changed.identity,undefined);
});
Deno.test('company registration is copied without inventing representatives or tax verification',()=>{
 const patch=sellerPrefill(account(),{...info,kind:'business',companyName:'Test Company',contactPhone:'+385 912345678'},{country:'HR'});
 assert.equal(patch.identity?.entity_type,'company');
 assert.equal(patch.identity?.business_details?.registered_name,'Test Company');
 assert.equal(patch.identity?.business_details?.phone,'+385912345678');
 assert.equal(patch.identity?.individual,undefined);
 assert.ok(!JSON.stringify(patch).includes('attestation'));
});
Deno.test('invalid and underage birth dates are left for hosted onboarding',()=>{
 for(const birthDate of ['not-a-date','1990-02-31','2020-01-01']){
  const patch=sellerPrefill(account(),{...info,birthDate},{});
  assert.equal(patch.identity?.individual?.date_of_birth,undefined);
 }
});
Deno.test('public website always uses the trusted application origin',()=>{
 assert.equal(publicSellerUrl('https://app.example.test/bot/?cloud=orders','karlo'),'https://app.example.test/bot/?shop=karlo');
 assert.equal(publicSellerUrl('https://app.example.test/bot/?cloud=orders','https://evil.test'),'https://app.example.test/bot/');
});
function fixture({existing=true,active=false,mismatch=false,updateError=false,dbError=false,forbidUpdate=false,forbidIdentity=false}={}){
 let mapping: {stripe_account_id:string}|null=existing?{stripe_account_id:'acct_owned'}:null;
 const calls={creates:0,updates:0,reads:[] as string[],saved:[] as unknown[],creation:null as unknown};
 const admin={from:(table:string)=>({
  select:(_columns:string)=>({eq:(_column:string,id:string)=>({maybeSingle:async()=>{
   assert.equal(id,'seller-one');calls.reads.push(table);
   if(dbError)return {data:null,error:new Error('private database data')};
   return {data:table==='commerce_sellers'?mapping:table==='loop_sellers'?{data:info}:{data:{username:'karlo',country:'HR'}},error:null};
  }})}),
  upsert:async(row:{stripe_account_id:string;user_id:string})=>{assert.equal(row.user_id,'seller-one');mapping={stripe_account_id:row.stripe_account_id};calls.saved.push(row);return {error:null};},
 })};
 const current=account({metadata:{user_id:mismatch?'someone-else':'seller-one'},configuration:{recipient:{capabilities:{stripe_balance:{stripe_transfers:{status:active?'active':'restricted'}}}}}});
 const stripe={v2:{core:{accounts:{
  create:async(params:unknown,options:{idempotencyKey:string})=>{calls.creates++;calls.creation=params;assert.equal(options.idempotencyKey,'seller-v2-seller-one');return current;},
  retrieve:async(id:string,params?:{include?:string[]})=>{assert.equal(id,'acct_owned');if(forbidIdentity&&params?.include?.includes('identity'))throw new Stripe.errors.StripePermissionError({type:'invalid_request_error',code:'forbidden',message:'not permitted'});return current;},
  update:async(id:string,patch:unknown)=>{assert.equal(id,'acct_owned');calls.updates++;if(forbidUpdate)throw new Stripe.errors.StripePermissionError({type:'invalid_request_error',code:'forbidden',message:'not permitted'});if(updateError)throw new Stripe.errors.StripeInvalidRequestError({type:'invalid_request_error',code:'invalid_fields',message:'field not permitted'});return current;},
 }}}} as unknown as Stripe;
 return {stripe,admin,calls};
}
Deno.test('new seller provisioning is idempotent and reads only that authenticated seller',async()=>{
 const f=fixture({existing:false});
 const user={id:'seller-one',email:'seller@example.test'};
 for(let i=0;i<2;i++)assert.deepEqual(await prepareSeller(f.stripe,f.admin,user,'https://app.example.test/bot/'),{accountId:'acct_owned',ready:false});
 assert.equal(f.calls.creates,1);assert.equal(f.calls.saved.length,1);
 assert.deepEqual((f.calls.creation as {metadata:unknown}).metadata,{user_id:'seller-one'});
 assert.ok(f.calls.reads.includes('loop_sellers'));
});
Deno.test('existing active accounts continue without replacing accounts or changing identity',async()=>{
 const f=fixture({active:true});
 assert.equal((await prepareSeller(f.stripe,f.admin,{id:'seller-one'},'https://app.example.test/bot/')).ready,true);
 assert.equal(f.calls.creates,0);assert.equal(f.calls.updates,0);assert.equal(f.calls.saved.length,0);
});
Deno.test('database failure or account ownership mismatch cannot provision a replacement',async()=>{
 for(const options of [{dbError:true},{mismatch:true}]){
  const f=fixture(options);
  await assert.rejects(()=>prepareSeller(f.stripe,f.admin,{id:'seller-one'},'https://app.example.test/bot/'));
  assert.equal(f.calls.creates,0);assert.equal(f.calls.updates,0);
 }
});
Deno.test('a provider prefill rejection leaves the seller restricted for hosted onboarding',async()=>{
 const f=fixture({updateError:true});
 assert.deepEqual(await prepareSeller(f.stripe,f.admin,{id:'seller-one'},'https://app.example.test/bot/'),{accountId:'acct_owned',ready:false});
 assert.equal(f.calls.creates,0);assert.equal(f.calls.updates,1);
});

Deno.test('Express accounts without identity access still reach hosted onboarding',async()=>{
 const updates=fixture({forbidUpdate:true});
 assert.deepEqual(await prepareSeller(updates.stripe,updates.admin,{id:'seller-one'},'https://app.example.test/bot/'),{accountId:'acct_owned',ready:false});
 assert.equal(updates.calls.updates,1);
 const reads=fixture({forbidIdentity:true});
 assert.deepEqual(await prepareSeller(reads.stripe,reads.admin,{id:'seller-one'},'https://app.example.test/bot/'),{accountId:'acct_owned',ready:false});
 assert.equal(reads.calls.updates,0);
});
