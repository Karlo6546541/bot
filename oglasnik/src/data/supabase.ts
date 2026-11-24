// Pravi način rada: Supabase (prijava, baza, spremište slika).
// Pravila pristupa provodi baza (RLS i okidači u supabase/migrations);
// ovdje su samo upiti.
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { PO_STRANICI } from '../config/app';
import { ocistiNacrt, provjeriOglas } from '../lib/provjera';
import { rijeciUpita } from '../lib/tekst';
import {
  GreskaKorisnika,
  type Backend,
  type Filteri,
  type Kontakt,
  type NacrtOglasa,
  type Oglas,
  type Poruka,
  type Prijava,
  type Profil,
  type Razgovor,
  type RazgovorSazetak,
  type SlikaZaSpremanje,
} from './types';

const BUCKET = 'oglasnik-slike';
const OGLAS_STUPCI =
  'id,korisnik_id,naslov,kategorija,opis,cijena,zupanija,grad,stanje,polja,slike,slike_male,prikazi_telefon,vrsta_prodaje,status,objavljeno,istjece,prodano_datum,prodano_cijena,uklonjeno_razlog';

interface RazgovorRed extends Razgovor {
  kupac_procitao: string | null;
  prodavatelj_procitao: string | null;
}

/** Poruke baze prevedene za korisnika; ostalo je općenita greška. */
function prevedi(e: { message?: string; code?: string } | null): never {
  const m = e?.message ?? '';
  if (/Invalid login credentials/i.test(m)) throw new GreskaKorisnika('Pogrešan e-mail ili lozinka.');
  if (/already registered/i.test(m)) throw new GreskaKorisnika('Taj e-mail je već registriran.');
  if (/Email not confirmed/i.test(m)) throw new GreskaKorisnika('Potvrdi e-mail adresu (poveznica je u pošti).');
  if (/Password should be/i.test(m)) throw new GreskaKorisnika('Lozinka mora imati barem 8 znakova.');
  if (/row-level security/i.test(m)) throw new GreskaKorisnika('Nemaš dopuštenje za ovu radnju (račun je možda blokiran).');
  if (/duplicate key.*oglasnik_prijave/i.test(m)) throw new GreskaKorisnika('Već si prijavio ovaj oglas.');
  if (e?.code === '42P01' || e?.code === 'PGRST205') throw new GreskaKorisnika('Baza oglasnika još nije postavljena.');
  if (/Oglas|Samo administrator/.test(m)) throw new GreskaKorisnika(m);
  throw new Error(m || 'Nešto nije u redu. Pokušaj ponovno.');
}

function ok<T>(r: { data: T; error: unknown }): T {
  if (r.error) prevedi(r.error as { message?: string });
  return r.data;
}

export class SupabaseBackend implements Backend {
  readonly nacin = 'supabase' as const;
  private sb: SupabaseClient;
  private profilCache = new Map<string, Promise<Profil | null>>();

  constructor(url: string, kljuc: string) {
    this.sb = createClient(url, kljuc, { auth: { persistSession: true, detectSessionInUrl: true } });
  }

  private async uid(): Promise<string | null> {
    const { data } = await this.sb.auth.getSession();
    return data.session?.user.id ?? null;
  }
  private async mora(): Promise<string> {
    const id = await this.uid();
    if (!id) throw new GreskaKorisnika('Prijavi se za nastavak.');
    return id;
  }

  // ---------- Prijava ----------

  /** Profil se stvara pri prvoj prijavi (i za Google račune). */
  private async osigurajProfil(): Promise<Profil | null> {
    const { data } = await this.sb.auth.getSession();
    const u = data.session?.user;
    if (!u) return null;
    const postoji = ok(await this.sb.from('oglasnik_profili').select('*').eq('id', u.id).maybeSingle()) as Profil | null;
    if (postoji) return postoji;
    const ime =
      (u.user_metadata?.ime as string | undefined) ||
      (u.user_metadata?.full_name as string | undefined) ||
      (u.email ?? 'Korisnik').split('@')[0];
    return ok(
      await this.sb.from('oglasnik_profili').insert({ id: u.id, ime: ime.slice(0, 60) }).select('*').single(),
    ) as Profil;
  }

  async trenutni() {
    return this.osigurajProfil();
  }

  naPromjenuPrijave(cb: () => void) {
    const { data } = this.sb.auth.onAuthStateChange(() => {
      this.profilCache.clear();
      cb();
    });
    return () => data.subscription.unsubscribe();
  }

  async registracija(email: string, lozinka: string, ime: string) {
    if (ime.trim().length < 2) throw new GreskaKorisnika('Upiši ime.');
    if (lozinka.length < 8) throw new GreskaKorisnika('Lozinka mora imati barem 8 znakova.');
    const r = await this.sb.auth.signUp({
      email: email.trim(),
      password: lozinka,
      options: { data: { ime: ime.trim() }, emailRedirectTo: location.origin + import.meta.env.BASE_URL },
    });
    if (r.error) prevedi(r.error);
    if (r.data.session) await this.osigurajProfil();
    return { potvrdaEmaila: !r.data.session };
  }

  async prijava(email: string, lozinka: string) {
    const r = await this.sb.auth.signInWithPassword({ email: email.trim(), password: lozinka });
    if (r.error) prevedi(r.error);
    await this.osigurajProfil();
  }

  async prijavaGoogle() {
    const r = await this.sb.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: location.origin + import.meta.env.BASE_URL },
    });
    if (r.error) prevedi(r.error);
  }

  async odjava() {
    await this.sb.auth.signOut();
  }

  async spremiProfil(p: { ime: string; grad: string | null; telefon: string | null }) {
    const id = await this.mora();
    if (p.ime.trim().length < 2) throw new GreskaKorisnika('Upiši ime.');
    ok(await this.sb.from('oglasnik_profili').update({ ime: p.ime.trim(), grad: p.grad?.trim() || null }).eq('id', id));
    ok(await this.sb.from('oglasnik_privatno').upsert({ id, telefon: p.telefon?.trim() || null }));
    this.profilCache.delete(id);
  }

  async mojTelefon() {
    const id = await this.mora();
    const r = ok(await this.sb.from('oglasnik_privatno').select('telefon').eq('id', id).maybeSingle()) as {
      telefon: string | null;
    } | null;
    return r?.telefon ?? null;
  }

  profil(id: string): Promise<Profil | null> {
    let p = this.profilCache.get(id);
    if (!p) {
      p = Promise.resolve(this.sb.from('oglasnik_profili').select('*').eq('id', id).maybeSingle()).then(
        (r) => ok(r) as Profil | null,
      );
      this.profilCache.set(id, p);
    }
    return p;
  }

  // ---------- Oglasi ----------

  async trazi(f: Filteri, stranica: number) {
    let q = this.sb
      .from('oglasnik_oglasi')
      .select(OGLAS_STUPCI, { count: 'exact' })
      .eq('status', 'aktivan')
      .gt('istjece', new Date().toISOString());
    if (f.korisnik) q = q.eq('korisnik_id', f.korisnik);
    if (f.kategorija) q = q.eq('kategorija', f.kategorija);
    if (f.zupanija) q = q.eq('zupanija', f.zupanija);
    if (f.stanje) q = q.eq('stanje', f.stanje);
    if (f.grad) q = q.ilike('grad', `%${f.grad.replace(/[%_\\]/g, '')}%`);
    if (f.cijenaOd != null) q = q.gte('cijena', f.cijenaOd);
    if (f.cijenaDo != null) q = q.lte('cijena', f.cijenaDo);
    for (const [k, v] of Object.entries(f.polja ?? {})) {
      if (v && /^[a-z_]+$/.test(k)) q = q.eq(`polja->>${k}`, v);
    }
    for (const w of rijeciUpita(f.q)) q = q.like('pretraga', `%${w}%`);
    if (f.sort === 'cijena_rastuce' || f.sort === 'cijena_padajuce') {
      q = q.order('cijena', { ascending: f.sort === 'cijena_rastuce', nullsFirst: false });
    }
    q = q.order('objavljeno', { ascending: false });
    const r = await q.range(stranica * PO_STRANICI, (stranica + 1) * PO_STRANICI - 1);
    return { stavke: ok(r) as unknown as Oglas[], ukupno: r.count ?? 0 };
  }

  async oglas(id: string) {
    if (!/^[0-9a-f-]{36}$/i.test(id)) return null;
    return ok(await this.sb.from('oglasnik_oglasi').select(OGLAS_STUPCI).eq('id', id).maybeSingle()) as Oglas | null;
  }

  async mojiOglasi() {
    const id = await this.mora();
    return ok(
      await this.sb
        .from('oglasnik_oglasi')
        .select(OGLAS_STUPCI)
        .eq('korisnik_id', id)
        .neq('status', 'obrisan')
        .order('objavljeno', { ascending: false }),
    ) as unknown as Oglas[];
  }

  async brojAktivnihOglasa(korisnikId: string) {
    const r = await this.sb
      .from('oglasnik_oglasi')
      .select('id', { count: 'exact', head: true })
      .eq('korisnik_id', korisnikId)
      .eq('status', 'aktivan')
      .gt('istjece', new Date().toISOString());
    if (r.error) prevedi(r.error);
    return r.count ?? 0;
  }

  private async posaljiSliku(uid: string, oglasId: string, b: Blob, ime: string) {
    const put = `${uid}/${oglasId}/${ime}`;
    ok(await this.sb.storage.from(BUCKET).upload(put, b, { contentType: b.type || 'image/webp', upsert: true, cacheControl: '31536000' }));
    return this.sb.storage.from(BUCKET).getPublicUrl(put).data.publicUrl;
  }

  async spremiOglas(nacrt: NacrtOglasa, slike: SlikaZaSpremanje[], id?: string) {
    const uid = await this.mora();
    const greske = provjeriOglas(nacrt, slike.length);
    if (Object.keys(greske).length) throw new GreskaKorisnika(Object.values(greske)[0]);
    const n = ocistiNacrt(nacrt);
    const oglasId = id ?? crypto.randomUUID();
    const velike: string[] = [];
    const male: string[] = [];
    const oznaka = Date.now().toString(36);
    for (const [i, s] of slike.entries()) {
      if (s.vrsta === 'postojeca') {
        velike.push(s.url);
        male.push(s.mala);
      } else {
        const ext = s.velika.type === 'image/jpeg' ? 'jpg' : 'webp';
        velike.push(await this.posaljiSliku(uid, oglasId, s.velika, `${oznaka}-${i}.${ext}`));
        male.push(await this.posaljiSliku(uid, oglasId, s.mala, `${oznaka}-${i}-m.${ext}`));
      }
    }
    const red = { ...n, slike: velike, slike_male: male };
    const r = id
      ? await this.sb.from('oglasnik_oglasi').update(red).eq('id', id).select(OGLAS_STUPCI).single()
      : await this.sb
          .from('oglasnik_oglasi')
          .insert({ ...red, id: oglasId, korisnik_id: uid })
          .select(OGLAS_STUPCI)
          .single();
    return ok(r) as unknown as Oglas;
  }

  async produlji(id: string) {
    await this.mora();
    const istjece = new Date(Date.now() + 30 * 86400000).toISOString();
    ok(await this.sb.from('oglasnik_oglasi').update({ istjece }).eq('id', id).eq('status', 'aktivan'));
  }

  async oznaciProdano(id: string, cijena: number | null) {
    await this.mora();
    ok(await this.sb.from('oglasnik_oglasi').update({ status: 'prodano', prodano_cijena: cijena }).eq('id', id));
  }

  async obrisi(id: string) {
    await this.mora();
    ok(await this.sb.from('oglasnik_oglasi').update({ status: 'obrisan' }).eq('id', id));
  }

  // ---------- Favoriti ----------

  async favoritIds() {
    const uid = await this.uid();
    if (!uid) return new Set<string>();
    const r = ok(await this.sb.from('oglasnik_favoriti').select('oglas_id').eq('korisnik_id', uid)) as {
      oglas_id: string;
    }[];
    return new Set(r.map((x) => x.oglas_id));
  }

  async favoriti() {
    const uid = await this.mora();
    const r = ok(
      await this.sb
        .from('oglasnik_favoriti')
        .select(`kreirano, oglas:oglasnik_oglasi(${OGLAS_STUPCI})`)
        .eq('korisnik_id', uid)
        .order('kreirano', { ascending: false }),
    ) as unknown as { oglas: Oglas | null }[];
    return r.map((x) => x.oglas).filter((o): o is Oglas => !!o);
  }

  async postaviFavorit(oglasId: string, da: boolean) {
    const uid = await this.mora();
    if (da) ok(await this.sb.from('oglasnik_favoriti').upsert({ korisnik_id: uid, oglas_id: oglasId }));
    else ok(await this.sb.from('oglasnik_favoriti').delete().eq('korisnik_id', uid).eq('oglas_id', oglasId));
  }

  // ---------- Poruke ----------

  private async sazetci(redovi: RazgovorRed[], uid: string): Promise<RazgovorSazetak[]> {
    if (!redovi.length) return [];
    const ids = redovi.map((r) => r.id);
    const oglasIds = [...new Set(redovi.map((r) => r.oglas_id))];
    const [oglasi, poruke] = await Promise.all([
      this.sb.from('oglasnik_oglasi').select('id,naslov,slike_male,cijena,status').in('id', oglasIds),
      // Zadnja poruka svakog razgovora (dovoljno za popis).
      this.sb.from('oglasnik_poruke').select('*').in('razgovor_id', ids).order('poslano', { ascending: false }).limit(ids.length * 20),
    ]);
    const o = (ok(oglasi) ?? []) as RazgovorSazetak['oglas'][];
    const p = (ok(poruke) ?? []) as Poruka[];
    return Promise.all(
      redovi.map(async (r) => {
        const zadnja = p.find((x) => x.razgovor_id === r.id) ?? null;
        const procitao = r.kupac_id === uid ? r.kupac_procitao : r.prodavatelj_procitao;
        return {
          razgovor: r,
          oglas: o.find((x) => x?.id === r.oglas_id) ?? null,
          sugovornik: await this.profil(r.kupac_id === uid ? r.prodavatelj_id : r.kupac_id),
          zadnja,
          neprocitano: !!zadnja && zadnja.posiljatelj_id !== uid && (procitao ?? '') < zadnja.poslano,
        };
      }),
    );
  }

  async razgovori() {
    const uid = await this.mora();
    const r = ok(
      await this.sb
        .from('oglasnik_razgovori')
        .select('*')
        .or(`kupac_id.eq.${uid},prodavatelj_id.eq.${uid}`)
        .order('zadnja_poruka', { ascending: false })
        .limit(100),
    ) as RazgovorRed[];
    return this.sazetci(r, uid);
  }

  async razgovor(id: string) {
    const uid = await this.mora();
    const r = ok(await this.sb.from('oglasnik_razgovori').select('*').eq('id', id).maybeSingle()) as RazgovorRed | null;
    if (!r) return null;
    const poruke = ok(
      await this.sb.from('oglasnik_poruke').select('*').eq('razgovor_id', id).order('poslano', { ascending: true }).limit(500),
    ) as Poruka[];
    const [sazetak] = await this.sazetci([r], uid);
    return { sazetak, poruke };
  }

  async postojeciRazgovor(oglasId: string) {
    const uid = await this.uid();
    if (!uid) return null;
    const r = ok(
      await this.sb.from('oglasnik_razgovori').select('id').eq('oglas_id', oglasId).eq('kupac_id', uid).maybeSingle(),
    ) as { id: string } | null;
    return r?.id ?? null;
  }

  async zapocniRazgovor(oglasId: string, tekst: string) {
    const uid = await this.mora();
    if (!tekst.trim()) throw new GreskaKorisnika('Poruka je prazna.');
    let id = await this.postojeciRazgovor(oglasId);
    if (!id) {
      const o = await this.oglas(oglasId);
      if (!o) throw new GreskaKorisnika('Oglas nije pronađen.');
      if (o.korisnik_id === uid) throw new GreskaKorisnika('Ne možeš pisati sam sebi.');
      const r = ok(
        await this.sb
          .from('oglasnik_razgovori')
          .insert({ oglas_id: oglasId, kupac_id: uid, prodavatelj_id: o.korisnik_id })
          .select('id')
          .single(),
      ) as { id: string };
      id = r.id;
    }
    await this.posalji(id, tekst);
    return id;
  }

  async posalji(razgovorId: string, tekst: string) {
    const uid = await this.mora();
    tekst = tekst.trim();
    if (!tekst) throw new GreskaKorisnika('Poruka je prazna.');
    if (tekst.length > 2000) throw new GreskaKorisnika('Poruka može imati najviše 2000 znakova.');
    ok(await this.sb.from('oglasnik_poruke').insert({ razgovor_id: razgovorId, posiljatelj_id: uid, tekst }));
  }

  async oznaciProcitano(razgovorId: string) {
    ok(await this.sb.rpc('oglasnik_procitano', { p_razgovor: razgovorId }));
  }

  async telefon(oglasId: string) {
    await this.mora();
    return ok(await this.sb.rpc('oglasnik_telefon', { p_oglas: oglasId })) as string | null;
  }

  async kontakti(oglasId: string) {
    return ok(
      await this.sb.from('oglasnik_kontakti').select('*').eq('oglas_id', oglasId).order('kreirano', { ascending: false }),
    ) as Kontakt[];
  }

  // ---------- Prijave i moderacija ----------

  async prijaviOglas(oglasId: string, razlog: Prijava['razlog'], napomena: string) {
    const uid = await this.mora();
    ok(
      await this.sb
        .from('oglasnik_prijave')
        .insert({ oglas_id: oglasId, prijavitelj_id: uid, razlog, napomena: napomena.trim().slice(0, 1000) }),
    );
  }

  async prijave() {
    return ok(
      await this.sb
        .from('oglasnik_prijave')
        .select('*, oglas:oglasnik_oglasi(id,naslov,korisnik_id,status)')
        .order('kreirano', { ascending: false })
        .limit(200),
    ) as Prijava[];
  }

  async rijesiPrijavu(id: string) {
    ok(await this.sb.from('oglasnik_prijave').update({ status: 'rijesena' }).eq('id', id));
  }

  async ukloniOglas(id: string, razlog: string) {
    ok(await this.sb.from('oglasnik_oglasi').update({ status: 'uklonjen', uklonjeno_razlog: razlog || null }).eq('id', id));
  }

  async blokiraj(korisnikId: string, blokiran: boolean) {
    const uid = await this.mora();
    if (uid === korisnikId) throw new GreskaKorisnika('Ne možeš blokirati sebe.');
    ok(await this.sb.from('oglasnik_profili').update({ blokiran }).eq('id', korisnikId));
    this.profilCache.delete(korisnikId);
  }

  async korisnici() {
    return ok(
      await this.sb.from('oglasnik_profili').select('*').order('registriran', { ascending: false }).limit(200),
    ) as Profil[];
  }
}
