import { useEffect, useState } from 'preact/hooks';
import { backend } from '../data';
import { adresa, idi } from '../lib/router';
import { postaviSeo } from '../lib/seo';
import { obavijest, osvjeziKorisnika, useJa } from '../lib/stanje';
import { MoraPrijava, Ucitavanje } from '../components/ui';

/** Samo putanje unutar aplikacije (sprječava preusmjeravanje na tuđe stranice). */
const sigurnoNatrag = (upit: URLSearchParams) => {
  const n = upit.get('natrag') ?? '/';
  return n.startsWith('/') && !n.startsWith('//') ? n : '/';
};

function GoogleGumb() {
  if (backend.nacin !== 'supabase') return null;
  return (
    <>
      <button
        class="gumb sirok"
        type="button"
        onClick={() => backend.prijavaGoogle().catch((e: Error) => obavijest(e.message))}
      >
        Nastavi s Googleom
      </button>
      <p class="pomoc" style={{ textAlign: 'center' }}>
        ili e-mailom
      </p>
    </>
  );
}

export function Prijava({ upit }: { upit: URLSearchParams }) {
  const { ja } = useJa();
  const [email, setEmail] = useState('');
  const [lozinka, setLozinka] = useState('');
  const [greska, setGreska] = useState('');
  const [radi, setRadi] = useState(false);
  useEffect(() => postaviSeo('Prijava'), []);
  useEffect(() => {
    if (ja) idi(sigurnoNatrag(upit), true);
  }, [ja?.id]);
  return (
    <div class="ploca" style={{ maxWidth: 420, margin: '0 auto' }}>
      <h1>Prijava</h1>
      <GoogleGumb />
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          setRadi(true);
          setGreska('');
          try {
            await backend.prijava(email, lozinka);
            await osvjeziKorisnika();
          } catch (err) {
            setGreska((err as Error).message);
          } finally {
            setRadi(false);
          }
        }}
      >
        <label class="polje">
          <span>E-mail</span>
          <input type="email" name="email" autoComplete="email" required value={email} onInput={(e) => setEmail(e.currentTarget.value)} />
        </label>
        <label class="polje">
          <span>Lozinka</span>
          <input
            type="password"
            name="lozinka"
            autoComplete="current-password"
            required
            value={lozinka}
            onInput={(e) => setLozinka(e.currentTarget.value)}
          />
        </label>
        {greska && <div class="greska">{greska}</div>}
        <button class="gumb glavni sirok" type="submit" disabled={radi}>
          {radi ? 'Prijavljujem…' : 'Prijavi se'}
        </button>
      </form>
      <p style={{ textAlign: 'center' }}>
        Nemaš račun? <a href={adresa(`/registracija${location.search}`)}>Registriraj se</a>
      </p>
    </div>
  );
}

export function Registracija({ upit }: { upit: URLSearchParams }) {
  const { ja } = useJa();
  const [ime, setIme] = useState('');
  const [email, setEmail] = useState('');
  const [lozinka, setLozinka] = useState('');
  const [uvjeti, setUvjeti] = useState(false);
  const [greska, setGreska] = useState('');
  const [radi, setRadi] = useState(false);
  const [potvrda, setPotvrda] = useState(false);
  useEffect(() => postaviSeo('Registracija'), []);
  useEffect(() => {
    if (ja) idi(sigurnoNatrag(upit), true);
  }, [ja?.id]);
  if (potvrda) {
    return (
      <div class="ploca" style={{ maxWidth: 420, margin: '0 auto' }}>
        <h1>Provjeri e-mail</h1>
        <p>
          Poslali smo poveznicu na <b>{email}</b>. Klikni je da potvrdiš račun, a zatim se prijavi.
        </p>
        <a class="gumb" href={adresa('/prijava')}>
          Na prijavu
        </a>
      </div>
    );
  }
  return (
    <div class="ploca" style={{ maxWidth: 420, margin: '0 auto' }}>
      <h1>Registracija</h1>
      <GoogleGumb />
      <form
        onSubmit={async (e) => {
          e.preventDefault();
          if (!uvjeti) {
            setGreska('Za registraciju prihvati Uvjete korištenja.');
            return;
          }
          setRadi(true);
          setGreska('');
          try {
            const r = await backend.registracija(email, lozinka, ime);
            if (r.potvrdaEmaila) setPotvrda(true);
            else {
              await osvjeziKorisnika();
              obavijest('Dobro došao!');
            }
          } catch (err) {
            setGreska((err as Error).message);
          } finally {
            setRadi(false);
          }
        }}
      >
        <label class="polje">
          <span>Ime ili nadimak</span>
          <input type="text" name="ime" autoComplete="nickname" maxLength={60} required value={ime} onInput={(e) => setIme(e.currentTarget.value)} />
        </label>
        <label class="polje">
          <span>E-mail</span>
          <input type="email" name="email" autoComplete="email" required value={email} onInput={(e) => setEmail(e.currentTarget.value)} />
        </label>
        <label class="polje">
          <span>Lozinka (barem 8 znakova)</span>
          <input
            type="password"
            name="lozinka"
            autoComplete="new-password"
            minLength={8}
            required
            value={lozinka}
            onInput={(e) => setLozinka(e.currentTarget.value)}
          />
        </label>
        <label class="kvacica">
          <input type="checkbox" name="uvjeti" checked={uvjeti} onChange={(e) => setUvjeti(e.currentTarget.checked)} />
          <span>
            Prihvaćam <a href={adresa('/uvjeti')}>Uvjete korištenja</a> i <a href={adresa('/privatnost')}>Politiku privatnosti</a>
          </span>
        </label>
        {greska && <div class="greska">{greska}</div>}
        <button class="gumb glavni sirok" type="submit" disabled={radi}>
          {radi ? 'Stvaram račun…' : 'Napravi račun'}
        </button>
      </form>
      <p style={{ textAlign: 'center' }}>
        Već imaš račun? <a href={adresa(`/prijava${location.search}`)}>Prijavi se</a>
      </p>
    </div>
  );
}

export function Profil() {
  useEffect(() => postaviSeo('Moj profil'), []);
  return (
    <MoraPrijava>
      <ProfilObrazac />
    </MoraPrijava>
  );
}

function ProfilObrazac() {
  const { ja } = useJa();
  const [ime, setIme] = useState(ja?.ime ?? '');
  const [grad, setGrad] = useState(ja?.grad ?? '');
  const [telefon, setTelefon] = useState<string | null>(null);
  const [radi, setRadi] = useState(false);
  useEffect(() => {
    backend.mojTelefon().then((t) => setTelefon(t ?? ''), () => setTelefon(''));
  }, []);
  if (telefon == null || !ja) return <Ucitavanje />;
  return (
    <div style={{ maxWidth: 480 }} class="stog">
      <h1>Moj profil</h1>
      <form
        class="ploca"
        onSubmit={async (e) => {
          e.preventDefault();
          setRadi(true);
          try {
            await backend.spremiProfil({ ime, grad: grad || null, telefon: telefon || null });
            await osvjeziKorisnika();
            obavijest('Profil je spremljen.');
          } catch (err) {
            obavijest((err as Error).message);
          } finally {
            setRadi(false);
          }
        }}
      >
        <label class="polje">
          <span>Ime ili nadimak (vidljivo drugima)</span>
          <input type="text" maxLength={60} value={ime} onInput={(e) => setIme(e.currentTarget.value)} />
        </label>
        <label class="polje">
          <span>Grad</span>
          <input type="text" maxLength={60} value={grad} onInput={(e) => setGrad(e.currentTarget.value)} />
        </label>
        <label class="polje">
          <span>Telefon (prikazuje se samo na oglasima gdje to odabereš)</span>
          <input type="tel" maxLength={30} value={telefon} onInput={(e) => setTelefon(e.currentTarget.value)} />
        </label>
        <button class="gumb glavni" type="submit" disabled={radi}>
          Spremi
        </button>
      </form>
      <div class="gumbi">
        <a class="gumb" href={adresa(`/korisnik/${ja.id}`)}>
          Moj javni profil
        </a>
        {ja.admin && (
          <a class="gumb" href={adresa('/admin')}>
            Moderacija
          </a>
        )}
        <button
          class="gumb opasno"
          type="button"
          onClick={async () => {
            await backend.odjava();
            await osvjeziKorisnika();
            idi('/');
          }}
        >
          Odjava
        </button>
      </div>
    </div>
  );
}
