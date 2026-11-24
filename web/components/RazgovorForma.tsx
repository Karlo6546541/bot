'use client';
import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';
import { IK } from '@/lib/ikone';
import { Ikona } from './Ikona';
import { useJezik } from './Jezik';

export function RazgovorForma(props: {
  razgovorId: string;
  uid: string;
  neprocitano: boolean;
  poruke: { id: string; moja: boolean; tekst: string; vrijeme: string }[];
}) {
  const router = useRouter();
  const { j, t } = useJezik();
  const [tekst, setTekst] = useState('');
  const [salje, setSalje] = useState(false);
  const [greska, setGreska] = useState('');
  const [moje, setMoje] = useState<{ id: string; tekst: string }[]>([]);
  const kraj = useRef<HTMLDivElement>(null);
  useEffect(() => {
    // Nove poruke: osvježavanje svakih 8 s dok je razgovor otvoren.
    const t = setInterval(() => document.visibilityState === 'visible' && router.refresh(), 8000);
    return () => clearInterval(t);
  }, [router]);
  useEffect(() => {
    kraj.current?.scrollIntoView({ block: 'end' });
    if (props.neprocitano) void klijentPreglednika().rpc('oglasnik_procitano', { p_razgovor: props.razgovorId });
  }, [props.poruke.length, moje.length, props.neprocitano, props.razgovorId]);
  return (
    <>
      <div className="razgovor" aria-live="polite">
        {props.poruke.map((p) => (
          <div key={p.id} className={`mjehur ${p.moja ? 'moj' : ''}`}>{p.tekst}<time>{p.vrijeme}</time></div>
        ))}
        {moje.filter((m) => !props.poruke.some((p) => p.moja && p.tekst === m.tekst)).map((m) => (
          <div key={m.id} className="mjehur moj">{m.tekst}<time>{t('Šaljem…')}</time></div>
        ))}
        <div ref={kraj} />
      </div>
      <form className="unos-poruke" onSubmit={async (e) => {
        e.preventDefault();
        if (!tekst.trim()) return;
        const poslano = tekst.trim();
        const privremeni = `p-${Date.now()}`;
        setSalje(true);
        setGreska('');
        setTekst('');
        setMoje((x) => [...x, { id: privremeni, tekst: poslano }]);
        const r = await klijentPreglednika().from('oglasnik_poruke').insert({ razgovor_id: props.razgovorId, posiljatelj_id: props.uid, tekst: poslano });
        setSalje(false);
        if (r.error) {
          setMoje((x) => x.filter((m) => m.id !== privremeni));
          setTekst(poslano);
          return setGreska(porukaGreske(r.error.message, j));
        }
        router.refresh();
      }}>
        <label className="sr-only" htmlFor="poruka">{t('Poruka')}</label>
        <textarea id="poruka" maxLength={2000} placeholder={t('Napiši poruku…')} value={tekst} onChange={(e) => setTekst(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); e.currentTarget.form?.requestSubmit(); } }} />
        <button className="posalji" type="submit" disabled={salje || !tekst.trim()} aria-label={t('Pošalji')}><Ikona k={IK.send} /></button>
      </form>
      {greska && <div className="greska" role="alert">{greska}</div>}
    </>
  );
}
