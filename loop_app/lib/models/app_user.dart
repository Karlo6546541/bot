/// Korisnik aplikacije. Krediti su LOOP krediti — ne mogu se isplatiti,
/// koriste se isključivo za kupnju unutar aplikacije.
///
/// Ovo je javni profil (u online načinu ga vide svi testeri), pa ne sadrži
/// lozinku. Lokalne lozinke su u zasebnom, nesinkroniziranom boxu, a online
/// prijavu vodi Supabase Auth.
class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.credits,
    required this.createdAt,
    String? username,
    this.isGuest = false,
    this.favorites = const [],
    this.address,
    this.bio = '',
    this.city,
    this.avatarPath,
    this.emailVerified = false,
    this.authProvider = 'email',
    this.formerUsername,
    this.usernameChangedAt,
    this.blockedIds = const [],
    this.referredBy,
    this.deletionRequestedAt,
  }) : username = username ?? '';

  final String id;

  /// E-mail za prijavu. U online načinu se ne sprema u javni profil
  /// (prazan string) — e-mail trenutnog korisnika daje Supabase Auth.
  final String email;
  final String name;
  final double credits;
  final bool isGuest;
  final DateTime createdAt;

  /// Jedinstveno korisničko ime (mala slova), prikazuje se kao `@username`.
  final String username;

  /// ID-evi uređaja koje je korisnik označio srcem (lista želja).
  final List<String> favorites;

  /// Zadnja adresa za dostavu (predlaže se pri sljedećoj kupnji).
  final String? address;

  /// Kratki opis na profilu (do [maxBio] znakova).
  final String bio;
  final String? city;

  /// Profilna fotografija (putanja iz `ImageStore`).
  final String? avatarPath;

  /// Potvrđen e-mail (ili prijava Googleom) — bedž "Provjeren".
  final bool emailVerified;

  /// 'email' | 'google' | 'guest'.
  final String authProvider;

  /// Prethodno korisničko ime — zaključano [usernameLockDays] dana nakon
  /// promjene, da ga nitko ne preuzme.
  final String? formerUsername;
  final DateTime? usernameChangedAt;

  /// Blokirani korisnici: njihovi predmeti i aukcije se ne prikazuju.
  final List<String> blockedIds;

  /// Korisnik čiji je kod za poziv upisan pri registraciji.
  final String? referredBy;

  /// Zatraženo brisanje računa (briše se nakon [deletionGraceDays] dana,
  /// a prijava u tom roku ga vraća).
  final DateTime? deletionRequestedAt;

  static const maxBio = 160;
  static const usernameLockDays = 30;
  static const deletionGraceDays = 7;

  /// "@karlo_99" (ili ime za starije zapise bez korisničkog imena).
  String get handle => username.isEmpty ? name : '@$username';

  /// Prikazno ime: ime ako postoji, inače korisničko ime.
  String get displayName => name.isNotEmpty ? name : handle;

  bool get pendingDeletion => deletionRequestedAt != null;

  /// Kada se može ponovno promijeniti korisničko ime.
  DateTime? get nextUsernameChange =>
      usernameChangedAt?.add(const Duration(days: usernameLockDays));

  AppUser copyWith({
    double? credits,
    List<String>? favorites,
    String? address,
    String? name,
    String? username,
    String? bio,
    String? city,
    String? avatarPath,
    bool clearAvatar = false,
    bool? emailVerified,
    String? formerUsername,
    DateTime? usernameChangedAt,
    List<String>? blockedIds,
    String? referredBy,
    DateTime? deletionRequestedAt,
    bool clearDeletion = false,
    String? email,
  }) => AppUser(
    id: id,
    email: email ?? this.email,
    name: name ?? this.name,
    credits: credits ?? this.credits,
    createdAt: createdAt,
    username: username ?? this.username,
    isGuest: isGuest,
    favorites: favorites ?? this.favorites,
    address: address ?? this.address,
    bio: bio ?? this.bio,
    city: city ?? this.city,
    avatarPath: clearAvatar ? null : avatarPath ?? this.avatarPath,
    emailVerified: emailVerified ?? this.emailVerified,
    authProvider: authProvider,
    formerUsername: formerUsername ?? this.formerUsername,
    usernameChangedAt: usernameChangedAt ?? this.usernameChangedAt,
    blockedIds: blockedIds ?? this.blockedIds,
    referredBy: referredBy ?? this.referredBy,
    deletionRequestedAt: clearDeletion
        ? null
        : deletionRequestedAt ?? this.deletionRequestedAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'email': email,
    'name': name,
    'username': username,
    'credits': credits,
    'isGuest': isGuest,
    'favorites': favorites,
    'address': address,
    'bio': bio,
    'city': city,
    'avatarPath': avatarPath,
    'emailVerified': emailVerified,
    'authProvider': authProvider,
    'formerUsername': formerUsername,
    'usernameChangedAt': usernameChangedAt?.toIso8601String(),
    'blockedIds': blockedIds,
    'referredBy': referredBy,
    'deletionRequestedAt': deletionRequestedAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
  };

  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse('$v');

  factory AppUser.fromMap(Map<dynamic, dynamic> map) => AppUser(
    id: map['id'] as String,
    email: map['email'] as String? ?? '',
    name: map['name'] as String? ?? '',
    credits: (map['credits'] as num).toDouble(),
    // Stariji zapisi nemaju sljedeća polja.
    username: map['username'] as String? ?? '',
    isGuest: map['isGuest'] as bool? ?? false,
    favorites: (map['favorites'] as List?)?.cast<String>() ?? const [],
    address: map['address'] as String?,
    bio: map['bio'] as String? ?? '',
    city: map['city'] as String?,
    avatarPath: map['avatarPath'] as String?,
    emailVerified: map['emailVerified'] as bool? ?? false,
    authProvider: map['authProvider'] as String? ?? 'email',
    formerUsername: map['formerUsername'] as String?,
    usernameChangedAt: _date(map['usernameChangedAt']),
    blockedIds: (map['blockedIds'] as List?)?.cast<String>() ?? const [],
    referredBy: map['referredBy'] as String?,
    deletionRequestedAt: _date(map['deletionRequestedAt']),
    createdAt: DateTime.parse(map['createdAt'] as String),
  );
}
