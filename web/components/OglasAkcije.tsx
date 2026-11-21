'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { imaBazu } from '@/lib/config';
import { RAZLOZI_PRIJAVE, type RazlogPrijave } from '@/lib/kategorije';
import { porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';
import { Dijalog } from './Dijalog';
import { VlasnikAkcije } from './VlasnikAkcije';

interface Sazetak {
  id: string;
  naslov: string;
  korisnik_id: string;
  status: string;
  prikazi_telefon: boolean;
  cijena: number | null;
  nedostupan: boolean;
}

/** Dio stranice oglasa koji ovisi o prijavi (kontakt, favorit, prijava, radnje vlasnika). Stranica je keširana, ovo se učitava u pregledniku. */
export function OglasAkcije({ oglas }: { oglas: Sazetak }) {
  const router = useRouter();
  const put = usePathname();
  const [uid, setUid] = useState<string | null | undefined>(undefined);
  const [razgovorId, setRazgovorId] = useState<string | null>(null);
  const [favorit, setFavorit] = useState(false);
  const [tekst, setTekst] = useState(`Pozdrav, zanima me "${oglas.naslov}". Je li još dostupno?`);
  const [telefon, setTelefon] = useState<string | null | undefined>(undefined);
  const [salje, setSalje] = useState(false);
  const [greska, setGreska] = useState('');
  const [prijava, setPrijava] = useState(false);
  const [razlog, setRazlog] = useState<RazlogPrijave>('prevara');
  const [napomena, setNapomena] = useState('');
  const [info, setInfo] = useState('');

  useEffect(() => {
    if (!imaBazu()) return setUid(null);
    const sb = klijentPreglednika();
    sb.auth.getSession().then(async ({ data }) => {
      const id = data.session?.user.id ?? null;
      setUid(id);
      if (!id) return;
      const [r, f] = await Promise.all([
        sb.from('oglasnik_razgovori').select('id').eq('oglas_id', oglas.id).eq('kupac_id', id).maybeSingle(),
        sb.from('oglasnik_favoriti').select('oglas_id').eq('korisnik_id', id).eq('oglas_id', oglas.id).maybeSingle(),
      ]);
      setRazgovorId((r.data as { id: string } | null)?.id ?? null);
      setFavorit(!!f.data);
    });
  }, [oglas.id]);

  const natrag = `/prijava?natrag=${encodeURIComponent(put)}`;
  if (uid === undefined) return <div className="ploca" aria-busy="true">Učitavam…</div>;
  if (uid && uid === oglas.korisnik_id) {
    return (
      <div className="ploca stog">
        <h2>Tvoj oglas</h2>
        <VlasnikAkcije oglasId={oglas.id} status={oglas.status} istekao={oglas.nedostupan && oglas.status === 'aktivan'} cijena={oglas.cijena} />
      </div>
    );
  }

  async function posalji() {
    if (!uid) return;
    setSalje(true);
    setGreska('');
    const sb = klijentPreglednika();
    let id = razgovorId;
    if (!id) {
      const r = await sb.from('oglasnik_razgovori').insert({ oglas_id: oglas.id, kupac_id: uid, prodavatelj_id: oglas.korisnik_id }).select('id').single();
      if (r.error) {
        setSalje(false);
        return setGreska(porukaGreske(r.error.message));
      }
      id = (r.data as { id: string }).id;
    }
    const p = await sb.from('oglasnik_poruke').insert({ razgovor_id: id, posiljatelj_id: uid, tekst: tekst.trim() });
    setSalje(false);
    if (p.error) return setGreska(porukaGreske(p.error.message));
    router.push(`/poruke/${id}`);
  }

  async function prebaciFavorit() {
    if (!uid) return router.push(natrag);
    const sb = klijentPreglednika();
    const r = favorit
      ? await sb.from('oglasnik_favoriti').delete().eq('korisnik_id', uid).eq('oglas_id', oglas.id)
      : await sb.from('oglasnik_favoriti').upsert({ korisnik_id: uid, oglas_id: oglas.id });
    if (r.error) return setInfo(porukaGreske(r.error.message));
    setFavorit(!favorit);
    setInfo(favorit ? 'Uklonjeno iz favorita.' : 'Spremljeno u favorite.');
  }

  return (
    <div className="stog">
      {!oglas.nedostupan && (
        <div className="ploca stog" id="kontakt">
          {!uid ? (
            <>
              <Link className="gumb glavni sirok" href={natrag}>Kontaktiraj prodavatelja</Link>
              <p className="pomoc">Za slanje poruke prijavi se (Googleom ili e-mailom) ili napravi račun.</p>
            </>
          ) : razgovorId ? (
            <Link className="gumb glavni sirok" href={`/poruke/${razgovorId}`}>Otvori razgovor</Link>
          ) : (
            <form onSubmit={(e) => { e.preventDefault(); void posalji(); }}>
              <h2>Kontaktiraj prodavatelja</h2>
              <label className="polje"><span>Poruka</span>
                <textarea value={tekst} maxLength={2000} onChange={(e) => setTekst(e.target.value)} />
              </label>
              {greska && <div className="greska" role="alert">{greska}</div>}
              <button className="gumb glavni sirok" type="submit" disabled={salje || !tekst.trim()}>{salje ? 'Šaljem…' : 'Pošalji poruku'}</button>
            </form>
          )}
          {oglas.prikazi_telefon && uid && (
            telefon ? <a className="gumb sirok" href={`tel:${telefon.replace(/[^\d+]/g, '')}`}>📞 {telefon}</a>
            : telefon === null ? <p className="pomoc">Prodavatelj nije upisao broj telefona.</p>
            : <button className="gumb sirok" type="button" onClick={async () => {
                const r = await klijentPreglednika().rpc('oglasnik_telefon', { p_oglas: oglas.id });
                if (r.error) return setInfo(porukaGreske(r.error.message));
                setTelefon((r.data as string | null) ?? null);
              }}>📞 Prikaži telefon</button>
          )}
        </div>
      )}
      {info && <div className="pomoc" role="status">{info}</div>}
      <div className="gumbi">
        <button className="gumb malen" type="button" aria-pressed={favorit} onClick={prebaciFavorit}>{favorit ? '♥ Spremljeno' : '♡ Spremi'}</button>
        <button className="gumb malen" type="button" onClick={async () => {
          const url = location.href;
          try {
            if (navigator.share) await navigator.share({ title: oglas.naslov, url });
            else { await navigator.clipboard.writeText(url); setInfo('Poveznica je kopirana.'); }
          } catch { /* odustao */ }
        }}>↗ Podijeli</button>
        <button className="gumb malen opasno" type="button" onClick={() => (uid ? setPrijava(true) : router.push(natrag))}>🚩 Prijavi oglas</button>
      </div>
      {prijava && (
        <Dijalog naslov="Prijavi oglas" onZatvori={() => setPrijava(false)}>
          <form onSubmit={async (e) => {
            e.preventDefault();
            const r = await klijentPreglednika().from('oglasnik_prijave').insert({ oglas_id: oglas.id, prijavitelj_id: uid, razlog, napomena: napomena.trim().slice(0, 1000) });
            if (r.error) return setGreska(porukaGreske(r.error.message));
            setPrijava(false);
            setInfo('Hvala! Prijava je poslana moderatorima.');
          }}>
            <fieldset className="polje">
              <legend>Razlog</legend>
              {RAZLOZI_PRIJAVE.map((r) => (
                <label className="kvacica" key={r.kljuc}>
                  <input type="radio" name="razlog" value={r.kljuc} checked={razlog === r.kljuc} onChange={() => setRazlog(r.kljuc)} />
                  {r.naziv}
                </label>
              ))}
            </fieldset>
            <label className="polje"><span>Napomena (neobavezno)</span>
              <textarea maxLength={1000} value={napomena} onChange={(e) => setNapomena(e.target.value)} />
            </label>
            {greska && <div className="greska" role="alert">{greska}</div>}
            <div className="gumbi">
              <button className="gumb glavni" type="submit">Pošalji prijavu</button>
              <button className="gumb" type="button" onClick={() => setPrijava(false)}>Odustani</button>
            </div>
          </form>
        </Dijalog>
      )}
    </div>
  );
}
