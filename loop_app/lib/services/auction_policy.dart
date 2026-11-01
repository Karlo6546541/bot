import 'dart:math';

import '../models/auction.dart';
import '../models/device.dart';
import '../utils/formatters.dart';
import 'fee.dart';
import 'storage_service.dart';
import '../l10n/tr.dart';

/// Pravila koja sprječavaju masovno stavljanje svega na aukcije.
///
/// Aukcije kreću od 1 € (kao na Whatnotu); pravila samo sprječavaju
/// masovno objavljivanje. Pravila:
/// - najviše [maxActive] aktivnih aukcija po korisniku;
/// - najviše [maxNewPerDay] novih aukcija u 24 sata;
/// - predmet mora vrijediti barem [minItemValue] kredita;
/// - naknada za objavu: [listingFeeRate] vrijednosti predmeta (najmanje
///   [minListingFee]), ne vraća se ni ako se aukcija otkaže ili ne uspije;
/// - predmet koji se nije prodao može ponovno na aukciju tek nakon
///   [relistCooldown].
class AuctionPolicy {
  AuctionPolicy(this._storage);

  final StorageService _storage;

  static const maxNewPerDay = 10;
  static const minItemValue = 1.0;

  /// Objava aukcije je besplatna (provizija se plaća tek od razlike).
  static const listingFeeRate = 0.0;
  static const minListingFee = 0.0;
  static const relistCooldown = Duration(hours: 24);

  static const maxActive = 10;

  /// Trgovci (obrt, tvrtka) prodaju više — veća ograničenja.
  static const businessMaxActive = 200;
  static const businessMaxNewPerDay = 200;

  bool _business(String userId) => _storage.userById(userId)?.isTrader ?? false;

  int maxActiveFor(String userId) =>
      _business(userId) ? businessMaxActive : maxActive;

  int maxNewPerDayFor(String userId) =>
      _business(userId) ? businessMaxNewPerDay : maxNewPerDay;

  /// Naknada za objavu — računa se od vrijednosti predmeta, a ne od početne
  /// cijene, kako se ne bi mogla izbjeći niskom početnom cijenom.
  static double listingFee(Device d) =>
      max(minListingFee, roundCredits(d.price * listingFeeRate));

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
    final active = maxActiveFor(userId);
    if (activeCount(userId) >= active) {
      return t(
        'Imaš već {0} aktivne aukcije — to je najviše. Pričekaj da neka završi ili prodaj na Kupi odmah.',
        [active],
      );
    }
    final perDay = maxNewPerDayFor(userId);
    if (createdLast24h(userId, now: now) >= perDay) {
      return t('Danas si već objavio {0} aukcije. Nove možeš sutra.', [perDay]);
    }
    if (device.price < minItemValue) {
      return t(
        'Na aukciju idu predmeti vrijedni barem {0}. Ovaj prodaj na Kupi odmah.',
        [formatCredits(minItemValue)],
      );
    }
    final until = cooldownUntil(device.id, now: now);
    if (until != null) {
      return t(
        'Ovaj predmet se nije prodao na aukciji. Ponovno ga možeš objaviti od {0} — ili ga prodaj odmah.',
        [formatDateTime(until)],
      );
    }
    return null;
  }
}
