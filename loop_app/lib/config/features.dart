/// Uključene vrste prodaje.
///
/// Aplikacija nudi aukcije i Kupi odmah (fiksna cijena). Kupi odmah
/// (fiksna cijena, uključujući digitalne proizvode, shop u liveu i
/// istaknuti proizvod) uključuje se s
/// `--dart-define=BUY_NOW_ENABLED=true`; postojeći oglasi ostaju u bazi.
const kBuyNowEnabled = bool.fromEnvironment(
  'BUY_NOW_ENABLED',
  defaultValue: true,
);

/// Live prijenosi (show, live aukcije, studio). Aplikacija je trenutno samo
/// za aukcije, pa je isključen; `--dart-define=LIVE_ENABLED=true` ga vraća.
const kLiveEnabled = bool.fromEnvironment('LIVE_ENABLED', defaultValue: false);
