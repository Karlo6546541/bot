import './globals.css';

// Adrese izvan oba jezika (rijetko): dvojezična stranica s vlastitim <html>.
export default function NotFound() {
  return (
    <html lang="hr">
      <body>
        <main className="sredina">
          <div className="prazno">
            <h1 style={{ fontSize: 20 }}>Stranica nije pronađena</h1>
            <p>Oglas je možda obrisan ili je adresa pogrešna.</p>
            <a className="gumb glavni" href="/oglasi">Pogledaj oglase</a>
            <p lang="en" style={{ marginTop: 24 }}>Page not found.</p>
            <a lang="en" className="gumb" href="/en/oglasi">Browse listings</a>
          </div>
        </main>
      </body>
    </html>
  );
}
