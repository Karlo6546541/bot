'use client';
import { useRouter } from 'next/navigation';
import { Fragment, useEffect, useState } from 'react';
import { ISTEK_DANA, MAX_SLIKA } from '@/lib/config';
import { SEKCIJE, STANJA, nazivNa, poljaKategorije, podkategorija } from '@/lib/kategorije';
import { Traka } from './Traka';
import { useJezik } from './Jezik';
import { osvjeziStranice } from '@/lib/osvjezi';
import { osigurajProfil, porukaGreske } from '@/lib/korisnik';
import { lokacijaTekst } from '@/lib/lokacije';
import { ocistiNacrt, provjeriOglas } from '@/lib/provjera';
import { putOglasa } from '@/lib/seo';
import { pripremiSliku } from '@/lib/slike';
import { klijentPreglednika } from '@/lib/supabase';
import { cijenaTekst } from '@/lib/tekst';
import type { NacrtOglasa, Oglas } from '@/lib/types';
import { LokacijaPolja } from './LokacijaPolja';
import { SigurnaKupnja } from './SigurnaKupnja';

type Slika = { kljuc: string; pregled: string } & ({ vrsta: 'postojeca'; url: string; mala: string } | { vrsta: 'nova'; velika: Blob; mala: Blob });

export function ObjaviForma({ oglas }: { oglas?: Oglas }) {
  const router = useRouter();
  const { j, t, put: putJ } = useJezik();
  const [nacrt, setNacrt] = useState<NacrtOglasa>(() => ({
    naslov: oglas?.naslov ?? '',
    kategorija: oglas?.kategorija ?? '',
    opis: oglas?.opis ?? '',
    cijena: oglas?.cijena ?? null,
    drzava: oglas?.drzava ?? 'HR',
    zupanija: oglas?.zupanija ?? '',
    grad: oglas?.grad ?? '',
    stanje: oglas?.stanje ?? '',
    polja: oglas?.polja ?? {},
    prikazi_telefon: oglas?.prikazi_telefon ?? false,
  }));
  const [cijenaTxt, setCijenaTxt] = useState(oglas?.cijena != null ? String(oglas.cijena) : '');
  const [dogovor, setDogovor] = useState(oglas ? oglas.cijena == null : false);
  const [slike, setSlike] = useState<Slika[]>(() => (oglas?.slike ?? []).map((url, i) => ({ vrsta: 'postojeca', url, mala: oglas!.slike_male[i], pregled: oglas!.slike_male[i], kljuc: url })));
  const [telefon, setTelefon] = useState('');
  const [korak, setKorak] = useState<'obrazac' | 'pregled'>('obrazac');
  const [greske, setGreske] = useState<Record<string, string>>({});
  const [greska, setGreska] = useState('');
  const [obrada, setObrada] = useState(false);
  const [sprema, setSprema] = useState(false);
  const kat = podkategorija(nacrt.kategorija);
  const polja = poljaKategorije(nacrt.kategorija);
  const postavi = (p: Partial<NacrtOglasa>) => setNacrt((x) => ({ ...x, ...p }));

  // Predpopuna lokacije iz profila (samo kod novog oglasa) i telefona.
  useEffect(() => {
    const sb = klijentPreglednika();
    sb.auth.getUser().then(async ({ data }) => {
      if (!data.user) return;
      const [p, t] = await Promise.all([osigurajProfil(sb, data.user), sb.from('oglasnik_privatno').select('telefon').eq('id', data.user.id).maybeSingle()]);
      setTelefon((t.data as { telefon: string | null } | null)?.telefon ?? '');
      if (!oglas && p) setNacrt((x) => ({ ...x, drzava: p.drzava || x.drzava, grad: x.grad || p.grad || '' }));
    });
  }, [oglas]);

  const konacni = (): NacrtOglasa => {
    const c = cijenaTxt.trim().replace(',', '.');
    return { ...nacrt, cijena: dogovor ? null : c === '' ? NaN : Number(c) };
  };

  async function dodajSlike(f: FileList | null) {
    if (!f?.length) return;
    const odabrane = [...f].slice(0, MAX_SLIKA - slike.length);
    setObrada(true);
    try {
      const nove: Slika[] = [];
      for (const dat of odabrane) {
        const s = await pripremiSliku(dat);
        nove.push({ vrsta: 'nova', velika: s.velika, mala: s.mala, pregled: s.pregled, kljuc: s.pregled });
      }
      setSlike((x) => [...x, ...nove].slice(0, MAX_SLIKA));
      setGreske((g) => ({ ...g, slike: '' }));
    } catch (e) {
      setGreska(t((e as Error).message || 'Slika se ne može učitati.'));
    } finally {
      setObrada(false);
    }
  }

  function naPregled(e: React.FormEvent) {
    e.preventDefault();
    const g = provjeriOglas(konacni(), slike.length);
    if (!dogovor && cijenaTxt.trim() === '') g.cijena = 'Upiši cijenu ili odaberi "Dogovor".';
    setGreske(g);
    if (Object.keys(g).length) return void document.querySelector(`[data-polje="${Object.keys(g)[0]}"]`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
    setKorak('pregled');
    window.scrollTo(0, 0);
  }

  async function objavi() {
    setSprema(true);
    setGreska('');
    try {
      const sb = klijentPreglednika();
      const { data: u } = await sb.auth.getUser();
      if (!u.user) throw new Error(t('Prijavi se za nastavak.'));
      const uid = u.user.id;
      const n = ocistiNacrt(konacni());
      const id = oglas?.id ?? crypto.randomUUID();
      if (n.prikazi_telefon && telefon.trim()) {
        const tel = await sb.from('oglasnik_privatno').upsert({ id: uid, telefon: telefon.trim() });
        if (tel.error) throw new Error(tel.error.message);
      }
      const velike: string[] = [];
      const male: string[] = [];
      const oznaka = Date.now().toString(36);
      for (const [i, s] of slike.entries()) {
        if (s.vrsta === 'postojeca') { velike.push(s.url); male.push(s.mala); continue; }
        const ext = s.velika.type === 'image/jpeg' ? 'jpg' : 'webp';
        for (const [blob, ime, popis] of [[s.velika, `${oznaka}-${i}.${ext}`, velike], [s.mala, `${oznaka}-${i}-m.${ext}`, male]] as const) {
          const putanja = `${uid}/${id}/${ime}`;
          const up = await sb.storage.from('oglasnik-slike').upload(putanja, blob, { contentType: blob.type || 'image/webp', upsert: true, cacheControl: '31536000' });
          if (up.error) throw new Error(up.error.message);
          popis.push(sb.storage.from('oglasnik-slike').getPublicUrl(putanja).data.publicUrl);
        }
      }
      const red = { ...n, slike: velike, slike_male: male };
      const r = oglas
        ? await sb.from('oglasnik_oglasi').update(red).eq('id', id).select('id,naslov').single()
        : await sb.from('oglasnik_oglasi').insert({ ...red, id, korisnik_id: uid }).select('id,naslov').single();
      if (r.error) throw new Error(r.error.message);
      await osvjeziStranice((r.data as { id: string }).id);
      router.push(putJ(putOglasa(r.data as { id: string; naslov: string })));
      router.refresh();
    } catch (e) {
      setGreska(porukaGreske((e as Error).message, j));
    } finally {
      setSprema(false);
    }
  }

  const G = ({ k }: { k: string }) => (greske[k] ? <div className="greska-polja">{t(greske[k])}</div> : null);

  if (korak === 'pregled') {
    const n = konacni();
    return (
      <>
      <Traka naslov={t('Pregled oglasa')} natrag="/objavi" />
      <div className="stog prodaj">
        <div className="koraci"><span>1. {t('Podaci')}</span>›<span className="aktivan">2. {t('Pregled')}</span></div>
        <p className="pomoc">{t('Ovako će oglas vidjeti kupci. Provjeri podatke prije objave.')}</p>
        <div className="ploca stog" data-pregled>
          <div className="galerija">
            <div className="glavna">{/* eslint-disable-next-line @next/next/no-img-element */}<img src={slike[0]?.pregled} alt="" /></div>
          </div>
          <div className="pomoc">{kat ? nazivNa(kat, j) : ''}</div>
          <h2>{n.naslov}</h2>
          <div className="velika-cijena">{cijenaTekst(n.cijena, j)}</div>
          <dl className="svojstva">
            <dt>{t('Stanje')}</dt><dd>{t(n.stanje)}</dd>
            {poljaKategorije(n.kategorija).map((p) => (n.polja[p.kljuc]?.trim() ? <Fragment key={p.kljuc}><dt>{t(p.naziv)}</dt><dd>{t(n.polja[p.kljuc])}</dd></Fragment> : null))}
            <dt>{t('Lokacija')}</dt><dd>{lokacijaTekst({ drzava: n.drzava, zupanija: n.zupanija?.trim() || null, grad: n.grad.trim() }, true, j)}</dd>
            <dt>{t('Telefon')}</dt><dd>{n.prikazi_telefon ? telefon || t('nije upisan') : t('ne prikazuje se')}</dd>
          </dl>
          <p className="opis">{n.opis}</p>
        </div>
        {!oglas && <p className="pomoc">{t('Oglas je aktivan {n} dana; poslije ga možeš produljiti.', { n: ISTEK_DANA })}</p>}
        {greska && <div className="greska" role="alert">{greska}</div>}
        <div className="gumbi">
          <button className="gumb glavni" type="button" disabled={sprema} onClick={objavi}>{sprema ? t('Spremam…') : oglas ? t('Spremi promjene') : t('Objavi oglas')}</button>
          <button className="gumb" type="button" disabled={sprema} onClick={() => setKorak('obrazac')}>← {t('Natrag na uređivanje')}</button>
        </div>
      </div>
      </>
    );
  }

  return (
    <>
    <Traka naslov={oglas ? t('Uredi oglas') : t('Objavi oglas')} natrag={oglas ? putOglasa(oglas) : '/'} />
    <form className="stog prodaj" onSubmit={naPregled} noValidate>
      <div className="koraci"><span className="aktivan">1. {t('Podaci')}</span>›<span>2. {t('Pregled')}</span></div>
      <div className="ploca">
        <fieldset className="polje" data-polje="slike">
          <legend>{t('Fotografije ({n}/{max}): barem jedna', { n: slike.length, max: MAX_SLIKA })}</legend>
          <div className="slike-obrazac">
            {slike.map((s, i) => (
              <div className="slot" key={s.kljuc}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={s.pregled} alt={`${t('Fotografija')} ${i + 1}`} />
                {i === 0 && <span className="oznaka prva">{t('Naslovna')}</span>}
                <button type="button" className="ukloni" aria-label={`${t('Ukloni fotografiju')} ${i + 1}`} onClick={() => setSlike((x) => x.filter((_, j) => j !== i))}>✕</button>
              </div>
            ))}
            {slike.length < MAX_SLIKA && (
              <label className="slot dodaj-sliku">
                <b aria-hidden="true">+</b>{obrada ? t('Obrađujem…') : t('Dodaj')}
                <input className="sr-only" type="file" accept="image/*" multiple data-unos-slika onChange={(e) => { void dodajSlike(e.target.files); e.target.value = ''; }} />
              </label>
            )}
          </div>
          <G k="slike" />
          <div className="pomoc">{t('Slike se smanjuju prije slanja. Prva je naslovna.')}</div>
        </fieldset>
      </div>
      <div className="ploca">
        <label className="polje" data-polje="naslov"><span>{t('Naslov')}</span>
          <input type="text" name="naslov" maxLength={100} value={nacrt.naslov} placeholder={t('npr. Charizard Base Set 4/102')} onChange={(e) => postavi({ naslov: e.target.value })} />
          <G k="naslov" />
        </label>
        <label className="polje" data-polje="kategorija"><span>{t('Kategorija')}</span>
          <select name="kategorija" value={nacrt.kategorija} onChange={(e) => postavi({ kategorija: e.target.value, polja: {} })}>
            <option value="">{t('Odaberi…')}</option>
            {SEKCIJE.map((sk) => <optgroup key={sk.slug} label={nazivNa(sk, j)}>{sk.podkategorije.map((k) => <option key={k.slug} value={k.slug}>{nazivNa(k, j)}</option>)}</optgroup>)}
          </select>
          <G k="kategorija" />
        </label>
        {polja.length > 0 && (
          <div className="dva-stupca">
            {polja.map((p) => (
              <label className="polje" key={p.kljuc} data-polje={`p_${p.kljuc}`}><span>{t(p.naziv)} ({t('neobavezno')})</span>
                {p.tip === 'izbor' ? (
                  <select name={`p_${p.kljuc}`} value={nacrt.polja[p.kljuc] ?? ''} onChange={(e) => postavi({ polja: { ...nacrt.polja, [p.kljuc]: e.target.value } })}>
                    <option value="">–</option>
                    {p.opcije.map((o) => <option key={o} value={o}>{t(o)}</option>)}
                  </select>
                ) : (
                  <input type={p.tip === 'broj' ? 'number' : 'text'} name={`p_${p.kljuc}`} placeholder={p.tip === 'tekst' && p.placeholder ? t(p.placeholder) : undefined} value={nacrt.polja[p.kljuc] ?? ''} onChange={(e) => postavi({ polja: { ...nacrt.polja, [p.kljuc]: e.target.value } })} />
                )}
                <G k={`p_${p.kljuc}`} />
              </label>
            ))}
          </div>
        )}
        <fieldset className="polje" data-polje="stanje">
          <legend>{t('Stanje')}</legend>
          <div className="stanja" style={{ padding: 0 }}>
            {STANJA.map((s) => (
              <label key={s}>
                <input type="radio" name="stanje" value={s} checked={nacrt.stanje === s} onChange={() => postavi({ stanje: s })} /><span>{t(s)}</span>
              </label>
            ))}
          </div>
          <G k="stanje" />
        </fieldset>
        <label className="polje" data-polje="opis"><span>{t('Opis')}</span>
          <textarea name="opis" maxLength={5000} value={nacrt.opis} placeholder={t('Stanje, izdanje, nedostaci, što je uključeno…')} onChange={(e) => postavi({ opis: e.target.value })} />
          <G k="opis" />
        </label>
      </div>
      <div className="ploca">
        <fieldset className="polje" data-polje="cijena">
          <legend>{t('Cijena')}</legend>
          <div className="dva-stupca">
            <label className="polje" style={{ marginBottom: 0 }}><span className="sr-only">{t('Cijena u eurima')}</span>
              <input type="number" name="cijena" inputMode="decimal" min={0} step="0.01" placeholder="€" disabled={dogovor} value={dogovor ? '' : cijenaTxt} onChange={(e) => setCijenaTxt(e.target.value)} />
            </label>
            <label className="kvacica"><input type="checkbox" name="dogovor" checked={dogovor} onChange={(e) => setDogovor(e.target.checked)} />{t('Dogovor')}</label>
          </div>
          <G k="cijena" />
        </fieldset>
        <LokacijaPolja
          drzava={nacrt.drzava}
          zupanija={nacrt.zupanija ?? ''}
          grad={nacrt.grad}
          greske={greske}
          onPromjena={(v) => postavi({ drzava: v.drzava, zupanija: v.zupanija, grad: v.grad })}
        />
        <label className="kvacica">
          <input type="checkbox" checked={nacrt.prikazi_telefon} onChange={(e) => postavi({ prikazi_telefon: e.target.checked })} />
          {t('Prikaži moj broj telefona prijavljenim korisnicima')}
        </label>
        {nacrt.prikazi_telefon && (
          <label className="polje"><span>{t('Broj telefona')}</span>
            <input type="tel" maxLength={30} value={telefon} onChange={(e) => setTelefon(e.target.value)} />
          </label>
        )}
      </div>
      <SigurnaKupnja />
      {greska && <div className="greska" role="alert">{greska}</div>}
      <button className="gumb glavni sirok" type="submit" disabled={obrada}>{t('Pregled oglasa')} →</button>
    </form>
    </>
  );
}
