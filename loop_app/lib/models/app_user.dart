/// Korisnik aplikacije. Krediti su LOOP krediti — ne mogu se isplatiti,
/// koriste se isključivo za kupnju unutar aplikacije.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.credits,
    required this.createdAt,
    this.isGuest = false,
    this.favorites = const [],
  });

  final String id;
  final String email;
  final String name;
  final double credits;
  final bool isGuest;
  final DateTime createdAt;

  /// ID-evi uređaja koje je korisnik označio srcem (lista želja).
  final List<String> favorites;

  AppUser copyWith({double? credits, List<String>? favorites}) => AppUser(
    id: id,
    email: email,
    name: name,
    credits: credits ?? this.credits,
    createdAt: createdAt,
    isGuest: isGuest,
    favorites: favorites ?? this.favorites,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'email': email,
    'name': name,
    'credits': credits,
    'isGuest': isGuest,
    'favorites': favorites,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AppUser.fromMap(Map<dynamic, dynamic> map) => AppUser(
    id: map['id'] as String,
    email: map['email'] as String,
    name: map['name'] as String,
    credits: (map['credits'] as num).toDouble(),
    isGuest: map['isGuest'] as bool? ?? false,
    // Stariji zapisi nemaju ovo polje.
    favorites: (map['favorites'] as List?)?.cast<String>() ?? const [],
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
