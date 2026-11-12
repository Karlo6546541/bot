import 'live_show.dart';

/// Vrsta promocije livea.
///
/// * [quick]: brzi boost na 15 minuta dok je live u tijeku (plaća domaćin).
/// * [show]: promocija zakazanog showa, vrijedi od plaćanja do kraja showa.
/// * [community]: besplatan boost na 15 minuta kad dovoljno gledatelja
///   podijeli live ([LiveBoost.communityGoal]).
enum BoostKind { quick, show, community }

/// Stanje promocije showa, izračunato iz događaja [LiveEventType.boost]
/// i [LiveEventType.share] (isto na svim uređajima, bez nove tablice).
///
/// Promovirani liveovi idu prvi na početnoj i u kategoriji, uz oznaku
/// "Promovirano" (oglas mora biti jasno označen).
class LiveBoost {
  const LiveBoost({
    this.kind,
    this.until,
    this.weight = 0,
    this.spent = 0,
    this.sharers = 0,
    this.communityUnlocked = false,
  });

  static const none = LiveBoost();

  /// Trajanje brzog i community boosta.
  static const quickMinutes = 15;

  /// Koliko različitih gledatelja treba podijeliti live za community boost.
  static const communityGoal = 10;

  /// Najmanji iznos brzog boosta i promocije showa, najveći iznos.
  static const minQuick = 1.0;
  static const minShow = 3.0;
  static const maxAmount = 50.0;

  /// Promocija showa traje najdulje toliko nakon početka showa.
  static const showPromoAfterStart = Duration(hours: 3);

  /// Aktivna promocija (najjača ako ih je više), ili `null`.
  final BoostKind? kind;

  /// Do kad traje aktivna promocija.
  final DateTime? until;

  /// Snaga promocije za poredak: plaćeni iznos aktivnih promocija, a
  /// community boost vrijedi kao 2 €.
  final double weight;

  /// Ukupno plaćeno za promocije ovog showa.
  final double spent;

  /// Koliko je različitih gledatelja podijelilo show.
  final int sharers;

  /// Community boost je otključan (jednom po showu).
  final bool communityUnlocked;

  bool get active => kind != null;

  /// Procijenjeni broj prikaza za iznos (oko 60 prikaza po euru).
  static int estimatedReach(double amount) => (amount * 60).round();

  /// Predloženi raspon za brzi boost: više gledatelja, više konkurencije.
  static (double, double) suggestedQuick(int viewers) {
    final low = (2 + viewers / 25).clamp(2, 20).roundToDouble();
    return (low, low + 3);
  }

  /// Predloženi raspon za promociju zakazanog showa.
  static (double, double) suggestedShow(int reminders) {
    final low = (5 + reminders / 10).clamp(5, 30).roundToDouble();
    return (low, low + 5);
  }

  /// Izračun iz događaja showa u trenutku [now]. [liveFrom] je kad je live
  /// stvarno krenuo (community boost ne teče prije početka).
  static LiveBoost of(
    LiveShow show,
    Iterable<LiveEvent> events,
    DateTime now, {
    DateTime? liveFrom,
  }) {
    final boosts = [
      for (final e in events)
        if (e.type == LiveEventType.boost) e,
    ]..sort((a, b) => a.at.compareTo(b.at));
    var spent = 0.0;
    var weight = 0.0;
    BoostKind? kind;
    DateTime? until;
    void consider(BoostKind k, DateTime from, DateTime to, double w) {
      if (now.isBefore(from) || !now.isBefore(to)) return;
      weight += w;
      // Najjača vrsta se prikazuje; plaćena ima prednost pred besplatnom.
      if (kind == null || kind == BoostKind.community) {
        kind = k;
        until = to;
      } else if (k == kind && to.isAfter(until!)) {
        until = to;
      }
    }

    // Brzi boostovi se nižu: novi koji je kupljen dok traje prethodni
    // počinje kad prethodni završi.
    DateTime? quickEnd;
    for (final e in boosts) {
      spent += e.amount;
      switch (e.text) {
        case 'quick':
          final from = quickEnd != null && quickEnd.isAfter(e.at)
              ? quickEnd
              : e.at;
          final to = from.add(const Duration(minutes: quickMinutes));
          quickEnd = to;
          consider(BoostKind.quick, from, to, e.amount);
        case 'show':
          final end = show.startsAt.add(showPromoAfterStart);
          consider(
            BoostKind.show,
            e.at,
            show.endedAt != null && show.endedAt!.isBefore(end)
                ? show.endedAt!
                : end,
            e.amount,
          );
      }
    }

    // Community boost: N-ti različiti gledatelj koji je podijelio show.
    final seen = <String>{};
    DateTime? unlockedAt;
    final shares = [
      for (final e in events)
        if (e.type == LiveEventType.share && e.userId != show.hostId) e,
    ]..sort((a, b) => a.at.compareTo(b.at));
    for (final e in shares) {
      if (e.at.isAfter(now)) break;
      if (seen.add(e.userId) && seen.length == communityGoal) {
        unlockedAt = e.at;
      }
    }
    if (unlockedAt != null) {
      final start = liveFrom != null && liveFrom.isAfter(unlockedAt)
          ? liveFrom
          : unlockedAt;
      if (liveFrom != null) {
        consider(
          BoostKind.community,
          start,
          start.add(const Duration(minutes: quickMinutes)),
          2,
        );
      }
    }
    return LiveBoost(
      kind: kind,
      until: until,
      weight: weight,
      spent: spent,
      sharers: seen.length,
      communityUnlocked: unlockedAt != null,
    );
  }
}
