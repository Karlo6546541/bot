import 'dart:math';

import '../models/auction.dart';
import '../models/device.dart';
import '../models/user_status.dart';
import '../utils/formatters.dart';
import 'fee.dart';
import 'storage_service.dart';

/// Pravila koja sprječavaju masovno stavljanje svega na aukcije.
///
/// Aukcije su za vrijedne ili tražene predmete; za sve ostalo je Market
/// (trenutna prodaja, bez naknade za objavu). Pravila:
/// - limit aktivnih aukcija ovisi o statusu (Bronze 2, Silver 4, Gold 6);
/// - najviše [maxNewPerDay] novih aukcija u 24 sata;
/// - predmet mora vrijediti barem [minItemValue] kredita;
/// - naknada za objavu: [listingFeeRate] vrijednosti predmeta (najmanje
///   [minListingFee]), ne vraća se ni ako se aukcija otkaže ili ne uspije;
/// - predmet koji se nije prodao može ponovno na aukciju tek nakon
///   [relistCooldown].
class AuctionPolicy {
  AuctionPolicy(this._storage);

  final StorageService _storage;

  static const maxNewPerDay = 3;
  static const minItemValue = 50.0;
  static const listingFeeRate = 0.02;
  static const minListingFee = 2.0;
  static const relistCooldown = Duration(hours: 24);

  static int maxActiveFor(UserStatus status) => switch (status) {
    UserStatus.bronze => 2,
    UserStatus.silver => 4,
    UserStatus.gold => 6,
  };

  /// Naknada za objavu — računa se od vrijednosti predmeta, a ne od početne
  /// cijene, kako se ne bi mogla izbjeći niskom početnom cijenom.
  static double listingFee(Device d) =>
      max(minListingFee, roundCredits(d.price * listingFeeRate));

  /// Status prema ukupnoj vrijednosti (krediti + blokirano + portfolio).
  UserStatus statusOf(String userId) {
    final user = _storage.userById(userId);
    if (user == null) return UserStatus.bronze;
    final portfolio = _storage.devices
        .where((d) => d.ownerId == userId)
        .fold(0.0, (sum, d) => sum + d.price);
    return UserStatus.fromTotalValue(
      user.credits + _storage.heldCredits(userId) + portfolio,
    );
  }

  int activeCount(String userId) =>
      _storage.auctions.where((a) => a.isActive && a.sellerId == userId).length;

  int createdLast24h(String userId, {DateTime? now}) {
    final since = (now ?? DateTime.now()).subtract(const Duration(days: 1));
    return _storage.auctions
        .where((a) => a.sellerId == userId && a.createdAt.isAfter(since))
        .length;
  }

  /// Do kada predmet ne smije ponovno na aukciju (null = smije).
  DateTime? cooldownUntil(String deviceId, {DateTime? now}) {
    final at = now ?? DateTime.now();
    DateTime? until;
    for (final a in _storage.auctions) {
      if (a.deviceId != deviceId || a.status != AuctionStatus.unsold) continue;
      final end = a.endsAt.add(relistCooldown);
      if (end.isAfter(at) && (until == null || end.isAfter(until))) {
        until = end;
      }
    }
    return until;
  }

  /// Razlog zbog kojeg korisnik ne može staviti predmet na aukciju,
  /// ili `null` ako može. Redoslijed: najprije pravila o korisniku,
  /// zatim o predmetu.
  String? blockReason(String userId, Device device, {DateTime? now}) {
    final status = statusOf(userId);
    final limit = maxActiveFor(status);
    if (activeCount(userId) >= limit) {
      return 'Imaš već $limit aktivne aukcije — najviše za status '
          '${status.label}. Pričekaj da neka završi ili prodaj na Marketu.';
    }
    if (createdLast24h(userId, now: now) >= maxNewPerDay) {
      return 'Danas si već objavio $maxNewPerDay aukcije. Nove možeš sutra.';
    }
    if (device.price < minItemValue) {
      return 'Na aukciju idu predmeti vrijedni barem '
          '${formatCredits(minItemValue)}. Ovaj prodaj na Marketu.';
    }
    final until = cooldownUntil(device.id, now: now);
    if (until != null) {
      return 'Ovaj predmet se nije prodao na aukciji. Ponovno ga možeš '
          'objaviti od ${formatDateTime(until)} — ili ga prodaj odmah.';
    }
    final user = _storage.userById(userId);
    final fee = listingFee(device);
    if (user != null && user.credits < fee) {
      return 'Za naknadu objave treba ${formatCredits(fee)}, '
          'a imaš ${formatCredits(user.credits)}.';
    }
    return null;
  }
}
