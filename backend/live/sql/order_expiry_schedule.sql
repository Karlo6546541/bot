-- Run once after 20261103000000_subhasto_order_fixes.sql (needs pg_cron, see platform_schedule.sql).
-- Cancels orders that never reached Stripe within 30 minutes and frees their listing.
-- Orders with a PaymentIntent are handled by the stripe-release job, which asks Stripe first.
begin;
create extension if not exists pg_cron;
select cron.unschedule('subhasto-order-expiry') where exists(select 1 from cron.job where jobname='subhasto-order-expiry');
select cron.schedule('subhasto-order-expiry','* * * * *','select public.commerce_expire_orders()');
commit;
