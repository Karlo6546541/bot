begin;
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
-- Generate in the database. The job credential is never returned to a client.
do $$ begin
 if not exists(select 1 from vault.secrets where name='STRIPE_RELEASE_JOB_SECRET') then
  perform vault.create_secret(gen_random_uuid()::text||gen_random_uuid()::text,'STRIPE_RELEASE_JOB_SECRET');
 end if;
end $$;
select cron.schedule('subhasto-test-seller-release','* * * * *', $job$
 select net.http_post(
  url:='https://mwhrjrxytfdttjjdhdns.supabase.co/functions/v1/stripe-release',
  headers:=jsonb_build_object('Content-Type','application/json','x-subhasto-job',(select decrypted_secret from vault.decrypted_secrets where name='STRIPE_RELEASE_JOB_SECRET')),
  body:='{}'::jsonb,timeout_milliseconds:=10000);
$job$);
commit;
