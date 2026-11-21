import Link from 'next/link';

export default function NijePronadeno() {
  return (
    <div className="prazno ploca">
      <h1>Stranica nije pronađena</h1>
      <p>Oglas je možda obrisan ili je adresa pogrešna.</p>
      <Link className="gumb" href="/oglasi">Pogledaj oglase</Link>
    </div>
  );
}
