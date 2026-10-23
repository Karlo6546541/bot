import 'dart:math';

/// Naknade LOOP-a (kao Whatnot: kupac ne plaća naknadu, provizija se
/// odbija prodavatelju od isplate):
/// - **Kupi odmah**: [kBuyNowRate] od cijene;
/// - **aukcija i live**: [kAuctionUpliftRate] samo od razlike između
///   prodajne i početne cijene ("plaćaš samo ono što je licitacija dodala").
///   Ako se predmet proda po početnoj cijeni, provizije nema.

/// Kupac ne plaća naknadu platforme.
const double kFeeRate = 0.0;

/// Provizija za Kupi odmah (od cijene).
const double kBuyNowRate = 0.05;

/// Provizija za aukcije i live (od razlike iznad početne cijene).
const double kAuctionUpliftRate = 0.10;

/// Zaokruživanje na cente (2 decimale).
double roundCredits(double value) => (value * 100).roundToDouble() / 100;

/// Naknada koju kupac plaća na zadanu cijenu (0 — kupac plaća samo cijenu).
double feeFor(double price) => roundCredits(price * kFeeRate);

/// Provizija za Kupi odmah.
double buyNowCommission(double price) => roundCredits(price * kBuyNowRate);

/// Iznos koji prodavatelj dobije za Kupi odmah (cijena − 5 %).
double sellPayout(double price) =>
    roundCredits(price - buyNowCommission(price));

/// Provizija za aukciju ili live: 10 % od razlike iznad početne cijene.
double auctionCommission(double price, double startPrice) =>
    roundCredits(max(0, price - startPrice) * kAuctionUpliftRate);

/// Iznos koji prodavatelj dobije za aukciju ili live.
double auctionPayout(double price, double startPrice) =>
    roundCredits(price - auctionCommission(price, startPrice));

/// Iznos koji kupac plati (bez dostave). To je i cijena koju kupac vidi.
double buyTotal(double price) => roundCredits(price + feeFor(price));

/// Obratno: iz iznosa koji kupac plaća (npr. ponuda) cijena oglasa.
double listPriceFor(double buyerAmount) =>
    roundCredits(buyerAmount / (1 + kFeeRate));
