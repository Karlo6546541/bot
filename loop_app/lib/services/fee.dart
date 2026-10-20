/// Fee platforme — uvijek 5% na svaku transakciju.
const double kFeeRate = 0.05;

/// Zaokruživanje na 2 decimale (krediti se prikazuju s centima).
double roundCredits(double value) => (value * 100).roundToDouble() / 100;

/// Fee za zadanu cijenu.
double feeFor(double price) => roundCredits(price * kFeeRate);

/// Iznos koji prodavatelj dobije: cijena − 5%.
double sellPayout(double price) => roundCredits(price - feeFor(price));

/// Iznos koji kupac plati: cijena + 5%.
double buyTotal(double price) => roundCredits(price + feeFor(price));
