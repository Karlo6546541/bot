import { useEffect, useRef, useState } from 'preact/hooks';
import { backend } from '../data';
import { adresa } from '../lib/router';
import { postaviSeo } from '../lib/seo';
import { obavijest, useJa, useUcitaj } from '../lib/stanje';
import { cijenaTekst, datum, prije } from '../lib/tekst';
import { Greska, MoraPrijava, Mreza, SigurnaKupnja, Ucitavanje, putOglasa } from '../components/ui';

// Broj nepročitanih razgovora za značku u zaglavlju.
let neprocitano = 0;
const slusatelji = new Set<() => void>();
export async function osvjeziNeprocitano() {
  try {
    neprocitano = (await backend.razgovori()).filter((r) => r.neprocitano).length;
  } catch {
    neprocitano = 0;
  }
  slusatelji.forEach((cb) => cb());
}
export function useNeprocitano() {
  const { ja } = useJa();
  const [, set] = useState(0);
  useEffect(() => {
    const cb = () => set((x) => x + 1);
    slusatelji.add(cb);
    if (ja) void osvjeziNeprocitano();
    const t = ja ? setInterval(osvjeziNeprocitano, 30000) : undefined;
    return () => {
      slusatelji.delete(cb);
      clearInterval(t);
    };
  }, [ja?.id]);
  return ja ? neprocitano : 0;
}

export function Poruke() {
  useEffect(() => postaviSeo('Poruke'), []);
  return (
    <MoraPrijava>
      <PopisRazgovora />
    </MoraPrijava>
  );
}

function PopisRazgovora() {
  const r = useUcitaj(() => backend.razgovori(), []);
  return (
    <>
      <h1>Poruke</h1>
      {r.greska && <Greska poruka={r.greska} ponovno={r.ponovno} />}
      {r.ucitava && !r.podaci && <Ucitavanje />}
      {r.podaci?.length === 0 && (
        <div class="prazno ploca">
          Još nemaš poruka. Kad nekome pišeš o oglasu ili netko piše tebi, razgovor će biti ovdje.
        </div>
      )}
      {r.podaci?.map((s) => (
        <a class="redak" key={s.razgovor.id} href={adresa(`/poruke/${s.razgovor.id}`)} style={{ textDecoration: 'none', color: 'inherit' }}>
          <div class="slicica">{s.oglas?.slike_male[0] && <img src={s.oglas.slike_male[0]} alt="" loading="lazy" />}</div>
          <div class="tijelo">
            <div class="naslov">
              {s.neprocitano && <span class="oznaka crvena">Novo</span>} {s.oglas?.naslov ?? 'Obrisan oglas'}
            </div>
            <div class="pomoc">
              {s.sugovornik?.ime ?? 'Korisnik'} · {s.zadnja ? prije(s.zadnja.poslano) : ''}
            </div>
            <div style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{s.zadnja?.tekst}</div>
          </div>
        </a>
      ))}
    </>
  );
}

export function RazgovorStranica({ id }: { id: string }) {
  useEffect(() => postaviSeo('Razgovor'), []);
  return (
    <MoraPrijava>
      <Razgovor id={id} />
    </MoraPrijava>
  );
}

function Razgovor({ id }: { id: string }) {
  const { ja } = useJa();
  const r = useUcitaj(() => backend.razgovor(id), [id]);
  const [tekst, setTekst] = useState('');
  const [salje, setSalje] = useState(false);
  const kraj = useRef<HTMLDivElement>(null);
  const broj = r.podaci?.poruke.length ?? 0;

  useEffect(() => {
    // Nove poruke: jednostavno osvježavanje svakih 8 s dok je razgovor otvoren.
    const t = setInterval(() => document.visibilityState === 'visible' && r.ponovno(), 8000);
    return () => clearInterval(t);
  }, [id]);
  useEffect(() => {
    if (!r.podaci) return;
    kraj.current?.scrollIntoView({ block: 'end' });
    if (r.podaci.sazetak.neprocitano) {
      void backend.oznaciProcitano(id).then(osvjeziNeprocitano);
    }
  }, [broj]);

  if (r.greska) return <Greska poruka={r.greska} ponovno={r.ponovno} />;
  if (!r.podaci) return r.ucitava ? <Ucitavanje /> : <div class="prazno ploca">Razgovor nije pronađen.</div>;
  const { sazetak, poruke } = r.podaci;
  const o = sazetak.oglas;
  return (
    <div style={{ maxWidth: 720 }}>
      <a href={adresa('/poruke')}>‹ Sve poruke</a>
      <h1 style={{ marginTop: 8 }}>{sazetak.sugovornik?.ime ?? 'Korisnik'}</h1>
      {o && (
        <a class="redak" href={adresa(putOglasa(o))} style={{ textDecoration: 'none', color: 'inherit' }}>
          <div class="slicica">
            <img src={o.slike_male[0]} alt="" />
          </div>
          <div class="tijelo">
            <div class="naslov">{o.naslov}</div>
            <div>{cijenaTekst(o.cijena)}</div>
            {o.status !== 'aktivan' && <div class="pomoc">Oglas više nije aktivan.</div>}
          </div>
        </a>
      )}
      <div class="razgovor" aria-live="polite">
        {poruke.map((p) => (
          <div key={p.id} class={`mjehur ${p.posiljatelj_id === ja?.id ? 'moj' : ''}`}>
            {p.tekst}
            <time dateTime={p.poslano}>
              {datum(p.poslano)} {new Date(p.poslano).toLocaleTimeString('hr-HR', { hour: '2-digit', minute: '2-digit' })}
            </time>
          </div>
        ))}
        <div ref={kraj} />
      </div>
      <form
        class="unos-poruke"
        onSubmit={async (e) => {
          e.preventDefault();
          if (!tekst.trim()) return;
          setSalje(true);
          try {
            await backend.posalji(id, tekst);
            setTekst('');
            r.ponovno();
          } catch (err) {
            obavijest((err as Error).message);
          } finally {
            setSalje(false);
          }
        }}
      >
        <label class="sr-only" for="poruka">
          Poruka
        </label>
        <textarea
          id="poruka"
          maxLength={2000}
          placeholder="Napiši poruku…"
          value={tekst}
          onInput={(e) => setTekst(e.currentTarget.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && !e.shiftKey) {
              e.preventDefault();
              (e.currentTarget.form as HTMLFormElement).requestSubmit();
            }
          }}
        />
        <button class="gumb glavni" type="submit" disabled={salje || !tekst.trim()}>
          Pošalji
        </button>
      </form>
      <SigurnaKupnja />
    </div>
  );
}

export function Favoriti() {
  useEffect(() => postaviSeo('Favoriti'), []);
  return (
    <MoraPrijava>
      <FavoritiSadrzaj />
    </MoraPrijava>
  );
}

function FavoritiSadrzaj() {
  const r = useUcitaj(() => backend.favoriti(), []);
  return (
    <>
      <h1>Favoriti</h1>
      {r.greska && <Greska poruka={r.greska} ponovno={r.ponovno} />}
      {r.ucitava && !r.podaci && <Ucitavanje />}
      {r.podaci?.length === 0 && <div class="prazno ploca">Još nisi spremio nijedan oglas. Dodirni ♡ na oglasu.</div>}
      {r.podaci && r.podaci.length > 0 && <Mreza oglasi={r.podaci} />}
    </>
  );
}

export function KorisnikStranica({ id }: { id: string }) {
  const r = useUcitaj(async () => {
    const [profil, oglasi] = await Promise.all([backend.profil(id), backend.trazi({ korisnik: id }, 0)]);
    return { profil, oglasi };
  }, [id]);
  useEffect(() => {
    if (r.podaci?.profil) postaviSeo(`${r.podaci.profil.ime} – oglasi`);
  }, [r.podaci?.profil?.id]);
  if (r.greska) return <Greska poruka={r.greska} ponovno={r.ponovno} />;
  if (!r.podaci) return <Ucitavanje />;
  const { profil, oglasi } = r.podaci;
  if (!profil) return <div class="prazno ploca">Korisnik nije pronađen.</div>;
  return (
    <>
      <h1>{profil.ime}</h1>
      <p class="pomoc">
        Član od {datum(profil.registriran)}
        {profil.grad ? ` · ${profil.grad}` : ''} · {oglasi.ukupno} aktivnih oglasa
      </p>
      {oglasi.stavke.length === 0 ? <div class="prazno ploca">Nema aktivnih oglasa.</div> : <Mreza oglasi={oglasi.stavke} />}
    </>
  );
}
