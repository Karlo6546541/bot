# Polymarket BTC 5-min Up/Down — latency + pair-lock bot

Bot ne predviđa smjer. Zarađuje na tome što Polymarket knjiga kasni 1–2 s za Binanceom:

1. **LATENCY.** BTC na Binanceu skoči, a UP ponuda na Polymarketu još stoji na staroj cijeni. Bot kupi UP ispod fer vrijednosti. Kad BTC padne, isto napravi s DOWN.
2. **LOCK.** Kad drži UP po prosječnoj cijeni `c_up`, kupi DOWN čim je `c_up + ask_down_eff ≤ 1 − margin`. Par UP+DOWN uvijek isplaćuje točno 1 $, pa je profit zaključan bez obzira na ishod.
3. **COMPLETE SET.** Ako je `ask_up_eff + ask_down_eff < 1 − margin`, kupi oba odmah.
4. **STALE BID.** Proda dionice u zastarjeli bid koji je iznad fer vrijednosti.

Zato bot može biti profitabilan i kad pojedinačni nalozi "pogode smjer" samo ~45–50% vremena. Svaki nalog je kupljen ispod fer vrijednosti, a upareni nalozi nemaju rizik.

## Matematika (`polybot/mathcore.py`)

| Veličina | Formula |
|---|---|
| Fer P(UP) | `d = (ln(S/K) − σ²τ/2)/(σ√τ)`, `q = F_ν(d·√(ν/(ν−2)))` (Student-t, debeli repovi; ν=0 → normalna) |
| S | Binance mid · exp(baza), baza = EWMA ln(Chainlink/Binance), jer se tržište rješava po Chainlinku |
| σ | EWMA varijanca 1-s log-povrata (half-life 300 s) |
| Fee (taker) | `fee = 0.25 · (p(1−p))²` po dionici (pri 0.50 to je 1.56¢); `a_eff = a + fee` |
| Nesigurnost q | `σ_q = √[(∂q/∂lnS · σ_baza)² + (φ(d)·|d|·ε_σ)²]` |
| Prag ulaska | `q − a_eff ≥ min_edge + z·σ_q` **i** `q − a_eff ≤ explain_mult·Δq_lag + slack` |
| Δq_lag | `∂q/∂lnS · ln(S_now / S_now−2s)`: koliko je svježi pomak Binancea trebao pomaknuti cijenu |
| Veličina | `x* = R·(q − a_eff)/(q(1−q)) − D`, gdje je `D = n_strana − n_druga`, a `R = kelly_mult·bankroll` |

Formula za veličinu je mean-variance optimum, `max E[PnL] − Var[PnL]/(2R)`, s varijancom `q(1−q)·D²`. Za male edgeove svodi se na frakcijski Kelly. Član `−D` automatski tjera bota da hedgea neuparene dionice.

Uvjet "edge objašnjen pomakom Binancea" najvažnija je zaštita. Ako model vidi edge, a Binance se nije pomaknuo, vjerojatnije je da griješi model (strike, baza, σ) nego da Polymarket kasni, pa bot ne trguje.

## Pokretanje

```bash
pip install -r requirements.txt
python -m pytest -q                       # testovi matematike i strategije
python simulate.py --windows 300          # Monte-Carlo, offline
python replay.py                          # zadnjih 10 STVARNIH 5-min prozora (prave Binance 1-s cijene)
python replay.py --last 20 --mm-lag 1.0   # više prozora / drugačije kašnjenje Polymarketa
python main.py                            # PAPER trading na živim podacima (default)
python main.py --binance-ws wss://stream.binance.us:9443/ws/btcusdt@bookTicker   # ako je binance.com blokiran
```

Live (pravi novac):
```bash
export POLY_PRIVATE_KEY=0x...          # privatni ključ walleta
export POLY_FUNDER=0x...               # proxy wallet adresa (ako koristiš Polymarket račun)
export POLY_SIGNATURE_TYPE=1           # 0=EOA, 1=email/Magic, 2=browser proxy
python main.py --live --bankroll 200 --max-window-usd 50
```

### Mali bankroll (npr. 50 €)

```bash
python replay.py --bankroll 50            # replay zadnjih 10 prozora s 50
python simulate.py --windows 300 --bankroll 50
python main.py --bankroll 50              # paper
python main.py --live --bankroll 50       # live
```

`--bankroll B` skalira limite: nalog 8% (4 za 50), prozor 20% (10), stop-loss 30% (15). Kad gubitak sesije dosegne stop-loss, bot se zaustavi. Kelly s malim bankrollom često traži manje od Polymarketova minimuma od 5 dionica. Ako želi barem 2.5 dionice, a knjiga i limit to dopuštaju, nalog se zaokruži na 5. Polymarket radi u USDC-u, pa je 50 € ≈ 50 € pretvoreno u USDC na Polygonu.

Svi parametri iz `polybot/config.py` mogu se postaviti kroz env, npr. `POLYBOT_MIN_EDGE=0.02`.
Logovi se pišu u `logs/trades.csv` i `logs/windows.csv`.

## Rezultati simulatora (300 prozora, exec latencija 0.25 s, 30% naloga ukrade konkurencija, fee uključen)

| Kašnjenje PM-a | PnL / prozor | std | "pogodak smjera" po nalogu |
|---|---|---|---|
| 0.0 s (samo requote 0.5 s) | +2.0 $ | 25.5 | 45% |
| 0.5 s | +8.0 $ | 36.0 | 47% |
| 1.0 s | +5.6 $ | 31.0 | 47% |
| 1.5 s | +8.8 $ | 35.1 | 48% |
| 2.0 s | +12.4 $ | 36.1 | 48% |

Kad kašnjenja nema i kotacije se osvježavaju svakih 0.1 s, edge pada na ≈0, što je i očekivano.

## Replay na stvarnim prozorima (`replay.py`)

Skripta povuče prave 1-sekundne BTCUSDT cijene s Binancea za zadnjih N završenih 5-min prozora. Uz njih uzme i 10 min prije, za procjenu volatilnosti. Bot zatim trguje na stvarnom kretanju BTC-a. Ispisuje tablicu po prozoru: strike, close, ishod, stvarni ishod na Polymarketu (ako je Gamma API dostupan), kupljene UP/DOWN dionice, fee, zaključani najgori PnL i PnL.

Povijesna Polymarket knjiga naloga nije javno dostupna, pa je **strana Polymarketa simulirana** (market maker koji kasni `--mm-lag` s). Kretanje BTC-a je stvarno, a koliko bi stvarno zaradio ovisi o tome koliko Polymarket u praksi kasni. Pravi odgovor daje tek `python main.py` u paper modu.

## ⚠️ Iskreno upozorenje

- Simulator modelira **naivnog** market makera koji ne povlači kotacije pri brzim pomacima. Pravi MM-ovi to rade, a Polymarket je fee na kratkoročna kripto tržišta uveo upravo zato da suzbije ovakav latency arb. Stvarni edge je vjerojatno puno manji od simuliranog.
- Pobjeđuje onaj s najmanjom latencijom (server blizu Polymarket/Binance infrastrukture, brzo potpisivanje naloga). Python + py-clob-client nije najbrži stack.
- Std po prozoru je 3–4× veći od prosjeka: gubitnički prozori su normalni, a profitabilnost se vidi tek kroz stotine prozora.
- Počni s **paper** modom, zatim live s malim iznosima. Usporedi `logs/windows.csv` sa simulacijom prije povećanja uloga.
- Provjeri smiješ li legalno koristiti Polymarket u svojoj zemlji.
