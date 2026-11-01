/// Local recommendation controls, scoped to one account by StorageService.
/// No recommendation controls or browsing history are shared with sellers.
class FeedPreferences {
  FeedPreferences({
    Map<String, int>? seen,
    Set<String>? hidden,
    Set<String>? sellers,
    Map<String, double>? less,
    Map<String, double>? models,
    Map<String, double>? conditions,
  }) : seen = seen ?? {},
       hidden = hidden ?? {},
       sellers = sellers ?? {},
       less = less ?? {},
       models = models ?? {},
       conditions = conditions ?? {};

  final Map<String, int> seen;
  final Set<String> hidden;
  final Set<String> sellers;
  final Map<String, double> less;
  final Map<String, double> models;
  final Map<String, double> conditions;

  factory FeedPreferences.fromMap(Map? map) {
    Map<String, double> weights(String key) => {
      for (final e in (map?[key] as Map? ?? {}).entries)
        if (e.value is num) '${e.key}': (e.value as num).toDouble(),
    };
    return FeedPreferences(
      seen: {
        for (final e in (map?['seen'] as Map? ?? {}).entries)
          if (e.value is int) '${e.key}': e.value as int,
      },
      hidden: Set<String>.from(map?['hidden'] as List? ?? []),
      sellers: Set<String>.from(map?['sellers'] as List? ?? []),
      less: weights('less'),
      models: weights('models'),
      conditions: weights('conditions'),
    );
  }

  bool seenRecently(String key, DateTime now) {
    final at = seen[key];
    return at != null &&
        now.difference(DateTime.fromMillisecondsSinceEpoch(at)) <
            const Duration(hours: 24);
  }

  void recordSeen(String key, DateTime at) {
    seen.remove(key);
    seen[key] = at.millisecondsSinceEpoch;
    while (seen.length > 500) {
      seen.remove(seen.keys.first);
    }
  }

  void hide(String key) {
    hidden.add(key);
    if (hidden.length > 1000) hidden.remove(hidden.first);
  }

  void hideSeller(String id) {
    sellers.add(id);
    if (sellers.length > 500) sellers.remove(sellers.first);
  }

  void learnModel(String model, String condition) {
    final key = model.trim().toLowerCase();
    if (key.length >= 2) {
      models[key] = ((models[key] ?? 0) + 0.5).clamp(0, 2).toDouble();
      if (models.length > 50) models.remove(models.keys.first);
    }
    conditions[condition] = ((conditions[condition] ?? 0) + 0.1)
        .clamp(0, 0.5)
        .toDouble();
  }

  Map<String, dynamic> toMap() => {
    'seen': seen,
    'hidden': hidden.toList(),
    'sellers': sellers.toList(),
    'less': less,
    'models': models,
    'conditions': conditions,
  };
}
