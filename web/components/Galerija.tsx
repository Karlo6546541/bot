'use client';
import { useState } from 'react';
import { Slika } from './Slika';
import { useJezik } from './Jezik';

/** Galerija: prva fotografija je u HTML-u (za SEO i brzinu), ostale se biraju klikom. */
export function Galerija({ naslov, slike, male }: { naslov: string; slike: string[]; male: string[] }) {
  const [i, setI] = useState(0);
  const { t } = useJezik();
  return (
    <div className="galerija">
      <div className="glavna">
        <Slika key={slike[i]} src={slike[i]} alt={`${naslov} – ${t('fotografija')} ${i + 1}`} sizes="(min-width: 900px) 520px, 100vw" prioritet={i === 0} />
      </div>
      {slike.length > 1 && (
        <div className="male" role="list">
          {male.map((s, j) => (
            <button key={s + j} type="button" role="listitem" aria-current={i === j} aria-label={`${t('Fotografija')} ${j + 1}`} onClick={() => setI(j)}>
              <span className="mala-slika"><Slika src={s} alt="" sizes="56px" /></span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
