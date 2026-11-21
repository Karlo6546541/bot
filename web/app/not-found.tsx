import Link from 'next/link';
import { Ikona } from '@/components/Ikona';
import { IK } from '@/lib/ikone';

export default function NijePronadeno() {
  return (
    <div className="prazno">
      <div className="krug"><Ikona k={IK.search} /></div>
      <h1 style={{ fontSize: 20 }}>Stranica nije pronađena</h1>
      <p>Oglas je možda obrisan ili je adresa pogrešna.</p>
      <Link className="gumb glavni" href="/oglasi">Pogledaj oglase</Link>
    </div>
  );
}
