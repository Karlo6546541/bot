import Link from 'next/link';

export function PravneVeze() {
  return (
    <p className="pomoc" style={{ textAlign: 'center', padding: '8px 16px 24px', display: 'flex', gap: 16, justifyContent: 'center', flexWrap: 'wrap' }}>
      <Link href="/uvjeti">Uvjeti korištenja</Link>
      <Link href="/privatnost">Privatnost</Link>
      <Link href="/kontakt">Kontakt</Link>
    </p>
  );
}
