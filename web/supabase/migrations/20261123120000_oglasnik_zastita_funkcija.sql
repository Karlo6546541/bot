-- Zaštita: funkcije okidača za sinkronizaciju s aplikacijom ne smiju se pozivati izravno preko API-ja
-- (PostgreSQL provjerava pravo EXECUTE samo pri stvaranju okidača, pa okidači i dalje rade).
revoke execute on function public.oglasnik_iz_aplikacije() from public, anon, authenticated;
revoke execute on function public.oglasnik_u_aplikaciju() from public, anon, authenticated;

-- Pomoćne funkcije koje koriste pravila pristupa (RLS) ostaju dostupne samo ulogama koje ih trebaju.
revoke execute on function public.oglasnik_je_admin() from public;
revoke execute on function public.oglasnik_je_aktivan_korisnik() from public;
grant execute on function public.oglasnik_je_admin() to anon, authenticated;
grant execute on function public.oglasnik_je_aktivan_korisnik() to anon, authenticated;
