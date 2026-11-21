'use client';
import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { porukaGreske } from '@/lib/korisnik';
import { klijentPreglednika } from '@/lib/supabase';

export function RazgovorForma(props: {
  razgovorId: string;
  uid: string;
  neprocitano: boolean;
  poruke: { id: string; moja: boolean; tekst: string; vrijeme: string }[];
}) {
  const router = useRouter();
  const [tekst, setTekst] = useState('');
  const [salje, setSalje] = useState(false);
  const [greska, setGreska] = useState('');
  const kraj = useRef<HTMLDivElement>(null);
  useEffect(() => {
    // Nove poruke: osvježavanje svakih 8 s dok je razgovor otvoren.
    const t = setInterval(() => document.visibilityState === 'visible' && router.refresh(), 8000);
    return () => clearInterval(t);
  }, [router]);
  useEffect(() => {
    kraj.current?.scrollIntoView({ block: 'end' });
    if (props.neprocitano) void klijentPreglednika().rpc('oglasnik_procitano', { p_razgovor: props.razgovorId });
  }, [props.poruke.length, props.neprocitano, props.razgovorId]);
  return (
    <>
      <div className="razgovor" aria-live="polite">
        {props.poruke.map((p) => (
          <div key={p.id} className={`mjehur ${p.moja ? 'moj' : ''}`}>{p.tekst}<time>{p.vrijeme}</time></div>
        ))}
        <div ref={kraj} />
      </div>
      <form className="unos-poruke" onSubmit={async (e) => {
        e.preventDefault();
        if (!tekst.trim()) return;
        setSalje(true);
        setGreska('');
        const r = await klijentPreglednika().from('oglasnik_poruke').insert({ razgovor_id: props.razgovorId, posiljatelj_id: props.uid, tekst: tekst.trim() });
        setSalje(false);
        if (r.error) return setGreska(porukaGreske(r.error.message));
        setTekst('');
        router.refresh();
      }}>
        <label className="sr-only" htmlFor="poruka">Poruka</label>
        <textarea id="poruka" maxLength={2000} placeholder="Napiši poruku…" value={tekst} onChange={(e) => setTekst(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); e.currentTarget.form?.requestSubmit(); } }} />
        <button className="gumb glavni" type="submit" disabled={salje || !tekst.trim()}>Pošalji</button>
      </form>
      {greska && <div className="greska" role="alert">{greska}</div>}
    </>
  );
}
