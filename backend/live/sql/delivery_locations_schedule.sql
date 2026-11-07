-- Daily read of the public BOX NOW catalogue. No shipment booking or payment.
-- Uses the existing private job credential in Vault; never send it to the client.
select cron.schedule('subhasto-locker-catalog','15 3 * * *', $job$
 select net.http_post(
  url:='https://mwhrjrxytfdttjjdhdns.supabase.co/functions/v1/delivery-lockers-sync',
  headers:=jsonb_build_object('Content-Type','application/json','x-subhasto-job',
    (select decrypted_secret from vault.decrypted_secrets where name='STRIPE_RELEASE_JOB_SECRET')),
  body:='{}'::jsonb,timeout_milliseconds:=120000
 );
$job$);
