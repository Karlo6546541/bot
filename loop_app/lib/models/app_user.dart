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
  });

  final String id;
  final String email;
  final String name;
  final double credits;
  final bool isGuest;
  final DateTime createdAt;

  AppUser copyWith({double? credits}) => AppUser(
    id: id,
    email: email,
    name: name,
    credits: credits ?? this.credits,
    createdAt: createdAt,
    isGuest: isGuest,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'email': email,
    'name': name,
    'credits': credits,
    'isGuest': isGuest,
    'createdAt': createdAt.toIso8601String(),
  };

  factory AppUser.fromMap(Map<dynamic, dynamic> map) => AppUser(
    id: map['id'] as String,
    email: map['email'] as String,
    name: map['name'] as String,
    credits: (map['credits'] as num).toDouble(),
    isGuest: map['isGuest'] as bool? ?? false,
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
