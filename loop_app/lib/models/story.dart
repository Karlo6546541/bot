import 'package:flutter/painting.dart' show Color;

/// Priča (story) trgovine: vidljiva 24 sata. Može prikazivati oglas
/// ("Novo stiglo", "Danas −20%"), tekst na boji ili fotografiju.
class Story {
  const Story({
    required this.id,
    required this.userId,
    required this.createdAt,
    this.text = '',
    this.deviceId,
    this.imagePath,
    this.color = 0,
  });

  final String id;
  final String userId;
  final String text;

  /// Oglas koji priča prikazuje (s cijenom i gumbom "Pogledaj").
  final String? deviceId;

  /// Fotografija priče.
  final String? imagePath;

  /// Indeks boje pozadine iz [palettes].
  final int color;
  final DateTime createdAt;

  static const lifetime = Duration(hours: 24);
  static const maxText = 120;

  /// Pozadine priča (gradijenti).
  static const palettes = <List<Color>>[
    [Color(0xFFFF2D55), Color(0xFF7B2FF7)],
    [Color(0xFFFF9500), Color(0xFFFF2D55)],
    [Color(0xFF00C6FB), Color(0xFF005BEA)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFF232526), Color(0xFF414345)],
    [Color(0xFFF7971E), Color(0xFFFFD200)],
  ];

  DateTime get expiresAt => createdAt.add(lifetime);

  bool activeAt(DateTime now) => now.isBefore(expiresAt);

  List<Color> get gradient => palettes[color % palettes.length];

  Map<String, dynamic> toMap() => {
    'id': id,
    'userId': userId,
    'text': text,
    'deviceId': deviceId,
    'imagePath': imagePath,
    'color': color,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Story.fromMap(Map<dynamic, dynamic> m) => Story(
    id: m['id'] as String,
    userId: m['userId'] as String,
    text: m['text'] as String? ?? '',
    deviceId: m['deviceId'] as String?,
    imagePath: m['imagePath'] as String?,
    color: (m['color'] as num?)?.toInt() ?? 0,
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}
