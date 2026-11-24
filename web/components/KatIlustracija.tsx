import type { ReactNode } from 'react';

// Vlastite vektorske ilustracije za svih 37 podkategorija (viewBox 120×120).
// Stil: bijeli i zlatni oblici s mekim sjenama na podlozi boje kategorije (--cc).
const C = { fill: 'var(--cc)' } as const;
const GOLD = '#ffd166';
const GOLD2 = '#e3a92c';
const INK = '#1d2427';
const SH = 'rgba(0,0,0,.22)';

const Sjena = ({ rx = 30 }: { rx?: number }) => <ellipse cx="60" cy="102" rx={rx} ry="4.5" fill={SH} />;

/** Karta (60×? s rubom i okvirom za sliku). */
function Karta({ x = 34, y = 16, rot = 0, art }: { x?: number; y?: number; rot?: number; art?: ReactNode }) {
  return (
    <g transform={`rotate(${rot} 60 56)`}>
      <rect x={x} y={y} width="52" height="76" rx="7" fill="#fff" />
      <rect x={x + 5} y={y + 6} width="42" height="38" rx="4" style={C} />
      {art}
      <rect x={x + 5} y={y + 52} width="30" height="4" rx="2" fill="#cfd6d9" />
      <rect x={x + 5} y={y + 60} width="22" height="4" rx="2" fill="#dfe4e6" />
    </g>
  );
}

const Zvijezda = ({ cx, cy, R, r, fill = GOLD, n = 5 }: { cx: number; cy: number; R: number; r: number; fill?: string; n?: number }) => {
  const t = [...Array(n * 2)].map((_, i) => {
    const a = (-90 + (i * 180) / n) * (Math.PI / 180);
    const rad = i % 2 ? r : R;
    return `${(cx + rad * Math.cos(a)).toFixed(1)},${(cy + rad * Math.sin(a)).toFixed(1)}`;
  });
  return <polygon points={t.join(' ')} fill={fill} />;
};

const Stud = ({ x, y }: { x: number; y: number }) => (
  <g>
    <rect x={x - 6} y={y} width="12" height="6" fill="rgba(0,0,0,.12)" />
    <ellipse cx={x} cy={y} rx="6" ry="3" fill="rgba(255,255,255,.95)" />
  </g>
);

const Slojevi = (p: { y: number; w?: number; fill: string; dark: string }) => {
  const w = p.w ?? 60;
  const x = 60 - w / 2;
  return (
    <g>
      <path d={`M${x - 8} ${p.y + 20} L${x + 6} ${p.y} H${x + w - 6} L${x + w + 8} ${p.y + 20} Z`} fill={p.fill} />
      <path d={`M${x - 8} ${p.y + 20} L${x + 6} ${p.y} H${x + w - 6} L${x + w + 8} ${p.y + 20} H${x - 8}`} fill="none" />
      <path d={`M${x + 4} ${p.y + 8} H${x + w - 4}`} stroke={p.dark} strokeWidth="2" opacity=".35" />
    </g>
  );
};

export const ILUSTRACIJE: Record<string, ReactNode> = {
  // ---- Kartice ----
  'pokemon-i-ostali-tcg': (
    <>
      <Sjena />
      <Karta rot={-8} />
      <Karta x={40} y={20} rot={6} art={<polygon points="66,26 53,48 63,48 58,66 77,40 66,40 72,26" fill={GOLD} />} />
    </>
  ),
  'magic-the-gathering': (
    <>
      <Sjena />
      <Karta x={30} y={18} rot={-10} />
      <Karta x={42} y={18} rot={7} art={<path d="M68 26 L74 40 L88 46 L74 52 L68 66 L62 52 L48 46 L62 40Z" fill={GOLD} />} />
    </>
  ),
  'yu-gi-oh': (
    <>
      <Sjena />
      <g transform="rotate(-4 60 56)">
        <rect x="34" y="16" width="52" height="76" rx="7" fill={GOLD2} />
        <rect x="38" y="20" width="44" height="68" rx="5" fill="#fff" />
        <rect x="42" y="25" width="36" height="34" rx="3" style={C} />
        <ellipse cx="60" cy="42" rx="14" ry="8" fill="#fff" />
        <circle cx="60" cy="42" r="5.5" fill={INK} />
        <circle cx="62" cy="40" r="1.8" fill="#fff" />
        <rect x="42" y="64" width="36" height="4" rx="2" fill="#cfd6d9" />
        <rect x="42" y="72" width="26" height="4" rx="2" fill="#dfe4e6" />
      </g>
    </>
  ),
  'sportske-kartice': (
    <>
      <Sjena />
      <Karta rot={-6} />
      <Karta x={40} y={20} rot={8} art={
        <g>
          <circle cx="66" cy="45" r="16" fill="#ff9a3c" />
          <path d="M50 45 H82 M66 29 V61 M54.5 33.5 C61 41 61 49 54.5 56.5 M77.5 33.5 C71 41 71 49 77.5 56.5" stroke="#8a3d00" strokeWidth="1.8" fill="none" />
        </g>
      } />
    </>
  ),
  'ocijenjene-kartice': (
    <>
      <Sjena />
      <rect x="30" y="12" width="60" height="86" rx="9" fill="rgba(255,255,255,.55)" />
      <rect x="35" y="17" width="50" height="76" rx="6" fill="rgba(255,255,255,.9)" />
      <rect x="39" y="21" width="42" height="16" rx="3" style={C} />
      <text x="60" y="34" textAnchor="middle" fontSize="13" fontWeight="800" fill="#fff" fontFamily="Inter, sans-serif">10</text>
      <rect x="42" y="42" width="36" height="46" rx="4" fill="#fff" />
      <rect x="46" y="46" width="28" height="26" rx="3" style={C} />
      <circle cx="60" cy="59" r="7" fill={GOLD} />
    </>
  ),
  // ---- Novci ----
  kovanice: (
    <>
      <Sjena />
      {[84, 70, 56].map((y) => (
        <g key={y}>
          <rect x="34" y={y} width="52" height="11" fill={GOLD2} />
          <ellipse cx="60" cy={y + 11} rx="26" ry="8" fill={GOLD2} />
          <ellipse cx="60" cy={y} rx="26" ry="8" fill={GOLD} />
        </g>
      ))}
      <ellipse cx="60" cy="56" rx="17" ry="5" fill="none" stroke={GOLD2} strokeWidth="2" />
      <Zvijezda cx={60} cy={55} R={5} r={2.2} fill={GOLD2} />
    </>
  ),
  novcanice: (
    <>
      <Sjena />
      <g transform="rotate(-8 60 60)">
        <rect x="20" y="36" width="80" height="46" rx="6" fill="rgba(255,255,255,.65)" />
      </g>
      <g transform="rotate(5 60 60)">
        <rect x="18" y="34" width="84" height="50" rx="6" fill="#fff" />
        <rect x="24" y="40" width="72" height="38" rx="3" fill="none" stroke="#cfd6d9" strokeWidth="1.5" />
        <circle cx="60" cy="59" r="13" style={C} />
        <text x="60" y="64" textAnchor="middle" fontSize="15" fontWeight="800" fill="#fff" fontFamily="Inter, sans-serif">€</text>
        <circle cx="32" cy="48" r="3" fill={GOLD} />
        <circle cx="88" cy="70" r="3" fill={GOLD} />
      </g>
    </>
  ),
  'zlato-i-srebro': (
    <>
      <Sjena />
      <Slojevi y={72} w={34} fill={GOLD} dark={GOLD2} />
      <g transform="translate(-26 0)"><Slojevi y={72} w={34} fill="#e8eef2" dark="#9aa7ad" /></g>
      <g transform="translate(26 0)"><Slojevi y={72} w={34} fill={GOLD} dark={GOLD2} /></g>
      <g transform="translate(0 -22)"><Slojevi y={72} w={34} fill="#e8eef2" dark="#9aa7ad" /></g>
      <path d="M40 30 l4 -8 l4 8 l-4 -2z M92 40 l3 -6 l3 6 l-3 -1.5z" fill="#fff" opacity=".9" />
    </>
  ),
  // ---- Markice ----
  markice: (
    <>
      <Sjena />
      <g transform="rotate(-5 60 56)">
        <rect x="30" y="18" width="60" height="76" fill="none" stroke="#fff" strokeWidth="7" strokeDasharray="0 8" strokeLinecap="round" />
        <rect x="32" y="20" width="56" height="72" fill="#fff" />
        <rect x="38" y="26" width="44" height="46" style={C} />
        <circle cx="60" cy="42" r="8" fill={GOLD} />
        <path d="M38 72 L52 52 L62 64 L70 56 L82 72Z" fill="rgba(0,0,0,.25)" />
        <rect x="40" y="78" width="22" height="4" rx="2" fill="#cfd6d9" />
        <text x="76" y="84" textAnchor="middle" fontSize="10" fontWeight="800" fill={INK} fontFamily="Inter, sans-serif">1</text>
      </g>
    </>
  ),
  'omotnice-i-filatelija': (
    <>
      <Sjena />
      <rect x="18" y="32" width="84" height="58" rx="7" fill="#fff" />
      <path d="M18 38 L60 68 L102 38" fill="none" stroke="#cfd6d9" strokeWidth="2.5" strokeLinejoin="round" />
      <path d="M18 88 L46 60 M102 88 L74 60" stroke="#dfe4e6" strokeWidth="2" />
      <g transform="rotate(6 90 44)">
        <rect x="80" y="34" width="18" height="22" fill="none" stroke="#fff" strokeWidth="4" strokeDasharray="0 5" strokeLinecap="round" />
        <rect x="81" y="35" width="16" height="20" fill="#fff" />
        <rect x="83" y="37" width="12" height="13" style={C} />
      </g>
      <path d="M34 78 q6 -5 12 0 t12 0" stroke="#aeb7bb" strokeWidth="2" fill="none" />
    </>
  ),
  // ---- Razglednice i plakati ----
  razglednice: (
    <>
      <Sjena />
      <g transform="rotate(-6 60 60)">
        <rect x="20" y="30" width="80" height="58" rx="5" fill="#fff" />
        <rect x="26" y="36" width="34" height="46" rx="3" style={C} />
        <circle cx="48" cy="48" r="6" fill={GOLD} />
        <path d="M26 82 L38 62 L46 72 L54 62 L60 82Z" fill="rgba(0,0,0,.25)" />
        <line x1="66" y1="36" x2="66" y2="82" stroke="#dfe4e6" strokeWidth="2" />
        <rect x="82" y="38" width="12" height="14" fill="none" stroke={GOLD2} strokeWidth="2" />
        <rect x="70" y="60" width="24" height="3" rx="1.5" fill="#cfd6d9" />
        <rect x="70" y="68" width="24" height="3" rx="1.5" fill="#cfd6d9" />
        <rect x="70" y="76" width="16" height="3" rx="1.5" fill="#cfd6d9" />
      </g>
    </>
  ),
  'plakati-i-reklame': (
    <>
      <Sjena />
      <g transform="rotate(4 60 56)">
        <rect x="32" y="12" width="56" height="80" rx="3" fill="#fff" />
        <rect x="32" y="12" width="56" height="26" rx="3" style={C} />
        <path d="M44 62 L70 52 V76 L44 68Z" fill={GOLD} />
        <rect x="38" y="60" width="10" height="10" rx="2" fill={GOLD2} />
        <path d="M76 56 q6 8 0 16 M82 52 q9 12 0 24" stroke={GOLD2} strokeWidth="2.5" fill="none" strokeLinecap="round" />
        <rect x="40" y="20" width="32" height="5" rx="2.5" fill="#fff" />
        <rect x="40" y="28" width="20" height="4" rx="2" fill="rgba(255,255,255,.7)" />
        <rect x="40" y="82" width="38" height="3" rx="1.5" fill="#cfd6d9" />
      </g>
    </>
  ),
  // ---- Ploče i mediji ----
  vinil: (
    <>
      <Sjena />
      <rect x="18" y="20" width="68" height="68" rx="4" fill="rgba(255,255,255,.9)" />
      <rect x="26" y="28" width="52" height="34" rx="2" style={C} />
      <rect x="26" y="68" width="30" height="4" rx="2" fill="#cfd6d9" />
      <circle cx="70" cy="62" r="34" fill="#1c2226" />
      {[28, 22, 16].map((r) => <circle key={r} cx="70" cy="62" r={r} fill="none" stroke="rgba(255,255,255,.12)" strokeWidth="1.2" />)}
      <path d="M48 50 A26 26 0 0 1 66 36" stroke="rgba(255,255,255,.35)" strokeWidth="3" fill="none" strokeLinecap="round" />
      <circle cx="70" cy="62" r="11" fill={GOLD} />
      <circle cx="70" cy="62" r="2.5" fill="#fff" />
    </>
  ),
  'cd-ovi-i-kazete': (
    <>
      <Sjena />
      <rect x="18" y="34" width="84" height="56" rx="7" fill="#fff" />
      <rect x="26" y="40" width="68" height="24" rx="3" style={C} />
      <rect x="30" y="45" width="30" height="3" rx="1.5" fill="rgba(255,255,255,.85)" />
      <rect x="30" y="52" width="20" height="3" rx="1.5" fill="rgba(255,255,255,.55)" />
      <rect x="38" y="68" width="44" height="16" rx="8" fill="#e1e6e8" />
      <circle cx="48" cy="76" r="6" fill="#fff" stroke={INK} strokeWidth="2" />
      <circle cx="72" cy="76" r="6" fill="#fff" stroke={INK} strokeWidth="2" />
      <circle cx="48" cy="76" r="1.8" fill={INK} /><circle cx="72" cy="76" r="1.8" fill={INK} />
    </>
  ),
  // ---- Stripovi ----
  'stripovi-i-manga': (
    <>
      <Sjena />
      <g transform="rotate(-4 60 56)">
        <rect x="26" y="14" width="68" height="84" rx="4" fill="#fff" />
        <rect x="32" y="20" width="26" height="30" style={C} />
        <rect x="62" y="20" width="26" height="30" fill={GOLD} />
        <rect x="32" y="54" width="56" height="38" fill="rgba(0,0,0,.08)" />
        <path d="M36 82 L48 62 L58 76 L66 66 L84 86Z" style={C} opacity=".9" />
        <ellipse cx="70" cy="34" rx="12" ry="8" fill="#fff" />
        <path d="M62 40 L58 47 L68 41Z" fill="#fff" />
        <text x="70" y="38" textAnchor="middle" fontSize="11" fontWeight="900" fill={INK} fontFamily="Inter, sans-serif">!</text>
      </g>
    </>
  ),
  'jugoslavenski-stripovi': (
    <>
      <Sjena />
      <g transform="rotate(3 60 56)">
        <rect x="30" y="12" width="60" height="86" rx="4" fill="#fff" />
        <rect x="30" y="12" width="60" height="24" rx="4" style={C} />
        <rect x="37" y="19" width="36" height="6" rx="3" fill="#fff" />
        <rect x="37" y="28" width="22" height="3" rx="1.5" fill="rgba(255,255,255,.7)" />
        <circle cx="60" cy="64" r="22" fill="#fff4cc" />
        <Zvijezda cx={60} cy={64} R={19} r={8} fill="#e0452d" />
        <rect x="38" y="90" width="44" height="3" rx="1.5" fill="#cfd6d9" />
      </g>
    </>
  ),
  // ---- Figure i igračke ----
  'figure-i-funko': (
    <>
      <Sjena />
      <rect x="44" y="68" width="32" height="22" rx="8" style={C} fill="#fff" />
      <rect x="44" y="68" width="32" height="22" rx="8" fill="rgba(255,255,255,.95)" />
      <rect x="48" y="74" width="24" height="12" rx="4" style={C} />
      <rect x="46" y="88" width="12" height="8" rx="3" fill="#fff" /><rect x="62" y="88" width="12" height="8" rx="3" fill="#fff" />
      <rect x="32" y="16" width="56" height="50" rx="18" fill="#fff" />
      <path d="M32 34 C32 18 44 12 60 12 C76 12 88 18 88 34 C74 26 46 26 32 34Z" fill={GOLD} />
      <circle cx="48" cy="44" r="5.5" fill={INK} /><circle cx="72" cy="44" r="5.5" fill={INK} />
      <circle cx="49.8" cy="42.2" r="1.7" fill="#fff" /><circle cx="73.8" cy="42.2" r="1.7" fill="#fff" />
      <path d="M54 56 q6 4 12 0" stroke={INK} strokeWidth="2.2" fill="none" strokeLinecap="round" />
    </>
  ),
  'modeli-i-lego': (
    <>
      <Sjena />
      <rect x="22" y="64" width="76" height="30" rx="3" fill={GOLD} />
      <rect x="22" y="84" width="76" height="10" rx="3" fill={GOLD2} />
      {[36, 52, 68, 84].map((x) => <Stud key={x} x={x - 2} y={60} />)}
      <rect x="36" y="38" width="48" height="28" rx="3" fill="#fff" />
      <rect x="36" y="56" width="48" height="10" rx="3" fill="#dfe4e6" />
      {[48, 60, 72].map((x) => <Stud key={x} x={x} y={34} />)}
    </>
  ),
  // ---- Konzole i igre ----
  konzole: (
    <>
      <Sjena />
      <rect x="16" y="40" width="88" height="44" rx="22" fill="#fff" />
      <rect x="35" y="55" width="22" height="7" rx="2" style={C} /><rect x="42.5" y="47.5" width="7" height="22" rx="2" style={C} />
      <circle cx="80" cy="54" r="5" fill={GOLD} /><circle cx="90" cy="63" r="5" style={C} />
      <circle cx="70" cy="63" r="4" fill="#dfe4e6" /><circle cx="80" cy="72" r="5" fill="#e0452d" />
      <rect x="55" y="66" width="10" height="4" rx="2" fill="#cfd6d9" />
    </>
  ),
  videoigre: (
    <>
      <Sjena />
      <path d="M34 20 H86 V84 L80 92 H40 L34 84Z" fill="#cfd8dc" />
      <rect x="40" y="26" width="40" height="38" rx="3" style={C} />
      <Zvijezda cx={60} cy={45} R={11} r={4.5} fill={GOLD} />
      <rect x="44" y="70" width="32" height="14" rx="2" fill="#aeb9be" />
      {[48, 54, 60, 66, 72].map((x) => <rect key={x} x={x} y="72" width="2" height="10" fill="#8e9aa0" />)}
    </>
  ),
  'retro-racunala': (
    <>
      <Sjena />
      <rect x="26" y="18" width="68" height="56" rx="7" fill="#fff" />
      <rect x="33" y="25" width="54" height="40" rx="4" fill="#12181a" />
      <path d="M40 36 l7 5 l-7 5" stroke="#7CFFB0" strokeWidth="2.5" fill="none" strokeLinecap="round" strokeLinejoin="round" />
      <rect x="52" y="44" width="14" height="3" rx="1.5" fill="#7CFFB0" />
      <rect x="40" y="74" width="40" height="8" fill="#e1e6e8" />
      <rect x="22" y="84" width="76" height="13" rx="4" fill="rgba(255,255,255,.9)" />
      {[30, 40, 50, 60, 70, 80].map((x) => <rect key={x} x={x} y="88" width="6" height="3" rx="1" fill="#aeb7bb" />)}
    </>
  ),
  // ---- Memorabilije i autogrami ----
  'sportske-memorabilije': (
    <>
      <Sjena />
      <path d="M40 22 H80 V48 C80 62 71 70 60 70 C49 70 40 62 40 48Z" fill={GOLD} />
      <path d="M40 28 C26 28 26 48 42 50 M80 28 C94 28 94 48 78 50" stroke={GOLD2} strokeWidth="5" fill="none" strokeLinecap="round" />
      <Zvijezda cx={60} cy={45} R={11} r={4.6} fill="#fff" />
      <rect x="55" y="70" width="10" height="12" fill={GOLD2} />
      <rect x="42" y="82" width="36" height="12" rx="3" fill="#fff" />
      <rect x="48" y="86" width="24" height="3" rx="1.5" style={C} />
    </>
  ),
  autogrami: (
    <>
      <Sjena />
      <g transform="rotate(-5 60 60)">
        <rect x="24" y="22" width="56" height="70" rx="5" fill="#fff" />
        <rect x="30" y="28" width="44" height="40" rx="3" style={C} />
        <circle cx="52" cy="43" r="8" fill="rgba(255,255,255,.95)" />
        <path d="M36 68 C36 56 44 52 52 52 C60 52 68 56 68 68Z" fill="rgba(255,255,255,.95)" />
        <path d="M30 80 q8 -10 14 0 t12 -2 t14 -4" stroke={GOLD2} strokeWidth="3" fill="none" strokeLinecap="round" />
      </g>
      <g transform="rotate(38 88 40)">
        <rect x="84" y="14" width="8" height="42" rx="3" fill="#fff" />
        <polygon points="84,56 92,56 88,66" fill={GOLD} />
        <rect x="84" y="14" width="8" height="8" rx="3" style={C} />
      </g>
    </>
  ),
  // ---- Vojna i povijest ----
  'vojna-i-povijesna-oprema': (
    <>
      <Sjena />
      <path d="M22 70 C22 42 40 24 62 24 C84 24 98 44 98 70Z" fill="#fff" />
      <path d="M22 70 C22 42 40 24 62 24 C84 24 98 44 98 70Z" fill="rgba(0,0,0,.1)" />
      <path d="M30 52 C38 36 52 30 64 30" stroke="rgba(255,255,255,.9)" strokeWidth="4" fill="none" strokeLinecap="round" />
      <ellipse cx="60" cy="72" rx="44" ry="9" fill="rgba(255,255,255,.9)" />
      <Zvijezda cx={62} cy={50} R={11} r={4.6} fill="#e0452d" />
      <path d="M30 78 q30 14 60 0" stroke="rgba(255,255,255,.6)" strokeWidth="3" fill="none" strokeLinecap="round" />
    </>
  ),
  'znacke-i-medalje': (
    <>
      <Sjena />
      <polygon points="38,12 56,12 68,50 52,50" fill="#fff" />
      <polygon points="82,12 64,12 52,50 68,50" style={C} fill="#fff" />
      <polygon points="64,12 82,12 70,48 54,48" fill="rgba(255,255,255,.55)" />
      <circle cx="60" cy="72" r="24" fill={GOLD2} />
      <circle cx="60" cy="70" r="24" fill={GOLD} />
      <circle cx="60" cy="70" r="16" fill="none" stroke={GOLD2} strokeWidth="2.5" />
      <Zvijezda cx={60} cy={70} R={11} r={4.5} fill="#fff" />
    </>
  ),
  // ---- Slike i umjetnost ----
  'slike-i-crtezi': (
    <>
      <Sjena />
      <rect x="20" y="20" width="80" height="68" rx="4" fill={GOLD2} />
      <rect x="25" y="25" width="70" height="58" rx="2" fill={GOLD} />
      <rect x="30" y="30" width="60" height="48" fill="#fff" />
      <rect x="30" y="30" width="60" height="48" fill="rgba(255,255,255,.2)" />
      <circle cx="74" cy="44" r="7" fill={GOLD} />
      <path d="M30 78 L48 52 L60 66 L70 56 L90 78Z" style={C} />
      <path d="M30 78 L40 66 L52 78Z" fill="rgba(0,0,0,.22)" />
    </>
  ),
  'grafike-i-fotografije': (
    <>
      <Sjena />
      <g transform="rotate(9 60 56)"><rect x="34" y="18" width="52" height="64" rx="3" fill="rgba(255,255,255,.65)" /></g>
      <g transform="rotate(-7 60 56)">
        <rect x="30" y="18" width="60" height="72" rx="3" fill="#fff" />
        <rect x="36" y="24" width="48" height="46" style={C} />
        <circle cx="68" cy="38" r="6" fill={GOLD} />
        <path d="M36 70 L50 50 L60 62 L68 54 L84 70Z" fill="rgba(0,0,0,.25)" />
        <rect x="40" y="77" width="26" height="4" rx="2" fill="#cfd6d9" />
      </g>
    </>
  ),
  // ---- Satovi ----
  'rucni-satovi': (
    <>
      <Sjena />
      <rect x="45" y="8" width="30" height="34" rx="7" fill="rgba(255,255,255,.55)" />
      <rect x="45" y="78" width="30" height="34" rx="7" fill="rgba(255,255,255,.55)" />
      <circle cx="60" cy="60" r="30" fill={GOLD2} />
      <circle cx="60" cy="58" r="30" fill={GOLD} />
      <circle cx="60" cy="58" r="23" fill="#fff" />
      {[0, 90, 180, 270].map((a) => <rect key={a} x="58.8" y="37" width="2.4" height="5" rx="1" fill={INK} transform={`rotate(${a} 60 58)`} />)}
      <path d="M60 58 V43" stroke={INK} strokeWidth="3" strokeLinecap="round" />
      <path d="M60 58 L71 64" stroke={INK} strokeWidth="2.6" strokeLinecap="round" />
      <circle cx="60" cy="58" r="2.4" style={C} />
      <rect x="88" y="55" width="6" height="7" rx="2" fill={GOLD2} />
    </>
  ),
  'dzepni-i-zidni-satovi': (
    <>
      <Sjena />
      <circle cx="60" cy="24" r="9" fill="none" stroke={GOLD2} strokeWidth="5" />
      <rect x="55" y="28" width="10" height="9" rx="2" fill={GOLD2} />
      <circle cx="60" cy="68" r="33" fill={GOLD2} />
      <circle cx="60" cy="66" r="33" fill={GOLD} />
      <circle cx="60" cy="66" r="26" fill="#fff" />
      {[...Array(12)].map((_, i) => <rect key={i} x="59" y="42" width="2" height={i % 3 ? 3 : 5} fill={INK} transform={`rotate(${i * 30} 60 66)`} />)}
      <path d="M60 66 V48" stroke={INK} strokeWidth="2.8" strokeLinecap="round" />
      <path d="M60 66 L74 72" stroke={INK} strokeWidth="2.4" strokeLinecap="round" />
      <circle cx="60" cy="66" r="2.6" style={C} />
    </>
  ),
  // ---- Antikviteti i vintage ----
  'vintage-i-antikviteti': (
    <>
      <Sjena />
      <path d="M44 38 L52 24 M76 38 L68 24" stroke="#fff" strokeWidth="3" strokeLinecap="round" />
      <rect x="20" y="38" width="80" height="54" rx="9" fill="#fff" />
      <circle cx="46" cy="65" r="15" style={C} />
      {[56, 61, 66, 71, 76].map((y) => <path key={y} d={`M35 ${y - 11} H57`} stroke="rgba(255,255,255,.6)" strokeWidth="1.4" />)}
      <circle cx="78" cy="55" r="7.5" fill={GOLD} /><circle cx="78" cy="76" r="7.5" fill="#cfd6d9" />
      <rect x="66" y="45" width="30" height="3" rx="1.5" fill="#dfe4e6" />
      <circle cx="78" cy="55" r="1.6" fill={GOLD2} />
    </>
  ),
  'keramika-i-porculan': (
    <>
      <Sjena />
      <path d="M46 16 H74 V28 C74 36 90 42 90 64 C90 84 76 94 60 94 C44 94 30 84 30 64 C30 42 46 36 46 28Z" fill="#fff" />
      <ellipse cx="60" cy="16" rx="14" ry="4" fill="#dfe4e6" />
      <path d="M31 58 C45 66 75 66 89 58 L88 70 C74 78 46 78 32 70Z" style={C} />
      <path d="M37 76 C50 83 70 83 83 76" stroke={GOLD} strokeWidth="3.5" fill="none" strokeLinecap="round" />
      {[44, 60, 76].map((x) => <circle key={x} cx={x} cy={64 + (x === 60 ? 3 : 0)} r="3" fill={GOLD} />)}
      <path d="M38 40 C34 52 36 60 40 64" stroke="rgba(255,255,255,.9)" strokeWidth="3" fill="none" strokeLinecap="round" opacity=".6" />
    </>
  ),
  'stari-nakit': (
    <>
      <Sjena />
      <ellipse cx="60" cy="76" rx="27" ry="23" fill="none" stroke={GOLD2} strokeWidth="9" />
      <ellipse cx="60" cy="74" rx="27" ry="23" fill="none" stroke={GOLD} strokeWidth="8" />
      <polygon points="60,16 78,32 60,56 42,32" fill="#fff" />
      <polygon points="60,16 78,32 42,32" fill="rgba(255,255,255,.85)" />
      <polygon points="60,32 78,32 60,56" style={C} opacity=".55" />
      <path d="M42 32 H78 M60 16 L52 32 L60 56 L68 32Z" stroke="rgba(0,0,0,.18)" strokeWidth="1.2" fill="none" />
      <path d="M32 26 l3 -7 l3 7 l-3 -2z M86 22 l2.5 -6 l2.5 6 l-2.5 -1.5z" fill="#fff" />
    </>
  ),
  // ---- Elektronika ----
  'ostala-elektronika': (
    <>
      <Sjena />
      {[44, 56, 68, 80].flatMap((p) => [
        <rect key={`a${p}`} x={p - 3} y="26" width="6" height="12" rx="2" fill="#dfe4e6" />,
        <rect key={`b${p}`} x={p - 3} y="82" width="6" height="12" rx="2" fill="#dfe4e6" />,
        <rect key={`c${p}`} x="26" y={p - 3 + 4} width="12" height="6" rx="2" fill="#dfe4e6" />,
        <rect key={`d${p}`} x="82" y={p - 3 + 4} width="12" height="6" rx="2" fill="#dfe4e6" />,
      ])}
      <rect x="34" y="34" width="52" height="52" rx="8" fill="#fff" />
      <rect x="44" y="44" width="32" height="32" rx="5" style={C} />
      <circle cx="60" cy="60" r="7" fill={GOLD} />
      <circle cx="40" cy="40" r="2" fill="#cfd6d9" />
    </>
  ),
  mobiteli: (
    <>
      <Sjena />
      <rect x="36" y="12" width="48" height="88" rx="10" fill="#fff" />
      <rect x="41" y="21" width="38" height="66" rx="4" style={C} />
      <rect x="41" y="21" width="38" height="66" rx="4" fill="url(#sjaj)" />
      <rect x="53" y="15" width="14" height="3" rx="1.5" fill="#cfd6d9" />
      {[0, 1, 2].flatMap((r) => [0, 1, 2].map((c) => <rect key={`${r}${c}`} x={46 + c * 11} y={27 + r * 13} width="8" height="8" rx="2.5" fill={(r + c) % 3 === 0 ? GOLD : 'rgba(255,255,255,.9)'} />))}
      <rect x="52" y="93" width="16" height="3" rx="1.5" fill="#cfd6d9" />
    </>
  ),
  'racunala-i-laptopi': (
    <>
      <Sjena />
      <rect x="26" y="24" width="68" height="48" rx="6" fill="#fff" />
      <rect x="32" y="30" width="56" height="36" rx="3" style={C} />
      <path d="M32 56 L46 44 L56 54 L66 46 L88 62 V66 H32Z" fill="rgba(0,0,0,.2)" />
      <circle cx="74" cy="40" r="5" fill={GOLD} />
      <path d="M16 76 H104 L98 88 H22Z" fill="rgba(255,255,255,.92)" />
      <rect x="48" y="78" width="24" height="3" rx="1.5" fill="#cfd6d9" />
    </>
  ),
  'kamere-i-foto': (
    <>
      <Sjena />
      <path d="M40 34 L46 24 H66 L72 34Z" fill="#dfe4e6" />
      <rect x="20" y="34" width="80" height="54" rx="9" fill="#fff" />
      <rect x="20" y="42" width="80" height="8" fill="rgba(0,0,0,.08)" />
      <circle cx="60" cy="63" r="20" fill="#dfe4e6" />
      <circle cx="60" cy="63" r="15" fill={INK} />
      <circle cx="60" cy="63" r="10" style={C} />
      <circle cx="56" cy="59" r="3.2" fill="rgba(255,255,255,.9)" />
      <circle cx="88" cy="43" r="3.4" fill={GOLD} />
      <rect x="26" y="40" width="12" height="5" rx="2" fill={GOLD} />
    </>
  ),
  'audio-i-slusalice': (
    <>
      <Sjena />
      <path d="M30 68 V58 C30 36 44 22 60 22 C76 22 90 36 90 58 V68" fill="none" stroke="#fff" strokeWidth="8" strokeLinecap="round" />
      <path d="M36 58 C36 42 46 30 60 30" fill="none" stroke="rgba(255,255,255,.35)" strokeWidth="3" strokeLinecap="round" />
      <rect x="22" y="58" width="20" height="38" rx="10" fill="#fff" />
      <rect x="78" y="58" width="20" height="38" rx="10" fill="#fff" />
      <rect x="27" y="66" width="10" height="22" rx="5" style={C} />
      <rect x="83" y="66" width="10" height="22" rx="5" style={C} />
    </>
  ),
};

/** Ilustracija podkategorije; nepoznata dobiva neutralnu etiketu. */
export function KatIlustracija({ slug, naslov }: { slug: string; naslov?: string }) {
  const sadrzaj = ILUSTRACIJE[slug] ?? (
    <>
      <Sjena />
      <path d="M26 54 L26 34 Q26 28 32 28 L54 28 L96 70 Q100 74 96 78 L76 98 Q72 102 68 98Z" fill="#fff" />
      <circle cx="40" cy="42" r="6" style={C} />
    </>
  );
  return (
    <svg viewBox="0 0 120 120" role={naslov ? 'img' : undefined} aria-label={naslov} aria-hidden={naslov ? undefined : true} focusable="false" className="kat-ilu">
      <defs>
        <linearGradient id="sjaj" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#fff" stopOpacity=".35" />
          <stop offset=".5" stopColor="#fff" stopOpacity="0" />
        </linearGradient>
      </defs>
      {sadrzaj}
    </svg>
  );
}
