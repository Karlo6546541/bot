import '../l10n/tr.dart';

/// Podaci prodavatelja koje platforma mora prikupiti prije objave (DAC7,
/// izvještaj Poreznoj upravi). Svi korisnici LICIT-a su fizičke osobe
/// (nema obrta ni tvrtki), pa je prodavatelj uvijek privatna osoba.
/// U demo verziji se ništa ne šalje — samo se spremaju uz račun.
class SellerInfo {
  const SellerInfo({
    required this.legalName,
    required this.oib,
    required this.address,
    required this.iban,
    required this.updatedAt,
    this.birthDate,
  });

  /// Ime i prezime.
  final String legalName;
  final String oib;
  final DateTime? birthDate;

  /// Adresa prebivališta.
  final String address;
  final String iban;
  final DateTime updatedAt;

  /// IBAN za prikaz: "HR12 •••• 0160".
  String get maskedIban {
    final s = iban.replaceAll(' ', '');
    if (s.length < 8) return s;
    return '${s.substring(0, 4)} •••• ${s.substring(s.length - 4)}';
  }

  Map<String, dynamic> toMap() => {
    'legalName': legalName,
    'oib': oib,
    if (birthDate != null) 'birthDate': birthDate!.toIso8601String(),
    'address': address,
    'iban': iban,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SellerInfo.fromMap(Map<dynamic, dynamic> m) => SellerInfo(
    legalName: m['legalName'] as String? ?? '',
    oib: m['oib'] as String? ?? '',
    birthDate: m['birthDate'] == null
        ? null
        : DateTime.tryParse('${m['birthDate']}'),
    address: m['address'] as String? ?? '',
    iban: m['iban'] as String? ?? '',
    updatedAt:
        DateTime.tryParse('${m['updatedAt']}') ??
        DateTime.fromMillisecondsSinceEpoch(0),
  );

  /// Hrvatski OIB: 11 znamenki, kontrolna znamenka ISO 7064 (MOD 11,10).
  static bool validOib(String value) {
    final s = value.trim();
    if (!RegExp(r'^\d{11}$').hasMatch(s)) return false;
    var a = 10;
    for (var i = 0; i < 10; i++) {
      a = (a + int.parse(s[i])) % 10;
      if (a == 0) a = 10;
      a = (a * 2) % 11;
    }
    var check = 11 - a;
    if (check == 10) check = 0;
    return check == int.parse(s[10]);
  }

  /// IBAN: oblik zemlje i kontrolni zbroj MOD 97.
  static bool validIban(String value) {
    final s = value.replaceAll(' ', '').toUpperCase();
    if (!RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(s)) return false;
    if (s.startsWith('HR') && s.length != 21) return false;
    final moved = s.substring(4) + s.substring(0, 4);
    var rest = 0;
    for (final ch in moved.split('')) {
      final code = ch.codeUnitAt(0);
      final digits = code >= 65 ? '${code - 55}' : ch;
      for (final d in digits.split('')) {
        rest = (rest * 10 + int.parse(d)) % 97;
      }
    }
    return rest == 1;
  }

  /// Greška u podacima (null = ispravno).
  static String? validate({
    required String legalName,
    required String oib,
    required String address,
    required String iban,
    DateTime? birthDate,
    DateTime? now,
  }) {
    if (legalName.trim().length < 3) return t('Upiši ime i prezime.');
    if (!validOib(oib)) return t('OIB nije ispravan (11 znamenki).');
    if (birthDate == null) return t('Upiši datum rođenja.');
    final at = now ?? DateTime.now();
    final adult = DateTime(birthDate.year + 18, birthDate.month, birthDate.day);
    if (adult.isAfter(at)) {
      return t('Prodavati mogu samo punoljetne osobe (18+).');
    }
    if (address.trim().length < 5) return t('Upiši adresu.');
    if (!validIban(iban)) return t('IBAN nije ispravan.');
    return null;
  }
}
