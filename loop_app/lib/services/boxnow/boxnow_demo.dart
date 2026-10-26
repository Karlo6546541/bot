import '../../l10n/tr.dart';
import '../../models/delivery.dart';

/// Demo BOX NOW integracija (bez pravog API-ja): pošiljka dobiva BOX NOW
/// broj, PIN za predaju (prodavač) i PIN za preuzimanje (kupac), a
/// praćenje prati korake pošiljke. Sve je izvedeno iz pošiljke, pa je
/// isto na svakom uređaju. S pravim partnerskim API-jem ove vrijednosti
/// vraća BOX NOW.
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

  /// BOX NOW broj pošiljke (10 znamenki).
  static String parcelId(Delivery d) => '92${_digits(d.id, 1, 8)}';

  /// PIN koji prodavač upiše na paketomatu kad predaje paket.
  static String dropOffPin(Delivery d) => _digits(d.id, 2, 6);

  /// PIN kojim kupac otvara pretinac (vidi ga kad paket stigne).
  static String pickupPin(Delivery d) => _digits(d.id, 3, 6);

  /// Praćenje u stilu BOX NOW-a: (opis, kada, gotovo).
  static List<(String, DateTime?, bool)> events(Delivery d, DateTime now) {
    final cur = d.stepIndex(now);
    final labels = [
      t('Pošiljka prijavljena u BOX NOW'),
      t('Prodavač predao paket u paketomat'),
      t('BOX NOW: u transportu'),
      t('Stiglo u paketomat kupca'),
      t('Kupac preuzeo paket'),
    ];
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
