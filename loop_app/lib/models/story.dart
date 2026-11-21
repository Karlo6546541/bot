import 'package:flutter/painting.dart' show Color, TextAlign;

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
    this.texts = const [],
  });

  final String id;
  final String userId;

  /// Sav tekst priče (za starije verzije i pretragu); izgled je u [texts].
  final String text;

  /// Tekstovi postavljeni po pozadini (položaj, veličina, font, boja…).
  final List<StoryText> texts;

  /// Oglas koji priča prikazuje (s cijenom i gumbom "Pogledaj").
  final String? deviceId;

  /// Fotografija priče.
  final String? imagePath;

  /// Indeks boje pozadine iz [palettes].
  final int color;
  final DateTime createdAt;

  static const lifetime = Duration(hours: 24);
  static const maxText = 120;

  /// Najviše tekstova na jednoj priči.
  static const maxTexts = 6;

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

  /// Tekstovi za prikaz; starije priče imaju samo [text] (u sredini).
  List<StoryText> get layers => texts.isNotEmpty
      ? texts
      : text.isEmpty
      ? const []
      : [
          StoryText(
            text: text,
            y: deviceId == null && imagePath == null ? 0.45 : 0.3,
          ),
        ];

  Map<String, dynamic> toMap() => {
    'id': id,
    'userId': userId,
    'text': text,
    'deviceId': deviceId,
    'imagePath': imagePath,
    'color': color,
    if (texts.isNotEmpty) 'texts': [for (final x in texts) x.toMap()],
    'createdAt': createdAt.toIso8601String(),
  };

  factory Story.fromMap(Map<dynamic, dynamic> m) => Story(
    id: m['id'] as String,
    userId: m['userId'] as String,
    text: m['text'] as String? ?? '',
    deviceId: m['deviceId'] as String?,
    imagePath: m['imagePath'] as String?,
    color: (m['color'] as num?)?.toInt() ?? 0,
    texts: [
      for (final x in (m['texts'] as List?) ?? const [])
        if (x is Map) StoryText.fromMap(x),
    ],
    createdAt: DateTime.parse(m['createdAt'] as String),
  );
}

/// Fontovi teksta u priči.
enum StoryFont { classic, modern, neon, typewriter, script }

/// Pozadina iza teksta: bez, puna boja ili poluprozirna.
enum StoryTextBackground { none, solid, soft }

/// Jedan tekst na priči — može se pomicati, povećavati i rotirati.
class StoryText {
  const StoryText({
    required this.text,
    this.x = 0.5,
    this.y = 0.45,
    this.size = defaultSize,
    this.rotation = 0,
    this.color = 0xFFFFFFFF,
    this.font = StoryFont.classic,
    this.align = TextAlign.center,
    this.background = StoryTextBackground.none,
  });

  final String text;

  /// Središte teksta kao udio širine/visine priče (0–1).
  final double x;
  final double y;

  /// Veličina slova kao udio širine priče.
  final double size;

  /// Rotacija u radijanima.
  final double rotation;
  final int color;
  final StoryFont font;
  final TextAlign align;
  final StoryTextBackground background;

  static const defaultSize = 0.085;
  static const minSize = 0.04;
  static const maxSize = 0.25;

  /// Boje teksta.
  static const colors = <int>[
    0xFFFFFFFF,
    0xFF000000,
    0xFFFF2D55,
    0xFFFF9500,
    0xFFFFD60A,
    0xFF34C759,
    0xFF0A84FF,
    0xFFBF5AF2,
    0xFFFF6FB5,
  ];

  StoryText copyWith({
    String? text,
    double? x,
    double? y,
    double? size,
    double? rotation,
    int? color,
    StoryFont? font,
    TextAlign? align,
    StoryTextBackground? background,
  }) => StoryText(
    text: text ?? this.text,
    x: x ?? this.x,
    y: y ?? this.y,
    size: size ?? this.size,
    rotation: rotation ?? this.rotation,
    color: color ?? this.color,
    font: font ?? this.font,
    align: align ?? this.align,
    background: background ?? this.background,
  );

  /// Vrijednosti unutar dopuštenih granica (i za podatke iz baze).
  StoryText normalized() => copyWith(
    text: text.trim(),
    x: x.clamp(0.0, 1.0),
    y: y.clamp(0.0, 1.0),
    size: size.clamp(minSize, maxSize),
  );

  Map<String, dynamic> toMap() => {
    'text': text,
    'x': x,
    'y': y,
    'size': size,
    'rotation': rotation,
    'color': color,
    'font': font.name,
    'align': align.name,
    'background': background.name,
  };

  factory StoryText.fromMap(Map<dynamic, dynamic> m) {
    double d(String k, double fallback) =>
        (m[k] as num?)?.toDouble() ?? fallback;
    T byName<T extends Enum>(List<T> values, String k, T fallback) =>
        values.where((v) => v.name == m[k]).firstOrNull ?? fallback;
    return StoryText(
      text: m['text'] as String? ?? '',
      x: d('x', 0.5),
      y: d('y', 0.45),
      size: d('size', defaultSize),
      rotation: d('rotation', 0),
      color: (m['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
      font: byName(StoryFont.values, 'font', StoryFont.classic),
      align: byName(TextAlign.values, 'align', TextAlign.center),
      background: byName(
        StoryTextBackground.values,
        'background',
        StoryTextBackground.none,
      ),
    ).normalized();
  }
}
