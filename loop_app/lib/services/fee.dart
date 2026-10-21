/// Naknada platforme: plaća je samo KUPAC (2% na cijenu). Prodavatelj
/// dobiva punu cijenu — bez naknade.
const double kFeeRate = 0.02;

/// Naknada za prodavatelja (0 — prodaja je besplatna).
const double kSellerFeeRate = 0.0;

/// Zaokruživanje na cente (2 decimale).
double roundCredits(double value) => (value * 100).roundToDouble() / 100;

/// Naknada koju kupac plaća na zadanu cijenu.
double feeFor(double price) => roundCredits(price * kFeeRate);

/// Iznos koji prodavatelj dobije: puna cijena (bez naknade).
double sellPayout(double price) => roundCredits(price - price * kSellerFeeRate);

/// Iznos koji kupac plati: cijena + 2%. To je i cijena koju kupac vidi.
double buyTotal(double price) => roundCredits(price + feeFor(price));

/// Obratno: iz iznosa koji kupac plaća (npr. ponuda) cijena oglasa.
double listPriceFor(double buyerAmount) =>
    roundCredits(buyerAmount / (1 + kFeeRate));
