import 'market_filter.dart' show normalizeSearch;

/// Što korisnik traži (iz samog upita, npr. "aukcije", "uživo").
enum SearchKind { auction, buyNow, live }

/// Pametan upit: tipfeleri, sinonimi, cijena i vrsta u istom polju.
///
/// - "mobtel" nalazi "mobitel" (tipfeler),
/// - "telefon" nalazi i mobitele (sinonim),
/// - "tenisice do 50" ili "laptop < 300" filtrira po cijeni,
/// - "aukcije", "uživo", "kupi odmah" biraju vrstu objave.
class SmartQuery {
  const SmartQuery({
    this.terms = const [],
    this.minPrice,
    this.maxPrice,
    this.kind,
  });

  /// Normalizirani pojmovi (bez cijene i vrste).
  final List<String> terms;
  final double? minPrice;
  final double? maxPrice;
  final SearchKind? kind;

  bool get hasPrice => minPrice != null || maxPrice != null;
  bool get hasFilters => hasPrice || kind != null;
  bool get isEmpty => terms.isEmpty && !hasFilters;

  bool priceOk(double price) =>
      (minPrice == null || price >= minPrice!) &&
      (maxPrice == null || price <= maxPrice!);

  /// Svaki pojam mora naći riječ u [text] (početak riječi, sinonim ili
  /// tipfeler).
  bool matches(String text) => termsMatch(text, terms);

  static final _num = r'(\d+(?:[.,]\d+)?)';

  static double _n(String s) => double.parse(s.replaceAll(',', '.'));

  static SmartQuery parse(String raw) {
    var q = normalizeSearch(raw.replaceAll('@', ''));
    double? min, max;
    SearchKind? kind;

    // Raspon: "20-50", "20 – 50".
    final range = RegExp('$_num\\s*[-–]\\s*$_num').firstMatch(q);
    if (range != null) {
      min = _n(range.group(1)!);
      max = _n(range.group(2)!);
      q = q.replaceRange(range.start, range.end, ' ');
    }
    // "do 50", "ispod 50", "pod 50", "max 50", "<50", "<=50".
    final upper = RegExp(
      '(?:\\bdo\\b|\\bispod\\b|\\bpod\\b|\\bmax\\b|<=|<)\\s*$_num',
    ).firstMatch(q);
    if (upper != null) {
      max = _n(upper.group(1)!);
      q = q.replaceRange(upper.start, upper.end, ' ');
    }
    // "od 20", "preko 20", "iznad 20", "min 20", ">20", ">=20".
    final lower = RegExp(
      '(?:\\bod\\b|\\bpreko\\b|\\biznad\\b|\\bmin\\b|>=|>)\\s*$_num',
    ).firstMatch(q);
    if (lower != null) {
      min = _n(lower.group(1)!);
      q = q.replaceRange(lower.start, lower.end, ' ');
    }
    q = q.replaceAll(RegExp(r'€|\beur\b|\beura\b|\beuro\b'), ' ');

    // Vrsta objave.
    if (RegExp(r'\bkupi odmah\b').hasMatch(q)) {
      kind = SearchKind.buyNow;
      q = q.replaceAll(RegExp(r'\bkupi odmah\b'), ' ');
    }
    final words = q
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((w) => w.isNotEmpty)
        .toList();
    final terms = <String>[];
    for (final w in words) {
      if (RegExp(r'^(aukcij\w*|licitacij\w*)$').hasMatch(w)) {
        kind ??= SearchKind.auction;
      } else if (RegExp(r'^(uzivo|live|livea|liveovi|showovi?)$').hasMatch(w)) {
        kind ??= SearchKind.live;
      } else if (w == 'odmah') {
        kind ??= SearchKind.buyNow;
      } else {
        terms.add(w);
      }
    }
    return SmartQuery(terms: terms, minPrice: min, maxPrice: max, kind: kind);
  }
}

/// Skupine riječi s istim značenjem (normalizirane, bez dijakritike).
const _synonyms = <List<String>>[
  ['mobitel', 'mobiteli', 'telefon', 'telefoni', 'smartphone', 'smartfon'],
  ['laptop', 'laptopi', 'racunalo', 'racunala', 'prijenosnik', 'notebook'],
  ['slusalice', 'slusalica', 'headphones', 'earbuds'],
  ['konzola', 'konzole', 'console'],
  ['sat', 'satovi', 'ura', 'sati'],
  ['kamera', 'kamere', 'fotoaparat', 'fotoaparati'],
  ['kartica', 'kartice', 'karta', 'karte', 'card', 'cards'],
  ['strip', 'stripovi', 'manga', 'comic', 'comics'],
  ['kovanica', 'kovanice', 'novcanica', 'novcanice', 'novac'],
  ['marka', 'marke', 'markica'],
  ['figura', 'figure', 'figurica', 'igracka', 'igracke'],
  ['ploca', 'ploce', 'vinil', 'vinyl', 'gramofon'],
  ['instrument', 'instrumenti', 'glazbalo', 'glazbala'],
  ['knjiga', 'knjige', 'roman', 'knjizara'],
  ['igra', 'igre', 'igrica', 'igrice', 'videoigra', 'videoigre'],
  ['odjeca', 'odijelo', 'garderoba', 'moda'],
  ['tenisice', 'patike', 'tenisica', 'sneakers', 'sneaker', 'cipele'],
  ['torba', 'torbe', 'ruksak', 'tasna', 'torbica'],
  ['nakit', 'prsten', 'ogrlica', 'narukvica', 'nausnice', 'lancic'],
  ['slika', 'slike', 'crtez', 'crtezi', 'platno'],
  ['keramika', 'posuda', 'vaza', 'sale'],
  ['djecje', 'dijete', 'djeca', 'bebe', 'bebi'],
  ['dekor', 'ukras', 'ukrasi', 'dom'],
  ['bicikl', 'bicikli', 'bike'],
  ['vintage', 'antikvitet', 'antikviteti', 'retro'],
];

final Map<String, Set<String>> _synIndex = () {
  final m = <String, Set<String>>{};
  for (final g in _synonyms) {
    for (final w in g) {
      m.putIfAbsent(w, () => {}).addAll(g);
    }
  }
  return m;
}();

/// [term] i njegovi sinonimi (term je normaliziran).
Set<String> expandTerm(String term) {
  final out = {term};
  if (term.length < 3) return out;
  for (final e in _synIndex.entries) {
    if (e.key == term || (term.length >= 4 && e.key.startsWith(term))) {
      out.addAll(e.value);
    }
  }
  return out;
}

/// Najveći dopušteni broj pogrešnih slova (tipfeleri): kratke riječi
/// ("nike") moraju biti točne, dulje trpe 1 ili 2 pogreške.
int _allowedTypos(int length) => length >= 8
    ? 2
    : length >= 5
    ? 1
    : 0;

/// Udaljenost uređivanja (umetanje, brisanje, zamjena i zamjena susjednih
/// slova), prekida kad prijeđe [max].
int editDistance(String a, String b, int max) {
  if ((a.length - b.length).abs() > max) return max + 1;
  final d = List.generate(
    a.length + 1,
    (i) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = 0; i <= a.length; i++) {
    d[i][0] = i;
  }
  for (var j = 0; j <= b.length; j++) {
    d[0][j] = j;
  }
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = d[i - 1][j] + 1;
      if (d[i][j - 1] + 1 < v) v = d[i][j - 1] + 1;
      if (d[i - 1][j - 1] + cost < v) v = d[i - 1][j - 1] + cost;
      if (i > 1 &&
          j > 1 &&
          a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) &&
          a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1) &&
          d[i - 2][j - 2] + 1 < v) {
        v = d[i - 2][j - 2] + 1;
      }
      d[i][j] = v;
    }
  }
  return d[a.length][b.length];
}

bool _wordMatches(String word, String term) {
  if (word.startsWith(term)) return true;
  final typos = _allowedTypos(term.length);
  if (typos == 0) return false;
  // Cijela riječ ili njezin početak iste duljine kao pojam.
  if (editDistance(term, word, typos) <= typos) return true;
  if (word.length > term.length &&
      editDistance(term, word.substring(0, term.length), typos) <= typos) {
    return true;
  }
  return false;
}

/// Je li [term] (normaliziran) u nekoj od [words] — točno, sinonim ili
/// tipfeler.
bool termInWords(Iterable<String> words, String term) {
  final alts = expandTerm(term);
  for (final w in words) {
    for (final a in alts) {
      if (_wordMatches(w, a)) return true;
    }
  }
  return false;
}

/// Svaki pojam mora biti pronađen u [text] (tekst se normalizira ovdje).
bool termsMatch(String text, Iterable<String> terms) {
  final words = normalizeSearch(
    text,
  ).split(RegExp(r'[^\p{L}\p{N}]+', unicode: true));
  return terms.every((t) => termInWords(words, t));
}

/// Prijedlog ispravka ("Misliš li na…"): za svaki pojam koji ništa ne nalazi
/// najbliža riječ iz [vocabulary]. `null` ako nema što predložiti.
String? suggestQuery(List<String> terms, Iterable<String> vocabulary) {
  final vocab = {
    for (final v in vocabulary)
      for (final w in normalizeSearch(
        v,
      ).split(RegExp(r'[^\p{L}\p{N}]+', unicode: true)))
        if (w.length >= 3) w,
  };
  var changed = false;
  final out = <String>[];
  for (final t in terms) {
    if (vocab.any((w) => w.startsWith(t))) {
      out.add(t);
      continue;
    }
    String? best;
    var bestD = 3;
    for (final w in vocab) {
      final cut = w.length > t.length ? w.substring(0, t.length) : w;
      final d = [
        editDistance(t, w, 2),
        editDistance(t, cut, 2),
      ].reduce((a, b) => a < b ? a : b);
      if (d < bestD) {
        bestD = d;
        best = w;
      }
    }
    if (best != null && bestD <= 2 && bestD < t.length) {
      out.add(best);
      changed = true;
    } else {
      out.add(t);
    }
  }
  return changed ? out.join(' ') : null;
}
