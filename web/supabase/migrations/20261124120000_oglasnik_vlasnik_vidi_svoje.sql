-- Vlasnik uvijek vidi svoje retke (i obrisane): bez toga UPDATE na status 'obrisan' pada jer novi redak ne zadovoljava pravilo čitanja.
drop policy if exists oglasi_citaj on public.oglasnik_oglasi;
create policy oglasi_citaj on public.oglasnik_oglasi for select using (
  status in ('aktivan', 'prodano')
  or korisnik_id = (select auth.uid())
  or public.oglasnik_je_admin()
);
