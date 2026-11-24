/// Lista želja (kolekcija): npr. "Za stan", "Pokloni". Sprema se uz profil
/// korisnika, a može se podijeliti poveznicom.
class Wishlist {
  const Wishlist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.emoji = '🎁',
    this.deviceIds = const [],
  });

  final String id;
  final String name;
  final String emoji;
  final List<String> deviceIds;
  final DateTime createdAt;

  static const maxName = 30;
  static const maxLists = 20;
  static const maxItems = 100;

  /// Ponuđeni simboli za novu listu.
  static const emojis = [
    '🎁',
    '🏠',
    '👕',
    '🎮',
    '📚',
    '🎧',
    '🚲',
    '💍',
    '🧸',
    '⭐',
  ];

  Wishlist copyWith({String? name, String? emoji, List<String>? deviceIds}) =>
      Wishlist(
        id: id,
        name: name ?? this.name,
        emoji: emoji ?? this.emoji,
        deviceIds: deviceIds ?? this.deviceIds,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'emoji': emoji,
    'deviceIds': deviceIds,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Wishlist.fromMap(Map<dynamic, dynamic> m) => Wishlist(
    id: m['id'] as String,
    name: m['name'] as String? ?? '',
    emoji: m['emoji'] as String? ?? '🎁',
    deviceIds: (m['deviceIds'] as List?)?.cast<String>() ?? const [],
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}
