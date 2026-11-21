'use client';
import { useRouter } from 'next/navigation';
import { Fragment, useEffect, useState } from 'react';
import { ISTEK_DANA, MAX_SLIKA } from '@/lib/config';
import { KATEGORIJE, STANJA, kategorija } from '@/lib/kategorije';
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
  const kat = kategorija(nacrt.kategorija);
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
      setGreska((e as Error).message || 'Slika se ne može učitati.');
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
      if (!u.user) throw new Error('Prijavi se za nastavak.');
      const uid = u.user.id;
      const n = ocistiNacrt(konacni());
      const id = oglas?.id ?? crypto.randomUUID();
      if (n.prikazi_telefon && telefon.trim()) {
        const t = await sb.from('oglasnik_privatno').upsert({ id: uid, telefon: telefon.trim() });
        if (t.error) throw new Error(t.error.message);
      }
      const velike: string[] = [];
      const male: string[] = [];
      const oznaka = Date.now().toString(36);
      for (const [i, s] of slike.entries()) {
        if (s.vrsta === 'postojeca') { velike.push(s.url); male.push(s.mala); continue; }
        const ext = s.velika.type === 'image/jpeg' ? 'jpg' : 'webp';
        for (const [blob, ime, popis] of [[s.velika, `${oznaka}-${i}.${ext}`, velike], [s.mala, `${oznaka}-${i}-m.${ext}`, male]] as const) {
          const put = `${uid}/${id}/${ime}`;
          const up = await sb.storage.from('oglasnik-slike').upload(put, blob, { contentType: blob.type || 'image/webp', upsert: true, cacheControl: '31536000' });
          if (up.error) throw new Error(up.error.message);
          popis.push(sb.storage.from('oglasnik-slike').getPublicUrl(put).data.publicUrl);
        }
      }
      const red = { ...n, slike: velike, slike_male: male };
      const r = oglas
        ? await sb.from('oglasnik_oglasi').update(red).eq('id', id).select('id,naslov').single()
        : await sb.from('oglasnik_oglasi').insert({ ...red, id, korisnik_id: uid }).select('id,naslov').single();
      if (r.error) throw new Error(r.error.message);
      router.push(putOglasa(r.data as { id: string; naslov: string }));
      router.refresh();
    } catch (e) {
      setGreska(porukaGreske((e as Error).message));
    } finally {
      setSprema(false);
    }
  }

  const G = ({ k }: { k: string }) => (greske[k] ? <div className="greska-polja">{greske[k]}</div> : null);

  if (korak === 'pregled') {
    const n = konacni();
    return (
      <div className="stog" style={{ maxWidth: 720 }}>
        <div className="koraci"><span>1. Podaci</span>›<span className="aktivan">2. Pregled</span></div>
        <h1>Pregled oglasa</h1>
        <p className="pomoc">Ovako će oglas vidjeti kupci. Provjeri podatke prije objave.</p>
        <div className="ploca stog" data-pregled>
          <div className="galerija">
            <div className="glavna">{/* eslint-disable-next-line @next/next/no-img-element */}<img src={slike[0]?.pregled} alt="" /></div>
          </div>
          <div className="pomoc">{kat?.naziv}</div>
          <h2>{n.naslov}</h2>
          <div className="velika-cijena">{cijenaTekst(n.cijena)}</div>
          <dl className="svojstva">
            <dt>Stanje</dt><dd>{n.stanje}</dd>
            {kat?.polja.map((p) => (n.polja[p.kljuc]?.trim() ? <Fragment key={p.kljuc}><dt>{p.naziv}</dt><dd>{n.polja[p.kljuc]}</dd></Fragment> : null))}
            <dt>Lokacija</dt><dd>{lokacijaTekst({ drzava: n.drzava, zupanija: n.zupanija?.trim() || null, grad: n.grad.trim() })}</dd>
            <dt>Telefon</dt><dd>{n.prikazi_telefon ? telefon || 'nije upisan' : 'ne prikazuje se'}</dd>
          </dl>
          <p className="opis">{n.opis}</p>
        </div>
        {!oglas && <p className="pomoc">Oglas je aktivan {ISTEK_DANA} dana; poslije ga možeš produljiti.</p>}
        {greska && <div className="greska" role="alert">{greska}</div>}
        <div className="gumbi">
          <button className="gumb glavni" type="button" disabled={sprema} onClick={objavi}>{sprema ? 'Spremam…' : oglas ? 'Spremi promjene' : 'Objavi oglas'}</button>
          <button className="gumb" type="button" disabled={sprema} onClick={() => setKorak('obrazac')}>← Natrag na uređivanje</button>
        </div>
      </div>
    );
  }

  return (
    <form className="stog" style={{ maxWidth: 720 }} onSubmit={naPregled} noValidate>
      <div className="koraci"><span className="aktivan">1. Podaci</span>›<span>2. Pregled</span></div>
      <h1>{oglas ? 'Uredi oglas' : 'Objavi oglas'}</h1>
      <div className="ploca">
        <fieldset className="polje" data-polje="slike">
          <legend>Fotografije ({slike.length}/{MAX_SLIKA}): barem jedna</legend>
          <div className="slike-obrazac">
            {slike.map((s, i) => (
              <div className="slot" key={s.kljuc}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={s.pregled} alt={`Fotografija ${i + 1}`} />
                {i === 0 && <span className="oznaka prva">Naslovna</span>}
                <button type="button" className="ukloni" aria-label={`Ukloni fotografiju ${i + 1}`} onClick={() => setSlike((x) => x.filter((_, j) => j !== i))}>✕</button>
              </div>
            ))}
            {slike.length < MAX_SLIKA && (
              <label className="slot dodaj-sliku">
                <b aria-hidden="true">+</b>{obrada ? 'Obrađujem…' : 'Dodaj'}
                <input className="sr-only" type="file" accept="image/*" multiple data-unos-slika onChange={(e) => { void dodajSlike(e.target.files); e.target.value = ''; }} />
              </label>
            )}
          </div>
          <G k="slike" />
          <div className="pomoc">Slike se smanjuju prije slanja. Prva je naslovna.</div>
        </fieldset>
      </div>
      <div className="ploca">
        <label className="polje" data-polje="naslov"><span>Naslov</span>
          <input type="text" name="naslov" maxLength={100} value={nacrt.naslov} placeholder="npr. Charizard Base Set 4/102" onChange={(e) => postavi({ naslov: e.target.value })} />
          <G k="naslov" />
        </label>
        <label className="polje" data-polje="kategorija"><span>Kategorija</span>
          <select name="kategorija" value={nacrt.kategorija} onChange={(e) => postavi({ kategorija: e.target.value, polja: {} })}>
            <option value="">Odaberi…</option>
            {KATEGORIJE.map((k) => <option key={k.slug} value={k.slug}>{k.naziv}</option>)}
          </select>
          <G k="kategorija" />
        </label>
        {kat && kat.polja.length > 0 && (
          <div className="dva-stupca">
            {kat.polja.map((p) => (
              <label className="polje" key={p.kljuc} data-polje={`p_${p.kljuc}`}><span>{p.naziv} (neobavezno)</span>
                {p.tip === 'izbor' ? (
                  <select name={`p_${p.kljuc}`} value={nacrt.polja[p.kljuc] ?? ''} onChange={(e) => postavi({ polja: { ...nacrt.polja, [p.kljuc]: e.target.value } })}>
                    <option value="">–</option>
                    {p.opcije.map((o) => <option key={o}>{o}</option>)}
                  </select>
                ) : (
                  <input type={p.tip === 'broj' ? 'number' : 'text'} name={`p_${p.kljuc}`} placeholder={p.tip === 'tekst' ? p.placeholder : undefined} value={nacrt.polja[p.kljuc] ?? ''} onChange={(e) => postavi({ polja: { ...nacrt.polja, [p.kljuc]: e.target.value } })} />
                )}
                <G k={`p_${p.kljuc}`} />
              </label>
            ))}
          </div>
        )}
        <fieldset className="polje" data-polje="stanje">
          <legend>Stanje</legend>
          <div className="gumbi">
            {STANJA.map((s) => (
              <label className="kvacica" key={s} style={{ marginRight: 8 }}>
                <input type="radio" name="stanje" value={s} checked={nacrt.stanje === s} onChange={() => postavi({ stanje: s })} />{s}
              </label>
            ))}
          </div>
          <G k="stanje" />
        </fieldset>
        <label className="polje" data-polje="opis"><span>Opis</span>
          <textarea name="opis" maxLength={5000} value={nacrt.opis} placeholder="Stanje, izdanje, nedostaci, što je uključeno…" onChange={(e) => postavi({ opis: e.target.value })} />
          <G k="opis" />
        </label>
      </div>
      <div className="ploca">
        <fieldset className="polje" data-polje="cijena">
          <legend>Cijena</legend>
          <div className="dva-stupca">
            <label className="polje" style={{ marginBottom: 0 }}><span className="sr-only">Cijena u eurima</span>
              <input type="number" name="cijena" inputMode="decimal" min={0} step="0.01" placeholder="€" disabled={dogovor} value={dogovor ? '' : cijenaTxt} onChange={(e) => setCijenaTxt(e.target.value)} />
            </label>
            <label className="kvacica"><input type="checkbox" name="dogovor" checked={dogovor} onChange={(e) => setDogovor(e.target.checked)} />Dogovor</label>
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
          Prikaži moj broj telefona prijavljenim korisnicima
        </label>
        {nacrt.prikazi_telefon && (
          <label className="polje"><span>Broj telefona</span>
            <input type="tel" maxLength={30} value={telefon} onChange={(e) => setTelefon(e.target.value)} />
          </label>
        )}
      </div>
      <SigurnaKupnja />
      {greska && <div className="greska" role="alert">{greska}</div>}
      <button className="gumb glavni sirok" type="submit" disabled={obrada}>Pregled oglasa →</button>
    </form>
  );
}
