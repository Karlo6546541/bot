import { APP_NAME, APP_SLOGAN } from './config/app';
import { backend } from './data';
import { adresa, useRuta } from './lib/router';
import { useJa, useToastovi } from './lib/stanje';
import { Admin } from './pages/admin';
import { MojiOglasi } from './pages/moji';
import { Objavi } from './pages/objavi';
import { OglasStranica } from './pages/oglas';
import { Favoriti, KorisnikStranica, Poruke, RazgovorStranica, useNeprocitano } from './pages/poruke';
import { Pocetna, Popis } from './pages/popis';
import { Kontakt, NijePronadeno, Privatnost, Uvjeti } from './pages/pravno';
import { Prijava, Profil, Registracija } from './pages/racun';

function Zaglavlje() {
  const { ja } = useJa();
  const neprocitano = useNeprocitano();
  return (
    <header class="zaglavlje">
      <div class="zaglavlje-unutra">
        <a class="logo" href={adresa('/')} aria-label={`${APP_NAME} – početna`}>
          <b>{APP_NAME}</b>
          <small>{APP_SLOGAN}</small>
        </a>
        <a class="ikona-gumb" href={adresa('/oglasi')} aria-label="Pretraži oglase" title="Pretraži">
          🔍
        </a>
        {ja ? (
          <>
            <a class="ikona-gumb" href={adresa('/favoriti')} aria-label="Favoriti" title="Favoriti">
              ♡
            </a>
            <a class="ikona-gumb" href={adresa('/poruke')} aria-label={`Poruke${neprocitano ? ` (${neprocitano} novih)` : ''}`} title="Poruke">
              ✉️{neprocitano > 0 && <span class="znacka">{neprocitano}</span>}
            </a>
            <a class="ikona-gumb" href={adresa('/moji-oglasi')} aria-label="Moji oglasi" title="Moji oglasi">
              📋
            </a>
            <a class="ikona-gumb" href={adresa('/profil')} aria-label="Moj profil" title="Profil">
              👤
            </a>
          </>
        ) : (
          <a class="gumb malen" href={adresa('/prijava')}>
            Prijava
          </a>
        )}
        <a class="gumb glavni malen objavi-zaglavlje" href={adresa('/objavi')}>
          + Objavi oglas
        </a>
      </div>
    </header>
  );
}

function Sadrzaj() {
  const { put, upit } = useRuta();
  const d = put.split('/').filter(Boolean).map(decodeURIComponent);
  const [a, b, c] = d;
  if (d.length === 0) return <Pocetna />;
  if (a === 'oglasi' && d.length === 1) return <Popis upit={upit} />;
  if (a === 'kategorija' && b) return <Popis upit={upit} kategorijaSlug={b} key={b} />;
  if (a === 'oglas' && b && c === 'uredi') return <Objavi id={b} key={`u${b}`} />;
  if (a === 'oglas' && b) return <OglasStranica id={b} key={b} />;
  if (a === 'objavi') return <Objavi key="novi" />;
  if (a === 'moji-oglasi') return <MojiOglasi />;
  if (a === 'poruke' && b) return <RazgovorStranica id={b} key={b} />;
  if (a === 'poruke') return <Poruke />;
  if (a === 'favoriti') return <Favoriti />;
  if (a === 'korisnik' && b) return <KorisnikStranica id={b} key={b} />;
  if (a === 'prijava') return <Prijava upit={upit} />;
  if (a === 'registracija') return <Registracija upit={upit} />;
  if (a === 'profil') return <Profil />;
  if (a === 'admin') return <Admin />;
  if (a === 'uvjeti') return <Uvjeti />;
  if (a === 'privatnost') return <Privatnost />;
  if (a === 'kontakt') return <Kontakt />;
  return <NijePronadeno />;
}

export function App() {
  const toastovi = useToastovi();
  const { put } = useRuta();
  return (
    <>
      {backend.nacin === 'lokalno' && (
        <div class="demo-traka" role="note">
          Demo način: oglasi i računi spremaju se samo u ovom pregledniku.
        </div>
      )}
      <Zaglavlje />
      <main id="sadrzaj">
        <Sadrzaj />
      </main>
      <footer class="podnozje">
        <div class="podnozje-unutra">
          <span>
            © {new Date().getFullYear()} {APP_NAME}
          </span>
          <a href={adresa('/uvjeti')}>Uvjeti korištenja</a>
          <a href={adresa('/privatnost')}>Privatnost</a>
          <a href={adresa('/kontakt')}>Kontakt</a>
        </div>
      </footer>
      {put !== '/objavi' && !put.endsWith('/uredi') && (
        <a class="gumb glavni objavi-plutajuci" href={adresa('/objavi')}>
          + Objavi oglas
        </a>
      )}
      <div class="toastovi" aria-live="polite">
        {toastovi.map((t) => (
          <div class="toast" key={t.id}>
            {t.tekst}
          </div>
        ))}
      </div>
    </>
  );
}
