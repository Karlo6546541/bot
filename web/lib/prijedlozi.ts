import { PODKATEGORIJE, SEKCIJE, nazivNa, type Podkategorija } from './kategorije';
import { normaliziraj, rijeciUpita } from './tekst';

/** Dodatni pojmovi po kategoriji, da "pokemon", "lego", "playstation" ili "alan ford" odmah nađu pravu kategoriju. */
const DODATNO: Record<string, string> = {
  'pokemon-i-ostali-tcg': 'pokemon pikachu charizard tcg karte kartice digimon one piece',
  'magic-the-gathering': 'magic mtg karte kartice',
  'yu-gi-oh': 'yugioh yu gi oh karte kartice',
  'sportske-kartice': 'panini nba nfl nogomet karte kartice',
  'ocijenjene-kartice': 'psa bgs cgc graded ocijenjeno slab',
  kovanice: 'novac kuna lipa euro numizmatika coin',
  novcanice: 'novac papirnati kuna dinar numizmatika banknote',
  'zlato-i-srebro': 'zlatnik srebrnjak poluga gold silver',
  markice: 'marke filatelija stamps',
  'omotnice-i-filatelija': 'pisma kuverte fdc',
  razglednice: 'postcards',
  vinil: 'gramofon ploce ploca lp singl vinyl record',
  'cd-ovi-i-kazete': 'cd kazeta audio glazba',
  'stripovi-i-manga': 'strip manga comics marvel dc',
  'jugoslavenski-stripovi': 'alan ford zagor tex mikijev miki mis',
  'figure-i-funko': 'funko pop figurice igracke action figure',
  'modeli-i-lego': 'lego autici maketa model',
  konzole: 'playstation xbox nintendo sega atari gameboy switch ps1 ps2 ps3 ps4 ps5 nes snes',
  videoigre: 'igre igrica games ps2 ps3 ps4 ps5 switch pc',
  'retro-racunala': 'commodore amiga spectrum atari computer',
  'rucni-satovi': 'sat satovi seiko casio rolex omega watch',
  'dzepni-i-zidni-satovi': 'sat satovi clock',
  'stari-nakit': 'prsten lancic ogrlica narukvica nakit jewelry',
  mobiteli: 'telefon iphone samsung nokia phone',
  'racunala-i-laptopi': 'racunalo laptop pc computer',
  'kamere-i-foto': 'fotoaparat kamera canon nikon camera',
  'audio-i-slusalice': 'slusalice zvucnik pojacalo headphones speaker',
};

export interface PrijedlogKategorije {
  slug: string;
  sekcija: string;
  naziv: string;
  emoji: string;
}

function trazenaVrijednost(p: Podkategorija & { sekcija: string }) {
  const sek = SEKCIJE.find((s) => s.slug === p.sekcija);
  return normaliziraj([p.naziv, p.nazivEn, p.jednina, p.jedninaEn, sek?.naziv, sek?.nazivEn, DODATNO[p.slug]].filter(Boolean).join(' '));
}
const INDEKS = PODKATEGORIJE.map((p) => ({ p, tekst: trazenaVrijednost(p), glave: normaliziraj(`${p.naziv} ${p.nazivEn}`) }));

/** Kategorije koje odgovaraju upitu: svaka upisana riječ mora biti početak neke riječi kategorije. */
export function prijedloziKategorija(q: string, jezik: string, najvise = 4): PrijedlogKategorije[] {
  const rijeci = rijeciUpita(q).filter((w) => w.length >= 2);
  if (!rijeci.length) return [];
  return INDEKS.filter(({ tekst }) => {
    const tokeni = tekst.split(/[^\p{L}\p{N}]+/u);
    return rijeci.every((w) => tokeni.some((t) => t.startsWith(w)));
  })
    .sort((a, b) => Number(b.glave.startsWith(rijeci[0])) - Number(a.glave.startsWith(rijeci[0])))
    .slice(0, najvise)
    .map(({ p }) => ({ slug: p.slug, sekcija: p.sekcija, naziv: nazivNa(p, jezik), emoji: p.emoji }));
}
