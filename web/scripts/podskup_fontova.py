#!/usr/bin/env python3
"""Podskup fontova za web: samo ikone koje se koriste (lib/ikone.ts + kategorije) i latinica za Inter.
Treba fonttools i brotli. Pokretanje: python3 scripts/podskup_fontova.py <putanja do foldera s izvornim fontovima>"""
import re
import subprocess
import sys
from pathlib import Path

web = Path(__file__).resolve().parents[1]
izvor = Path(sys.argv[1])
kodovi = set()
for f in (web / 'lib/ikone.ts', web / 'lib/kategorije.ts'):
    t = f.read_text()
    kodovi |= {int(x, 16) for x in re.findall(r'0x([0-9a-fA-F]{3,6})', t)}
    if f.name == 'kategorije.ts':
        kodovi |= {int(x) for x in re.findall(r'ikona: (\d+)', t)}
unicodes = ','.join(f'U+{k:x}' for k in sorted(kodovi))
out = web / 'public/fonts'
out.mkdir(parents=True, exist_ok=True)
subprocess.run(['pyftsubset', str(izvor / 'MaterialIcons-Regular.otf'), f'--unicodes={unicodes}', '--flavor=woff2', f'--output-file={out}/mi.woff2'], check=True)
latin = 'U+0020-007E,U+00A0-017F,U+2010-2022,U+2026,U+20AC,U+2192,U+2190,U+00D7,U+2212'
for w, ime in [(400, 'Inter_400Regular'), (500, 'Inter_500Medium'), (600, 'Inter_600SemiBold'), (700, 'Inter_700Bold')]:
    subprocess.run(['pyftsubset', str(izvor / f'{ime}.ttf'), f'--unicodes={latin}', '--flavor=woff2', '--layout-features=*', f'--output-file={out}/inter-{w}.woff2'], check=True)
print(len(kodovi), 'ikona')
