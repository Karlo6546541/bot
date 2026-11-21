'use client';
import { useState } from 'react';
import { DRZAVE, ZUPANIJE_HR, imaZupanije } from '@/lib/lokacije';

/**
 * Država, županija i grad. Županija je padajući popis u Hrvatskoj, a izvan nje
 * slobodno polje "regija". Koristi se u filterima (GET forma) i u obrascu za objavu.
 */
export function LokacijaPolja(props: {
  drzava?: string;
  zupanija?: string;
  grad?: string;
  filter?: boolean;
  greske?: Record<string, string>;
  onPromjena?: (v: { drzava: string; zupanija: string; grad: string }) => void;
}) {
  const [drzava, setDrzava] = useState(props.drzava ?? (props.filter ? '' : 'HR'));
  const [zupanija, setZupanija] = useState(props.zupanija ?? '');
  const [grad, setGrad] = useState(props.grad ?? '');
  const javi = (d: string, z: string, g: string) => props.onPromjena?.({ drzava: d, zupanija: z, grad: g });
  const hr = imaZupanije(drzava) || (props.filter && drzava === '');
  const G = ({ k }: { k: string }) => (props.greske?.[k] ? <div className="greska-polja">{props.greske[k]}</div> : null);
  return (
    <div className="forma-red tri">
      <label className="polje" data-polje="drzava">
        <span>Država</span>
        <select
          name="drzava"
          value={drzava}
          onChange={(e) => {
            const d = e.target.value;
            setDrzava(d);
            setZupanija('');
            javi(d, '', grad);
          }}
        >
          {props.filter && <option value="">Sve države</option>}
          {DRZAVE.map((d) => (
            <option key={d.kod} value={d.kod}>{d.naziv}</option>
          ))}
        </select>
        <G k="drzava" />
      </label>
      <label className="polje" data-polje="zupanija">
        <span>{hr ? 'Županija' : 'Regija (neobavezno)'}</span>
        {hr ? (
          <select
            name="zupanija"
            value={zupanija}
            onChange={(e) => {
              setZupanija(e.target.value);
              javi(drzava, e.target.value, grad);
            }}
          >
            <option value="">{props.filter ? 'Sve županije' : 'Odaberi…'}</option>
            {ZUPANIJE_HR.map((z) => (
              <option key={z}>{z}</option>
            ))}
          </select>
        ) : (
          <input
            type="text"
            name="zupanija"
            maxLength={60}
            value={zupanija}
            onChange={(e) => {
              setZupanija(e.target.value);
              javi(drzava, e.target.value, grad);
            }}
          />
        )}
        <G k="zupanija" />
      </label>
      <label className="polje" data-polje="grad">
        <span>Grad / mjesto</span>
        <input
          type="text"
          name="grad"
          maxLength={60}
          value={grad}
          onChange={(e) => {
            setGrad(e.target.value);
            javi(drzava, zupanija, e.target.value);
          }}
        />
        <G k="grad" />
      </label>
    </div>
  );
}
