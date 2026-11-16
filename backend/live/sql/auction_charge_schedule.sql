-- Svake minute: automatska naplata pobjednika aukcije (funkcija
-- stripe-auction-charge, isti tajni ključ posla kao stripe-release).
begin;
select cron.unschedule(jobid) from cron.job where jobname='subhasto-auction-charge';
select cron.schedule('subhasto-auction-charge','* * * * *', $job$
 select net.http_post(
  url:='https://mwhrjrxytfdttjjdhdns.supabase.co/functions/v1/stripe-auction-charge',
  headers:=jsonb_build_object('Content-Type','application/json','x-subhasto-job',(select decrypted_secret from vault.decrypted_secrets where name='STRIPE_RELEASE_JOB_SECRET')),
  body:='{}'::jsonb,timeout_milliseconds:=20000);
$job$);
commit;
