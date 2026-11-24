'use client';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useState } from 'react';
import { imaBazu } from '@/lib/config';
import { IK } from '@/lib/ikone';
import { RAZLOZI_PRIJAVE, type RazlogPrijave } from '@/lib/kategorije';
import { porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';
import { Dijalog } from './Dijalog';
import { Ikona } from './Ikona';
import { useJezik } from './Jezik';
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
  const trenutna = usePathname();
  const { j, t, put } = useJezik();
  const [uid, setUid] = useState<string | null | undefined>(undefined);
  const [razgovorId, setRazgovorId] = useState<string | null>(null);
  const [favorit, setFavorit] = useState(false);
  const [tekst, setTekst] = useState(t('Pozdrav, zanima me "{naslov}". Je li još dostupno?', { naslov: oglas.naslov }));
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
    let ziv = true;
    sb.auth.getSession().then(async ({ data }) => {
      const id = data.session?.user.id ?? null;
      if (!ziv) return;
      setUid(id);
      if (!id || id === oglas.korisnik_id) return;
      const [r, f] = await Promise.all([
        sb.from('oglasnik_razgovori').select('id').eq('oglas_id', oglas.id).eq('kupac_id', id).maybeSingle(),
        sb.from('oglasnik_favoriti').select('oglas_id').eq('korisnik_id', id).eq('oglas_id', oglas.id).maybeSingle(),
      ]);
      if (!ziv) return;
      setRazgovorId((r.data as { id: string } | null)?.id ?? null);
      setFavorit(!!f.data);
    });
    return () => { ziv = false; };
  }, [oglas.id, oglas.korisnik_id]);

  const natrag = `${put('/prijava')}?natrag=${encodeURIComponent(trenutna)}`;
  if (uid === undefined) return <div className="ploca ucitavanje" aria-busy="true">{t('Učitavam…')}</div>;
  if (uid && uid === oglas.korisnik_id) {
    return (
      <div className="ploca stog">
        <h2>{t('Tvoj oglas')}</h2>
        <VlasnikAkcije oglasId={oglas.id} status={oglas.status} istekao={oglas.nedostupan && oglas.status === 'aktivan'} cijena={oglas.cijena} />
      </div>
    );
  }

  async function posalji() {
    if (!uid || salje) return;
    setSalje(true);
    setGreska('');
    const sb = klijentPreglednika();
    let id = razgovorId;
    if (!id) {
      const r = await sb.from('oglasnik_razgovori').insert({ oglas_id: oglas.id, kupac_id: uid, prodavatelj_id: oglas.korisnik_id }).select('id').single();
      if (r.error) {
        setSalje(false);
        return setGreska(porukaGreske(r.error.message, j));
      }
      id = (r.data as { id: string }).id;
      setRazgovorId(id);
    }
    const p = await sb.from('oglasnik_poruke').insert({ razgovor_id: id, posiljatelj_id: uid, tekst: tekst.trim() });
    setSalje(false);
    if (p.error) return setGreska(porukaGreske(p.error.message, j));
    router.push(put(`/poruke/${id}`));
  }

  async function prebaciFavorit() {
    if (!uid) return router.push(natrag);
    const novo = !favorit;
    setFavorit(novo); // odmah u sučelju, bez čekanja baze
    const sb = klijentPreglednika();
    const r = novo
      ? await sb.from('oglasnik_favoriti').upsert({ korisnik_id: uid, oglas_id: oglas.id })
      : await sb.from('oglasnik_favoriti').delete().eq('korisnik_id', uid).eq('oglas_id', oglas.id);
    if (r.error) {
      setFavorit(!novo);
      return setInfo(porukaGreske(r.error.message, j));
    }
    setInfo(novo ? t('Spremljeno u favorite.') : t('Uklonjeno iz favorita.'));
  }

  return (
    <div className="stog">
      {!oglas.nedostupan && (
        <div className="ploca stog" id="kontakt">
          {!uid ? (
            <>
              <Link className="gumb glavni sirok" href={natrag}>{t('Kontaktiraj prodavatelja')}</Link>
              <p className="pomoc">{t('Za slanje poruke prijavi se (Googleom ili e-mailom) ili napravi račun.')}</p>
            </>
          ) : razgovorId ? (
            <Link className="gumb glavni sirok" href={put(`/poruke/${razgovorId}`)}>{t('Otvori razgovor')}</Link>
          ) : (
            <form onSubmit={(e) => { e.preventDefault(); void posalji(); }}>
              <h2>{t('Kontaktiraj prodavatelja')}</h2>
              <label className="polje"><span>{t('Poruka')}</span>
                <textarea value={tekst} maxLength={2000} onChange={(e) => setTekst(e.target.value)} />
              </label>
              {greska && <div className="greska" role="alert">{greska}</div>}
              <button className="gumb glavni sirok" type="submit" disabled={salje || !tekst.trim()}>{salje ? t('Šaljem…') : t('Pošalji poruku')}</button>
            </form>
          )}
          {oglas.prikazi_telefon && uid && (
            telefon ? <a className="gumb sirok" href={`tel:${telefon.replace(/[^\d+]/g, '')}`}>{telefon}</a>
            : telefon === null ? <p className="pomoc">{t('Prodavatelj nije upisao broj telefona.')}</p>
            : <button className="gumb sirok" type="button" onClick={async () => {
                const r = await klijentPreglednika().rpc('oglasnik_telefon', { p_oglas: oglas.id });
                if (r.error) return setInfo(porukaGreske(r.error.message, j));
                setTelefon((r.data as string | null) ?? null);
              }}>{t('Prikaži telefon')}</button>
          )}
        </div>
      )}
      {info && <div className="pomoc" role="status">{info}</div>}
      <div className="gumbi">
        <button className={`gumb malen ${favorit ? 'aktivan' : ''}`} type="button" aria-pressed={favorit} onClick={prebaciFavorit}>
          <Ikona k={favorit ? IK.favorite : IK.favoriteBorder} velicina={18} /> {favorit ? t('Spremljeno') : t('Spremi')}
        </button>
        <button className="gumb malen" type="button" onClick={async () => {
          const url = location.href;
          try {
            if (navigator.share) await navigator.share({ title: oglas.naslov, url });
            else { await navigator.clipboard.writeText(url); setInfo(t('Poveznica je kopirana.')); }
          } catch { /* odustao */ }
        }}><Ikona k={IK.share} velicina={18} /> {t('Podijeli')}</button>
        <button className="gumb malen opasno" type="button" onClick={() => (uid ? setPrijava(true) : router.push(natrag))}>
          <Ikona k={IK.flagOutlined} velicina={18} /> {t('Prijavi oglas')}
        </button>
      </div>
      {prijava && (
        <Dijalog naslov={t('Prijavi oglas')} onZatvori={() => setPrijava(false)}>
          <form onSubmit={async (e) => {
            e.preventDefault();
            const r = await klijentPreglednika().from('oglasnik_prijave').insert({ oglas_id: oglas.id, prijavitelj_id: uid, razlog, napomena: napomena.trim().slice(0, 1000) });
            if (r.error) return setGreska(porukaGreske(r.error.message, j));
            setPrijava(false);
            setInfo(t('Hvala! Prijava je poslana moderatorima.'));
          }}>
            <fieldset className="polje">
              <legend>{t('Razlog')}</legend>
              {RAZLOZI_PRIJAVE.map((r) => (
                <label className="kvacica" key={r.kljuc}>
                  <input type="radio" name="razlog" value={r.kljuc} checked={razlog === r.kljuc} onChange={() => setRazlog(r.kljuc)} />
                  {t(r.naziv)}
                </label>
              ))}
            </fieldset>
            <label className="polje"><span>{t('Napomena (neobavezno)')}</span>
              <textarea maxLength={1000} value={napomena} onChange={(e) => setNapomena(e.target.value)} />
            </label>
            {greska && <div className="greska" role="alert">{greska}</div>}
            <div className="gumbi">
              <button className="gumb glavni" type="submit">{t('Pošalji prijavu')}</button>
              <button className="gumb" type="button" onClick={() => setPrijava(false)}>{t('Odustani')}</button>
            </div>
          </form>
        </Dijalog>
      )}
    </div>
  );
}
