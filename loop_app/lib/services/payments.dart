import '../l10n/tr.dart';
import 'trade_service.dart';

/// Vrsta kartice prema prvim znamenkama (BIN).
enum CardBrand {
  visa('Visa'),
  mastercard('Mastercard'),
  amex('American Express'),
  maestro('Maestro'),
  unknown('Kartica');

  const CardBrand(this.label);
  final String label;

  static CardBrand of(String number) {
    final n = digitsOnly(number);
    if (n.startsWith('4')) return visa;
    if (RegExp(r'^(5[1-5]|2[2-7])').hasMatch(n)) return mastercard;
    if (RegExp(r'^3[47]').hasMatch(n)) return amex;
    if (RegExp(r'^(50|5[6-9]|6)').hasMatch(n)) return maestro;
    return unknown;
  }

  int get cvcLength => this == amex ? 4 : 3;
  int get maxLength => this == amex ? 15 : 19;
}

/// Način plaćanja koji se sprema korisniku: samo oznaka (marka i zadnje
/// 4 znamenke), nikad puni broj ni CVC.
enum WalletKind {
  googlePay('Google Pay'),
  applePay('Apple Pay');

  const WalletKind(this.label);
  final String label;
}

String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

/// Luhnova provjera broja kartice.
bool luhnValid(String number) {
  final n = digitsOnly(number);
  if (n.length < 12) return false;
  var sum = 0;
  var alt = false;
  for (var i = n.length - 1; i >= 0; i--) {
    var d = n.codeUnitAt(i) - 48;
    if (alt) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
    alt = !alt;
  }
  return sum % 10 == 0;
}

/// "Visa •••• 4242"
String cardLabel(String number) {
  final n = digitsOnly(number);
  return '${CardBrand.of(n).label} •••• ${n.substring(n.length - 4)}';
}

/// Testne kartice (kao Stripeov testni način): svaka se ponaša drukčije.
class TestCards {
  static const success = '4242 4242 4242 4242';
  static const mastercard = '5555 5555 5555 4444';
  static const amex = '3782 822463 10005';
  static const declined = '4000 0000 0000 0002';
  static const insufficient = '4000 0000 0000 9995';

  static const all = [success, mastercard, amex, declined, insufficient];
}

/// Testni pružatelj plaćanja. Provjerava podatke kao pravi obrazac i
/// "tokenizira" karticu — vraća samo oznaku za spremanje.
///
/// Za prava plaćanja (sljedeći korak): Stripe (Payment Element ili
/// Payment Request Button za Google/Apple Pay) i SetupIntent na
/// poslužitelju (Supabase Edge Function s tajnim ključem); spremljeni
/// `payment_method` se zatim naplaćuje "off_session" kad kupac pobijedi.
class TestPayments {
  /// Greška u obrascu (null = ispravno).
  static String? validate(
    String number,
    String expiry,
    String cvc, {
    DateTime? now,
  }) {
    final n = digitsOnly(number);
    final brand = CardBrand.of(n);
    if (n.length < 13 || n.length > brand.maxLength || !luhnValid(n)) {
      return t('Broj kartice nije ispravan.');
    }
    final m = RegExp(r'^(\d{2})\s*/\s*(\d{2})$').firstMatch(expiry.trim());
    final month = int.tryParse(m?.group(1) ?? '');
    final year = int.tryParse(m?.group(2) ?? '');
    if (month == null || year == null || month < 1 || month > 12) {
      return t('Upiši datum isteka kao MM/GG.');
    }
    final at = now ?? DateTime.now();
    // Kartica vrijedi do kraja mjeseca isteka.
    final end = DateTime(2000 + year, month + 1);
    if (!end.isAfter(at)) return t('Kartica je istekla.');
    if (digitsOnly(cvc).length != brand.cvcLength) {
      return t('CVC ima {0} znamenke.', ['${brand.cvcLength}']);
    }
    return null;
  }

  /// Sprema karticu kod (testnog) pružatelja; testne odbijene kartice
  /// javljaju grešku kao prava banka.
  static String tokenize(
    String number,
    String expiry,
    String cvc, {
    DateTime? now,
  }) {
    final error = validate(number, expiry, cvc, now: now);
    if (error != null) throw TradeException(error);
    final n = digitsOnly(number);
    if (n == digitsOnly(TestCards.declined)) {
      throw TradeException(t('Banka je odbila karticu. Pokušaj drugu.'));
    }
    if (n == digitsOnly(TestCards.insufficient)) {
      throw TradeException(t('Na kartici nema dovoljno sredstava.'));
    }
    return cardLabel(n);
  }

  /// Google Pay / Apple Pay: novčanik vraća token kartice (u testu Visa).
  static String wallet(WalletKind kind) =>
      '${kind.label} · ${cardLabel(TestCards.success)}';
}
