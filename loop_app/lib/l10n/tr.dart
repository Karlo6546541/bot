import 'en.dart';

/// Jezik sučelja.
enum AppLang {
  hr('Hrvatski', '🇭🇷', 'HR'),
  en('English', '🇬🇧', 'EN');

  const AppLang(this.nativeName, this.flag, this.code);
  final String nativeName;
  final String flag;
  final String code;

  static AppLang fromName(String? n) =>
      AppLang.values.firstWhere((l) => l.name == n, orElse: () => AppLang.hr);
}

/// Aktivni jezik. Postavlja ga `LoopApp` (iz postavki) prije izgradnje
/// sučelja; promjena jezika ponovno gradi cijelu aplikaciju.
class Tr {
  static AppLang lang = AppLang.hr;

  /// Tekstovi bez engleskog prijevoda (testovi provjeravaju da je prazno).
  static final missing = <String>{};
}

/// Prevodi tekst. Ključ je hrvatski tekst; `{0}`, `{1}`… zamjenjuju se
/// vrijednostima iz [args]. Bez prijevoda vraća hrvatski tekst.
String t(String hr, [List<Object?> args = const []]) {
  var s = hr;
  if (Tr.lang == AppLang.en) {
    final en = kEn[hr];
    if (en != null) {
      s = en;
    } else {
      Tr.missing.add(hr);
    }
  }
  for (var i = 0; i < args.length; i++) {
    s = s.replaceAll('{$i}', '${args[i]}');
  }
  return s;
}
