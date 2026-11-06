import Stripe from 'npm:stripe@23.0.0';

export type SellerProfile = Record<string, unknown>;
const text = (value: unknown, max = 250) => typeof value === 'string' ? value.trim().slice(0,max) : '';
type Address = {country?:string;line1?:string;city?:string;postal_code?:string};

/** Copy supplied values only into empty provider fields. Never attest consent or verification. */
export function sellerPrefill(account: Stripe.V2.Core.Account, seller: SellerProfile,
  profile: SellerProfile, email?: string | null): Stripe.V2.Core.AccountUpdateParams {
  const patch: Stripe.V2.Core.AccountUpdateParams = {};
  const country = (account.identity?.country || text(profile.country) || 'HR').toUpperCase();
  const name = text(seller.legalName);
  const names = name.split(/\s+/).filter(Boolean);
  const address: Address = {};
  const rawAddress = text(seller.address,500);
  if(rawAddress) {
    address.country=country;
    const parts=rawAddress.split(',').map(p=>p.trim()).filter(Boolean);
    address.line1=parts[0];
    const place=parts.slice(1).join(', ');
    const postal=place.match(/\b([0-9]{4,6})\b/);
    if(postal) address.postal_code=postal[1];
    const city=text(profile.city) || (postal?place.replace(postal[0],'').replace(/^[,\s]+|[,\s]+$/g,''):'');
    if(city) address.city=city;
  }
  const missingAddress=(current?: Address | null) => Object.fromEntries(Object.entries(address).filter(([key])=>!current?.[key as keyof Address]));
  const business = seller.kind === 'business';
  const type = business ? 'company' : 'individual';
  const identity: NonNullable<Stripe.V2.Core.AccountUpdateParams['identity']> = {};
  if(!account.identity?.entity_type && name) identity.entity_type=type;
  // Preserve an existing legal entity type, even when local profile data differs.
  const effective=account.identity?.entity_type || identity.entity_type;
  if(effective==='individual'&&!business) {
    const current=account.identity?.individual;
    const person: NonNullable<typeof identity.individual> = {};
    if(!current?.given_name&&names.length>1) person.given_name=names[0];
    if(!current?.surname&&names.length>1) person.surname=names.slice(1).join(' ');
    if(!current?.email&&email) person.email=email;
    if(!current?.date_of_birth&&typeof seller.birthDate==='string') {
      const match=seller.birthDate.match(/^(\d{4})-(\d{2})-(\d{2})/);
      if(match) {
        const [year,month,day]=match.slice(1).map(Number);
        const date=new Date(Date.UTC(year,month-1,day));
        if(year>=1900&&new Date(Date.UTC(year+18,month-1,day))<=new Date()&&date.getUTCFullYear()===year&&date.getUTCMonth()===month-1&&date.getUTCDate()===day) person.date_of_birth={year,month,day};
      }
    }
    const fields=missingAddress(current?.address);
    if(Object.keys(fields).length) person.address=fields;
    // Tax IDs and bank accounts stay in the Stripe-hosted verification form.
    if(Object.keys(person).length) identity.individual=person;
  } else if(effective==='company'&&business) {
    const current=account.identity?.business_details;
    const details: NonNullable<typeof identity.business_details> = {};
    const companyName=text(seller.companyName);
    if(!current?.registered_name&&companyName) details.registered_name=companyName;
    const phone=text(seller.contactPhone,40);
    if(!current?.phone&&/^\+[1-9][0-9 ]{5,24}$/.test(phone)) details.phone=phone.replaceAll(' ','');
    const fields=missingAddress(current?.address);
    if(Object.keys(fields).length) details.address=fields;
    if(Object.keys(details).length) identity.business_details=details;
  }
  if(Object.keys(identity).length) patch.identity=identity;
  if(!account.contact_email&&email) patch.contact_email=email;
  return patch;
}

export function publicSellerUrl(appUrl: string, username: unknown) {
  const url=new URL(appUrl);url.search='';url.hash='';
  const name=text(username,40);
  if(/^[a-zA-Z0-9._-]+$/.test(name))url.searchParams.set('shop',name);
  return url.toString();
}

type Admin = {from: (name:string)=>any};
export async function prepareSeller(stripe: Stripe, admin: Admin, user: {id:string;email?:string|null},
  appUrl: string, supplied?: SellerProfile, suppliedCountry?: string) {
  const [{data:mapping,error:mappingError},{data:privateRow,error:privateError},{data:publicRow,error:publicError}]=await Promise.all([
    admin.from('commerce_sellers').select('stripe_account_id').eq('user_id',user.id).maybeSingle(),
    admin.from('loop_sellers').select('data').eq('id',user.id).maybeSingle(),
    admin.from('loop_users').select('data').eq('id',user.id).maybeSingle(),
  ]);
  if(mappingError||privateError||publicError)throw new Error('SELLER_PROFILE_UNAVAILABLE');
  const profile=publicRow?.data ?? {};
  const country=text(profile.country || suppliedCountry || 'HR',2).toUpperCase();
  const seller=supplied ?? privateRow?.data ?? {};
  let accountId=mapping?.stripe_account_id as string | undefined;
  if(!accountId){
    const account=await stripe.v2.core.accounts.create({
      contact_email:user.email??undefined,dashboard:'express',
      defaults:{responsibilities:{fees_collector:'application',losses_collector:'application'}},
      identity:{country},
      configuration:{recipient:{capabilities:{stripe_balance:{stripe_transfers:{requested:true}}}}},
      metadata:{user_id:user.id},
    },{idempotencyKey:`seller-v2-${user.id}`});
    accountId=account.id;
    const {error}=await admin.from('commerce_sellers').upsert({user_id:user.id,stripe_account_id:accountId},{onConflict:'user_id'});
    if(error)throw new Error('SELLER_PROFILE_UNAVAILABLE');
  }
  // Express račun: identitet (ime, adresa) smije čitati/mijenjati samo Stripe.
  // Bez dopuštenja čitamo samo status isplate, a podatke unosi Stripe obrazac.
  const isPermissionError=(error: unknown)=>error instanceof Stripe.errors.StripePermissionError;
  let identityAccess=true;
  let account: Stripe.V2.Core.Account;
  try{
    account=await stripe.v2.core.accounts.retrieve(accountId,{include:['configuration.recipient','identity','defaults']});
  }catch(error){
    if(!isPermissionError(error))throw error;
    identityAccess=false;
    account=await stripe.v2.core.accounts.retrieve(accountId,{include:['configuration.recipient']});
  }
  if(account.metadata?.user_id&&account.metadata.user_id!==user.id)throw new Error('SELLER_ACCOUNT_MISMATCH');
  let ready=account.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status==='active';
  // Leave verified/active accounts untouched. The existing button can still open account management.
  if(!ready&&identityAccess){
    const patch=sellerPrefill(account,seller,{...profile,country},user.email);
    if(!account.defaults?.profile?.business_url)patch.defaults={profile:{business_url:publicSellerUrl(appUrl,profile.username)}};
    if(Object.keys(patch).length){
      try{
        account=await stripe.v2.core.accounts.update(accountId,{...patch,include:['configuration.recipient']});
        ready=account.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status==='active';
      }catch(error){
        // Hosted onboarding still collects details that Stripe won't allow the platform to prefill.
        // Do not log raw errors: they can contain identity/address values.
        if(!(error instanceof Stripe.errors.StripeInvalidRequestError)&&!isPermissionError(error))throw error;
      }
    }
  }
  return {accountId,ready};
}

