import '../models/loop_transaction.dart';
import 'fee.dart';
import 'storage_service.dart';

/// Zarada prodavača iz prodaja (Kupi odmah, aukcija, live).
///
/// Prodaju upisuje uređaj kupca ili pobjednika, a stanje prodavača je u
/// njegovom profilu — dvije prodaje u istoj sekundi s dva uređaja mogle bi
/// prepisati jedna drugu. Zato profil pamti i KOJE su prodaje uračunate
/// ([AppUser.creditedSales]), zapisano zajedno sa stanjem: ako se izgubi
/// zarada, izgubi se i oznaka, pa je [reconcile] (bilo koji uređaj s
/// potpunim podacima) ponovno uračuna. Nikad dvaput, nikad izgubljeno.
class Earnings {
  Earnings(this._storage);

  final StorageService _storage;

  /// Prodaje koje donose zaradu: jedinstveni zapis prodaje s fiksnim ID-jem.
  static bool counts(LoopTransaction t, String sellerId) =>
      t.type == TransactionType.sell &&
      t.userId == sellerId &&
      t.sellerId == sellerId &&
      (t.id.startsWith('sale-') ||
          t.id.startsWith('auction-') ||
          t.id.startsWith('live-'));

  Iterable<LoopTransaction> _sales(String sellerId) =>
      _storage.transactions.where((t) => counts(t, sellerId));

  /// Uračunava prodaju [tx] prodavaču (jednom).
  Future<void> credit(LoopTransaction tx) async {
    final sellerId = tx.userId;
    final user = _storage.userById(sellerId);
    if (user == null) return;
    // Stariji račun: dosadašnje prodaje su već u stanju — samo se označe.
    final done = [
      ...user.creditedSales ??
          [
            for (final t in _sales(sellerId))
              if (t.id != tx.id) t.id,
          ],
    ];
    if (done.contains(tx.id)) {
      if (user.creditedSales == null) {
        await _storage.putUser(user.copyWith(creditedSales: done));
      }
      return;
    }
    await _storage.putUser(
      user.copyWith(
        credits: roundCredits(user.credits + tx.amount),
        creditedSales: [...done, tx.id],
      ),
    );
  }

  /// Uračunava prodaje koje nedostaju (npr. prepisane istovremenom
  /// prodajom s drugog uređaja). Vraća broj dodanih.
  Future<int> reconcile(String sellerId) async {
    final user = _storage.userById(sellerId);
    if (user == null) return 0;
    final done = user.creditedSales;
    if (done == null) {
      // Prvo pokretanje: sve postojeće prodaje su već u stanju.
      await _storage.putUser(
        user.copyWith(creditedSales: [for (final t in _sales(sellerId)) t.id]),
      );
      return 0;
    }
    final missing = [
      for (final t in _sales(sellerId))
        if (!done.contains(t.id)) t,
    ];
    if (missing.isEmpty) return 0;
    await _storage.putUser(
      user.copyWith(
        credits: roundCredits(
          user.credits + missing.fold<double>(0, (s, t) => s + t.amount),
        ),
        creditedSales: [...done, for (final t in missing) t.id],
      ),
    );
    return missing.length;
  }
}
