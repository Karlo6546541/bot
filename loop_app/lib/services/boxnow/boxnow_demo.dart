import '../../models/delivery.dart';
import 'lockers.dart';

/// Demo integracija paketomata (BOX NOW, GLS, DPD) (bez pravog API-ja): pošiljka dobiva BOX NOW
/// broj (javni, iz ID-ja pošiljke), nasumičan PIN za predaju (prodavač) i
/// PIN za preuzimanje (kupac), a praćenje prati korake pošiljke. S pravim
/// partnerskim API-jem ove vrijednosti vraća BOX NOW.
class BoxNowDemo {
  const BoxNowDemo._();

  static int _hash(String s, int salt) {
    var h = 17 + salt;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  static String _digits(String s, int salt, int n) =>
      (_hash(s, salt) % _pow10(n)).toString().padLeft(n, '0');

  static int _pow10(int n) {
    var p = 1;
    for (var i = 0; i < n; i++) {
      p *= 10;
    }
    return p;
  }

  /// Mreža paketomata pošiljke.
  static LockerNetwork network(Delivery d) => LockerNetwork.ofDelivery(d);

  /// Broj pošiljke u formatu mreže: BOX NOW 10 znamenki, GLS 11, DPD 14.
  static String parcelId(Delivery d) => switch (network(d)) {
    LockerNetwork.boxNow => '92${_digits(d.id, 1, 8)}',
    LockerNetwork.gls => '5${_digits(d.id, 4, 9)}${_digits(d.id, 5, 1)}',
    LockerNetwork.dpd => '0${_digits(d.id, 6, 7)}${_digits(d.id, 7, 6)}',
  };

  /// PIN koji prodavač upiše na paketomatu kad predaje paket (nasumičan,
  /// spremljen uz pošiljku; stare pošiljke bez PIN-a imaju zamjenski).
  static String dropOffPin(Delivery d) => d.dropOffPin ?? _digits(d.id, 2, 6);

  /// PIN kojim kupac otvara pretinac (vidi ga kad paket stigne).
  static String pickupPin(Delivery d) => d.pickupPin ?? _digits(d.id, 3, 6);

  /// Praćenje kao u aplikaciji dostavljača: (opis, kada, gotovo).
  static List<(String, DateTime?, bool)> events(Delivery d, DateTime now) {
    final cur = d.stepIndex(now);
    final labels = network(d).eventLabels;
    return [
      for (var i = 0; i < labels.length && i < d.steps.length; i++)
        (
          labels[i],
          i == d.steps.length - 1 && d.confirmedAt != null
              ? d.confirmedAt
              : d.stepAt(i),
          i <= cur,
        ),
    ];
  }
}
