-- Web i Flutter aplikacija dijele iste oglase: dvosmjerna sinkronizacija na razini baze.
--  * oglas objavljen/izmijenjen u aplikaciji (loop_devices) -> oglasnik_oglasi (web)
--  * oglas objavljen/izmijenjen na webu -> loop_devices (aplikacija ga dobije preko svog synca)
-- Aplikacija sinkronizira po retku (updated_at), pa dodani retci stižu bez izmjena u aplikaciji.
-- Zaštita od petlje: okidači rade samo na dubini 1 (pg_trigger_depth()).

alter table public.oglasnik_oglasi add column if not exists izvor_id text unique;

create table if not exists public.oglasnik_kategorija_map (
  flutter text primary key,
  slug text not null unique
);
alter table public.oglasnik_kategorija_map enable row level security;
insert into public.oglasnik_kategorija_map (flutter, slug) values
 ('phone','mobiteli'),('laptop','racunala-i-laptopi'),('audio','audio-i-slusalice'),('console','konzole'),('camera','kamere-i-foto'),
 ('other','ostala-elektronika'),('cards','sportske-kartice'),('tcg','pokemon-i-ostali-tcg'),('comics','stripovi-i-manga'),('coins','kovanice'),
 ('stamps','markice'),('figures','figure-i-funko'),('vinyl','vinil'),('militaria','vojna-i-povijesna-oprema'),('memorabilia','sportske-memorabilije'),
 ('autographs','autogrami'),('postcards','razglednice'),('posters','plakati-i-reklame'),('magic','magic-the-gathering'),('yugioh','yu-gi-oh'),
 ('gradedCards','ocijenjene-kartice'),('banknotes','novcanice'),('goldSilver','zlato-i-srebro'),('stampCovers','omotnice-i-filatelija'),
 ('cds','cd-ovi-i-kazete'),('comicsYugo','jugoslavenski-stripovi'),('retroComputers','retro-racunala'),('badges','znacke-i-medalje'),
 ('prints','grafike-i-fotografije'),('pocketWatches','dzepni-i-zidni-satovi'),('models','modeli-i-lego'),('videoGames','videoigre'),
 ('vintage','vintage-i-antikviteti'),('jewelry','stari-nakit'),('ceramics','keramika-i-porculan'),('paintings','slike-i-crtezi'),('watches','rucni-satovi')
on conflict do nothing;

-- Povezivanje već prebačenih oglasa s izvornim zapisima.
update public.oglasnik_oglasi o set izvor_id = x.id
from (
  select distinct on (o2.id) o2.id as oid, d.id
  from public.oglasnik_oglasi o2
  join public.loop_devices d on left(d.data->>'name',100) = o2.naslov
       and (d.data->>'ownerId')::uuid = o2.korisnik_id
       and (d.data->>'createdAt')::timestamptz = o2.objavljeno
  where o2.izvor_id is null
) x
where o.id = x.oid;

-- Aplikacija -> web
create or replace function public.oglasnik_iz_aplikacije() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  d jsonb; slug_k text; cijena_n numeric; je_oglas boolean; stanje_t text; slike_a text[]; ime_v text; vl uuid;
  lista timestamptz; novi_status text;
begin
  if pg_trigger_depth() > 1 then return coalesce(new, old); end if;
  if tg_op = 'DELETE' then
    update oglasnik_oglasi set status = 'obrisan', azurirano = now() where izvor_id = old.id and status <> 'obrisan';
    return old;
  end if;
  d := new.data;
  je_oglas := (d->>'listPrice') is not null
    or exists (select 1 from loop_auctions a where a.data->>'deviceId' = new.id and a.data->>'status' = 'active');
  if not je_oglas then
    update oglasnik_oglasi set status = 'obrisan', azurirano = now() where izvor_id = new.id and status = 'aktivan';
    return new;
  end if;
  select slug into slug_k from oglasnik_kategorija_map where flutter = d->>'category';
  slike_a := array(select jsonb_array_elements_text(coalesce(d->'imagePaths','[]'::jsonb)) limit 8);
  begin vl := (d->>'ownerId')::uuid; exception when others then vl := null; end;
  if slug_k is null or cardinality(slike_a) < 1 or vl is null or char_length(coalesce(d->>'name','')) < 3
     or not exists (select 1 from auth.users where id = vl) then
    return new;
  end if;
  cijena_n := coalesce((d->>'listPrice')::numeric, (d->>'price')::numeric);
  stanje_t := case d->>'condition' when 'brandNew' then 'Novo' when 'excellent' then 'Odlično' when 'veryGood' then 'Vrlo dobro' when 'forParts' then 'Za dijelove' else 'Dobro' end;
  select coalesce((select username from loop_usernames where user_id = vl), 'Korisnik') into ime_v;
  insert into oglasnik_profili (id, ime, grad, drzava) values (vl, left(ime_v, 60), 'Zagreb', 'HR') on conflict (id) do nothing;
  lista := nullif(d->>'listedAt','')::timestamptz;
  novi_status := case when d->>'soldAt' is not null then 'prodano' else 'aktivan' end;
  insert into oglasnik_oglasi (izvor_id, korisnik_id, naslov, kategorija, opis, cijena, drzava, zupanija, grad, stanje, polja, slike, slike_male,
                               objavljeno, istjece, status, prodano_datum, prodano_cijena)
  values (new.id, vl, left(d->>'name',100), slug_k,
          case when char_length(coalesce(d->>'description',''))>=10 then left(d->>'description',5000) else left(d->>'name',100)||' – pogledaj fotografije.' end,
          cijena_n, 'HR', 'Grad Zagreb', 'Zagreb', stanje_t, '{}'::jsonb, slike_a, slike_a,
          coalesce(nullif(d->>'createdAt','')::timestamptz, now()), coalesce(lista + interval '30 days', now() + interval '30 days'),
          novi_status, nullif(d->>'soldAt','')::timestamptz, nullif(d->>'soldPrice','')::numeric)
  on conflict (izvor_id) do update set
    naslov = excluded.naslov, kategorija = excluded.kategorija, opis = excluded.opis, cijena = excluded.cijena,
    stanje = excluded.stanje, slike = excluded.slike, slike_male = excluded.slike_male, azurirano = now(),
    istjece = case when lista is not null then excluded.istjece else oglasnik_oglasi.istjece end,
    status = case when oglasnik_oglasi.status in ('uklonjen') then oglasnik_oglasi.status else excluded.status end,
    prodano_datum = excluded.prodano_datum, prodano_cijena = excluded.prodano_cijena;
  return new;
end $$;

drop trigger if exists oglasnik_iz_aplikacije on public.loop_devices;
create trigger oglasnik_iz_aplikacije after insert or update or delete on public.loop_devices
  for each row execute function public.oglasnik_iz_aplikacije();

-- Web -> aplikacija
create or replace function public.oglasnik_u_aplikaciju() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  fk text; stanje_f text; did text; doc jsonb;
begin
  if pg_trigger_depth() > 1 then return new; end if;
  select flutter into fk from oglasnik_kategorija_map where slug = new.kategorija;
  if fk is null or new.cijena is null then return new; end if;
  stanje_f := case new.stanje when 'Novo' then 'brandNew' when 'Odlično' then 'excellent' when 'Vrlo dobro' then 'veryGood' when 'Za dijelove' then 'forParts' else 'good' end;
  if tg_op = 'INSERT' and new.izvor_id is null then
    did := 'web-' || new.id::text;
    doc := jsonb_build_object('id', did, 'file', null, 'name', new.naslov, 'model', '', 'price', new.cijena, 'ownerId', new.korisnik_id,
      'category', fk, 'listedAt', new.objavljeno, 'quantity', 1, 'condition', stanje_f, 'createdAt', new.objavljeno,
      'listPrice', new.cijena, 'imagePaths', to_jsonb(new.slike), 'description', new.opis, 'discountUntil', null,
      'marketChecked', false, 'discountPercent', 0);
    insert into loop_devices (id, data, updated_at) values (did, doc, now())
      on conflict (id) do update set data = excluded.data, updated_at = now();
    update oglasnik_oglasi set izvor_id = did where id = new.id;
  elsif tg_op = 'UPDATE' and new.izvor_id is not null then
    update loop_devices set updated_at = now(), data = data
      || jsonb_build_object('name', new.naslov, 'price', new.cijena, 'category', fk, 'condition', stanje_f,
                            'description', new.opis, 'imagePaths', to_jsonb(new.slike))
      || case when new.izvor_id like 'web-%' or (data->>'listPrice') is not null then
           jsonb_build_object('listPrice', case when new.status in ('obrisan','uklonjen') then null else new.cijena end,
                              'listedAt', case when new.status in ('obrisan','uklonjen') then null else coalesce(data->>'listedAt', to_char(new.objavljeno at time zone 'utc','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')) end)
         else '{}'::jsonb end
      || case when new.status = 'prodano' then jsonb_build_object('soldAt', coalesce(new.prodano_datum, now()), 'soldPrice', coalesce(new.prodano_cijena, new.cijena)) else '{}'::jsonb end
    where id = new.izvor_id;
  end if;
  return new;
end $$;

drop trigger if exists oglasnik_u_aplikaciju on public.oglasnik_oglasi;
create trigger oglasnik_u_aplikaciju after insert or update on public.oglasnik_oglasi
  for each row execute function public.oglasnik_u_aplikaciju();
