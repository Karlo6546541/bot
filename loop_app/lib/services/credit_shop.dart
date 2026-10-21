import 'package:uuid/uuid.dart';

import '../models/loop_transaction.dart';
import '../utils/formatters.dart';
import 'fee.dart';
import 'storage_service.dart';
import 'trade_service.dart';
import '../l10n/tr.dart';

/// Paket kredita. 1 kredit = 1 €, veći paketi donose bonus kredite.
class CreditPackage {
  const CreditPackage({
    required this.credits,
    this.bonus = 0,
    this.popular = false,
  });

  final int credits;
  final int bonus;
  final bool popular;

  int get total => credits + bonus;
  double get priceEur => credits.toDouble();
}

/// Način plaćanja (samo za prikaz — demo ništa ne naplaćuje i ne traži
/// podatke kartice).
enum PaymentMethod {
  card('Kartica', 'Visa, Mastercard, Maestro'),
  applePay('Apple Pay', 'Brzo plaćanje s iPhonea'),
  googlePay('Google Pay', 'Brzo plaćanje s Androida'),
  paypal('PayPal', 'Plaćanje PayPal računom');

  const PaymentMethod(this._label, this._subtitle);
  final String _label;
  String get label => t(_label);
  final String _subtitle;
  String get subtitle => t(_subtitle);
}

/// Kupnja LOOP kredita (simulirana). Pravila:
/// - 1 kredit = 1 €; paketi od 250 naviše daju bonus kredite;
/// - vlastiti iznos od [minAmount] do [maxSingle] kredita;
/// - dnevni limit od [dailyLimit] kupljenih kredita (bez bonusa) u 24 h;
/// - kupljeni krediti se, kao i svi ostali, ne mogu isplatiti natrag.
class CreditShop {
  CreditShop(this._storage);

  final StorageService _storage;
  final _uuid = const Uuid();

  static const packages = <CreditPackage>[
    CreditPackage(credits: 50),
    CreditPackage(credits: 100),
    CreditPackage(credits: 250, bonus: 10),
    CreditPackage(credits: 500, bonus: 30, popular: true),
    CreditPackage(credits: 1000, bonus: 80),
  ];

  static const minAmount = 10;
  static const maxSingle = 2000;
  static const dailyLimit = 2000;

  /// Bonus za vlastiti iznos: isti prag kao kod paketa.
  static int bonusFor(int credits) {
    var bonus = 0;
    for (final p in packages) {
      if (credits >= p.credits) bonus = p.bonus;
    }
    return bonus;
  }

  /// Koliko je korisnik kupio (bez bonusa) u zadnja 24 sata.
  double boughtLast24h(String userId, {DateTime? now}) {
    final since = (now ?? DateTime.now()).subtract(const Duration(days: 1));
    return _storage.transactions
        .where(
          (t) =>
              t.type == TransactionType.topUp &&
              t.userId == userId &&
              t.createdAt.isAfter(since),
        )
        .fold(0.0, (sum, t) => sum + t.price);
  }

  /// Preostali dnevni limit.
  double remainingToday(String userId, {DateTime? now}) =>
      (dailyLimit - boughtLast24h(userId, now: now))
          .clamp(0, dailyLimit)
          .toDouble();

  /// Kupuje [credits] kredita (+ bonus) i vraća zapis transakcije.
  Future<LoopTransaction> purchase({
    required String userId,
    required int credits,
    required PaymentMethod method,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final user = _storage.userById(userId);
    if (user == null) throw TradeException(t('Korisnik ne postoji.'));
    if (credits < minAmount || credits > maxSingle) {
      throw TradeException(
        t('Iznos mora biti između {0} i {1} kredita.', [minAmount, maxSingle]),
      );
    }
    final left = remainingToday(userId, now: at);
    if (credits > left) {
      throw TradeException(
        t('Dnevni limit je {0} kredita. Danas možeš kupiti još {1}.', [
          dailyLimit,
          formatCredits(left),
        ]),
      );
    }

    final bonus = bonusFor(credits);
    final total = credits + bonus;
    await _storage.putUser(
      user.copyWith(credits: roundCredits(user.credits + total)),
    );
    final tx = LoopTransaction(
      id: _uuid.v4(),
      type: TransactionType.topUp,
      userId: userId,
      deviceId: '',
      deviceName: bonus > 0
          ? '$credits + $bonus bonus kredita · ${method.label}'
          : '$credits kredita · ${method.label}',
      // Za dopune je cijena iznos u eurima, a iznos broj dobivenih kredita.
      price: credits.toDouble(),
      fee: 0,
      amount: total.toDouble(),
      buyerId: userId,
      buyerLabel: user.handle,
      sellerLabel: 'LOOP',
      createdAt: at,
    );
    await _storage.putTransaction(tx);
    await _storage.recordSnapshot(userId, now: at);
    return tx;
  }
}
