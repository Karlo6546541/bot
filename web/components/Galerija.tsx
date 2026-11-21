'use client';
import { useState } from 'react';

/** Galerija: prva fotografija je u HTML-u (za SEO i brzinu), ostale se biraju klikom. */
export function Galerija({ naslov, slike, male }: { naslov: string; slike: string[]; male: string[] }) {
  const [i, setI] = useState(0);
  return (
    <div className="galerija">
      <div className="glavna">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={slike[i]} alt={`${naslov} – fotografija ${i + 1}`} fetchPriority={i === 0 ? 'high' : 'auto'} decoding="async" />
      </div>
      {slike.length > 1 && (
        <div className="male" role="list">
          {male.map((s, j) => (
            <button key={s} type="button" role="listitem" aria-current={i === j} aria-label={`Fotografija ${j + 1}`} onClick={() => setI(j)}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={s} alt="" loading="lazy" />
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
