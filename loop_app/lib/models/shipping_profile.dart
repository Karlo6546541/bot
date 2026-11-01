import '../l10n/tr.dart';
import 'delivery.dart';

/// Profil dostave prodavača (kao Whatnot "Shipping Profile"): težina,
/// dimenzije paketa i koliko predmeta stane u jedan paket. Iz težine i
/// dimenzija se računa [ParcelSize] (cijena dostave), a [maxItems] određuje
/// kad počinje novi plaćeni paket pri spajanju kupnji iz istog livea.
class ShippingProfile {
  const ShippingProfile({
    required this.id,
    required this.name,
    required this.weightGrams,
    this.lengthCm = 0,
    this.widthCm = 0,
    this.heightCm = 0,
    this.maxItems = 0,
  });

  final String id;
  final String name;
  final int weightGrams;
  final int lengthCm;
  final int widthCm;
  final int heightCm;

  /// Najviše predmeta u jednom paketu; 0 = bez ograničenja.
  final int maxItems;

  static const maxName = 40;

  bool get hasDimensions => lengthCm > 0 && widthCm > 0 && heightCm > 0;

  /// Veličina paketa iz težine i zbroja dimenzija (kao kod kurira).
  ParcelSize get parcelSize {
    final sum = lengthCm + widthCm + heightCm;
    if (weightGrams <= 2000 && sum <= 90) return ParcelSize.small;
    if (weightGrams <= 10000 && sum <= 150) return ParcelSize.medium;
    if (weightGrams <= 30000 && sum <= 250) return ParcelSize.large;
    return ParcelSize.bulky;
  }

  String get weightLabel => weightGrams < 1000
      ? '$weightGrams g'
      : '${(weightGrams / 1000).toStringAsFixed(weightGrams % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} kg';

  String get dimensionsLabel =>
      hasDimensions ? '$lengthCm × $widthCm × $heightCm cm' : '';

  /// Kratki opis: "1,2 kg · 30 × 20 × 10 cm · do 5 u paketu".
  String get summary => [
    weightLabel,
    if (hasDimensions) dimensionsLabel,
    if (maxItems > 0) t('do {0} u paketu', ['$maxItems']),
  ].join(' · ');

  /// Provjera unosa; vraća poruku greške ili `null`.
  static String? validate({
    required String name,
    required int weightGrams,
    required int lengthCm,
    required int widthCm,
    required int heightCm,
    required int maxItems,
  }) {
    if (name.trim().length < 2) return t('Upiši naziv profila.');
    if (name.trim().length > maxName) {
      return t('Naziv može imati najviše {0} znakova.', ['$maxName']);
    }
    if (weightGrams <= 0 || weightGrams > 70000) {
      return t('Težina mora biti između 1 g i 70 kg.');
    }
    final dims = [lengthCm, widthCm, heightCm];
    if (dims.any((d) => d < 0 || d > 300)) {
      return t('Dimenzije moraju biti do 300 cm.');
    }
    if (dims.any((d) => d > 0) && dims.any((d) => d == 0)) {
      return t('Upiši sve tri dimenzije ili nijednu.');
    }
    if (maxItems < 0 || maxItems > 50) {
      return t('U paket stane od 1 do 50 predmeta.');
    }
    return null;
  }

  ShippingProfile copyWith({
    String? name,
    int? weightGrams,
    int? lengthCm,
    int? widthCm,
    int? heightCm,
    int? maxItems,
  }) => ShippingProfile(
    id: id,
    name: name ?? this.name,
    weightGrams: weightGrams ?? this.weightGrams,
    lengthCm: lengthCm ?? this.lengthCm,
    widthCm: widthCm ?? this.widthCm,
    heightCm: heightCm ?? this.heightCm,
    maxItems: maxItems ?? this.maxItems,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'weightGrams': weightGrams,
    if (lengthCm > 0) 'lengthCm': lengthCm,
    if (widthCm > 0) 'widthCm': widthCm,
    if (heightCm > 0) 'heightCm': heightCm,
    if (maxItems > 0) 'maxItems': maxItems,
  };

  factory ShippingProfile.fromMap(Map<dynamic, dynamic> m) => ShippingProfile(
    id: m['id'] as String? ?? '',
    name: m['name'] as String? ?? '',
    weightGrams: (m['weightGrams'] as num?)?.toInt() ?? 0,
    lengthCm: (m['lengthCm'] as num?)?.toInt() ?? 0,
    widthCm: (m['widthCm'] as num?)?.toInt() ?? 0,
    heightCm: (m['heightCm'] as num?)?.toInt() ?? 0,
    maxItems: (m['maxItems'] as num?)?.toInt() ?? 0,
  );
}
