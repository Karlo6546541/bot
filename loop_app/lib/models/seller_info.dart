import '../l10n/tr.dart';

/// Vrsta prodavatelja: privatna osoba (prodaje svoje stvari) ili trgovac
/// (obrt, tvrtka — prodaje kao djelatnost). Kupci vide razliku jer o njoj
/// ovise njihova prava (DSA, zaštita potrošača).
enum SellerKind {
  private('Privatna osoba'),
  business('Trgovac (obrt ili tvrtka)');

  const SellerKind(this._label);
  final String _label;
  String get label => t(_label);

  static SellerKind fromName(String? n) =>
      n == business.name ? business : private;
}

/// Pravni oblik trgovca.
enum LegalForm {
  obrt('Obrt'),
  jdoo('j.d.o.o.'),
  doo('d.o.o.'),
  dd('d.d.'),
  other('Ostalo');

  const LegalForm(this._label);
  final String _label;
  String get label => t(_label);

  static LegalForm fromName(String? n) =>
      LegalForm.values.firstWhere((v) => v.name == n, orElse: () => obrt);
}

/// Podaci prodavatelja koje platforma mora prikupiti prije objave (DAC7,
/// izvještaj Poreznoj upravi; DSA čl. 30 za trgovce). Prodavatelj je
/// privatna osoba ili trgovac (obrt/tvrtka) — trgovac upisuje i naziv
/// tvrtke, OIB tvrtke, kontakt i (neobavezno) PDV broj i registarski broj.
/// U demo verziji se ništa ne šalje — samo se spremaju uz račun.
class SellerInfo {
  const SellerInfo({
    required this.legalName,
    required this.oib,
    required this.address,
    required this.iban,
    required this.updatedAt,
    this.birthDate,
    this.kind = SellerKind.private,
    this.companyName = '',
    this.legalForm = LegalForm.obrt,
    this.vatId = '',
    this.registryNumber = '',
    this.contactEmail = '',
    this.contactPhone = '',
  });

  /// Ime i prezime (kod trgovca: odgovorna osoba / vlasnik).
  final String legalName;

  /// OIB osobe, a kod trgovca OIB obrta ili tvrtke.
  final String oib;
  final DateTime? birthDate;

  /// Adresa prebivališta (kod trgovca: sjedište).
  final String address;

  final SellerKind kind;

  /// Trgovac: naziv obrta ili tvrtke (npr. "Retro Kutak j.d.o.o.").
  final String companyName;
  final LegalForm legalForm;

  /// PDV identifikacijski broj (npr. HR12345678901) — samo ako je u sustavu PDV-a.
  final String vatId;

  /// MBS (sudski registar) ili MBO (obrtni registar).
  final String registryNumber;
  final String contactEmail;
  final String contactPhone;

  bool get isBusiness => kind == SellerKind.business;

  /// Ime koje kupac vidi uz oznaku trgovca.
  String get tradeName => isBusiness && companyName.trim().isNotEmpty
      ? companyName.trim()
      : legalName;
  final String iban;
  final DateTime updatedAt;

  /// IBAN za prikaz: "HR12 •••• 0160".
  String get maskedIban {
    final s = iban.replaceAll(' ', '');
    if (s.length < 8) return s;
    return '${s.substring(0, 4)} •••• ${s.substring(s.length - 4)}';
  }

  Map<String, dynamic> toMap() => {
    if (isBusiness) ...{
      'kind': kind.name,
      'companyName': companyName,
      'legalForm': legalForm.name,
      if (vatId.isNotEmpty) 'vatId': vatId,
      if (registryNumber.isNotEmpty) 'registryNumber': registryNumber,
      'contactEmail': contactEmail,
      'contactPhone': contactPhone,
    },
    'legalName': legalName,
    'oib': oib,
    if (birthDate != null) 'birthDate': birthDate!.toIso8601String(),
    'address': address,
    'iban': iban,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory SellerInfo.fromMap(Map<dynamic, dynamic> m) => SellerInfo(
    kind: SellerKind.fromName(m['kind'] as String?),
    companyName: m['companyName'] as String? ?? '',
    legalForm: LegalForm.fromName(m['legalForm'] as String?),
    vatId: m['vatId'] as String? ?? '',
    registryNumber: m['registryNumber'] as String? ?? '',
    contactEmail: m['contactEmail'] as String? ?? '',
    contactPhone: m['contactPhone'] as String? ?? '',
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
    SellerKind kind = SellerKind.private,
    String companyName = '',
    String vatId = '',
    String contactEmail = '',
    String contactPhone = '',
  }) {
    if (kind == SellerKind.business) {
      if (companyName.trim().length < 3) {
        return t('Upiši naziv obrta ili tvrtke.');
      }
      if (legalName.trim().length < 3) {
        return t('Upiši ime i prezime odgovorne osobe.');
      }
      if (!validOib(oib)) return t('OIB nije ispravan (11 znamenki).');
      final vat = vatId.replaceAll(' ', '').toUpperCase();
      if (vat.isNotEmpty &&
          !(vat.startsWith('HR') && validOib(vat.substring(2)))) {
        return t('PDV broj upiši kao HR + OIB (npr. HR12345678901).');
      }
      if (address.trim().length < 5) return t('Upiši adresu sjedišta.');
      if (!RegExp(
        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
      ).hasMatch(contactEmail.trim())) {
        return t('Upiši e-mail za kupce.');
      }
      if (contactPhone.replaceAll(RegExp(r'[^0-9]'), '').length < 6) {
        return t('Upiši telefon za kupce.');
      }
      if (!validIban(iban)) return t('IBAN nije ispravan.');
      return null;
    }
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

/// Javni podaci trgovca (DSA: trgovac mora biti prepoznatljiv s podacima
/// za kontakt). Spremaju se uz javni profil, pa ih vide svi korisnici —
/// za razliku od [SellerInfo] (IBAN, datum rođenja… ostaju privatni).
class TraderPublic {
  const TraderPublic({
    required this.name,
    required this.address,
    required this.oib,
    this.vatId = '',
    this.email = '',
    this.phone = '',
  });

  factory TraderPublic.of(SellerInfo i) => TraderPublic(
    name: i.tradeName,
    address: i.address,
    oib: i.oib,
    vatId: i.vatId,
    email: i.contactEmail,
    phone: i.contactPhone,
  );

  final String name;
  final String address;
  final String oib;
  final String vatId;
  final String email;
  final String phone;

  Map<String, dynamic> toMap() => {
    'name': name,
    'address': address,
    'oib': oib,
    'vatId': vatId,
    'email': email,
    'phone': phone,
  };

  static TraderPublic? fromMap(Object? m) => m is Map
      ? TraderPublic(
          name: m['name'] as String? ?? '',
          address: m['address'] as String? ?? '',
          oib: m['oib'] as String? ?? '',
          vatId: m['vatId'] as String? ?? '',
          email: m['email'] as String? ?? '',
          phone: m['phone'] as String? ?? '',
        )
      : null;
}
