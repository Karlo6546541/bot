import '../models/app_user.dart';
import '../models/loop_transaction.dart';

/// Jedan prodavatelj u DAC7 izvještaju za kalendarsku godinu.
class Dac7Seller {
  const Dac7Seller({
    required this.user,
    required this.sales,
    required this.amount,
  });

  final AppUser user;

  /// Broj prodaja (uključujući aukcije i nadoplate u zamjenama).
  final int sales;

  /// Ukupni iznos koji je prodavatelj primio (naknada kupca nije uključena).
  final double amount;

  /// DAC7: prijavljuju se prodavatelji s 30+ prodaja ili više od 2.000 €.
  bool get reportable => sales >= Dac7.minSales || amount > Dac7.minAmount;

  /// Nedostaju podaci prodavatelja potrebni za prijavu.
  bool get missingData => user.seller == null;
}

/// DAC7 (Direktiva 2021/514): platforma godišnje (do 31. siječnja) Poreznoj
/// upravi dostavlja podatke o prodavateljima i njihovim primicima.
class Dac7 {
  static const minSales = 30;
  static const minAmount = 2000.0;

  /// Prodavatelji s barem jednom prodajom u godini [year], najveći prvi.
  static List<Dac7Seller> sellers(
    List<AppUser> users,
    List<LoopTransaction> transactions,
    int year,
  ) {
    final sales = <String, int>{};
    final amounts = <String, double>{};
    for (final tx in transactions) {
      final seller = tx.sellerId;
      if (seller == null || tx.createdAt.year != year) continue;
      final isSale =
          tx.type == TransactionType.sell ||
          (tx.type == TransactionType.swap && tx.userId == seller);
      if (!isSale) continue;
      sales[seller] = (sales[seller] ?? 0) + 1;
      amounts[seller] = (amounts[seller] ?? 0) + tx.price;
    }
    final out = [
      for (final u in users)
        if (sales.containsKey(u.id))
          Dac7Seller(
            user: u,
            sales: sales[u.id]!,
            amount: ((amounts[u.id] ?? 0) * 100).round() / 100,
          ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return out;
  }

  /// CSV za knjigovođu / Poreznu upravu (samo prodavatelji koje treba
  /// prijaviti).
  static String csv(List<Dac7Seller> sellers, int year) {
    String cell(Object? v) {
      final s = '${v ?? ''}';
      return s.contains(RegExp(r'[",;\n]'))
          ? '"${s.replaceAll('"', '""')}"'
          : s;
    }

    final rows = <List<Object?>>[
      [
        'godina',
        'korisnik',
        'ime_prezime',
        'oib',
        'datum_rodenja',
        'adresa',
        'iban',
        'broj_prodaja',
        'iznos_eur',
        'naknade_platforme_eur',
        'nedostaju_podaci',
      ],
      for (final s in sellers.where((s) => s.reportable))
        [
          year,
          s.user.handle,
          s.user.seller?.legalName ?? '',
          s.user.seller?.oib ?? '',
          s.user.seller?.birthDate?.toIso8601String().substring(0, 10) ?? '',
          s.user.seller?.address ?? '',
          s.user.seller?.iban ?? '',
          s.sales,
          s.amount.toStringAsFixed(2),
          // Prodavatelj ne plaća naknadu (plaća je kupac).
          '0.00',
          s.missingData ? 'da' : 'ne',
        ],
    ];
    return rows.map((r) => r.map(cell).join(';')).join('\n');
  }
}
