import 'package:uuid/uuid.dart';

import '../l10n/tr.dart';
import '../models/app_user.dart';
import '../models/story.dart';
import '../models/wishlist.dart';
import 'storage_service.dart';
import 'trade_service.dart';

/// Liste želja (kolekcije) korisnika.
class WishlistService {
  WishlistService(this._storage);

  final StorageService _storage;
  static const _uuid = Uuid();

  AppUser _user(String userId) {
    final u = _storage.userById(userId);
    if (u == null || u.isGuest) {
      throw TradeException(t('Za liste želja se prijavi.'));
    }
    return u;
  }

  String _cleanName(String name) {
    final n = name.trim();
    if (n.isEmpty) throw TradeException(t('Upiši naziv liste.'));
    if (n.length > Wishlist.maxName) {
      throw TradeException(
        t('Naziv liste može imati najviše {0} znakova.', [
          '${Wishlist.maxName}',
        ]),
      );
    }
    return n;
  }

  Future<Wishlist> create(
    String userId,
    String name, {
    String emoji = '🎁',
    DateTime? now,
  }) async {
    final u = _user(userId);
    final n = _cleanName(name);
    if (u.wishlists.length >= Wishlist.maxLists) {
      throw TradeException(
        t('Možeš imati najviše {0} lista.', ['${Wishlist.maxLists}']),
      );
    }
    if (u.wishlists.any((w) => w.name.toLowerCase() == n.toLowerCase())) {
      throw TradeException(t('Lista s tim nazivom već postoji.'));
    }
    final list = Wishlist(
      id: _uuid.v4().substring(0, 8),
      name: n,
      emoji: emoji,
      createdAt: now ?? DateTime.now(),
    );
    await _storage.putUser(u.copyWith(wishlists: [...u.wishlists, list]));
    return list;
  }

  Future<void> _replace(AppUser u, Wishlist w) => _storage.putUser(
    u.copyWith(wishlists: [for (final x in u.wishlists) x.id == w.id ? w : x]),
  );

  Wishlist _require(AppUser u, String listId) {
    final w = u.wishlistById(listId);
    if (w == null) throw TradeException(t('Lista ne postoji.'));
    return w;
  }

  Future<Wishlist> edit(
    String userId,
    String listId, {
    String? name,
    String? emoji,
  }) async {
    final u = _user(userId);
    final w = _require(u, listId);
    final n = name == null ? null : _cleanName(name);
    if (n != null &&
        u.wishlists.any(
          (x) => x.id != listId && x.name.toLowerCase() == n.toLowerCase(),
        )) {
      throw TradeException(t('Lista s tim nazivom već postoji.'));
    }
    final updated = w.copyWith(name: n, emoji: emoji);
    await _replace(u, updated);
    return updated;
  }

  Future<void> delete(String userId, String listId) async {
    final u = _user(userId);
    _require(u, listId);
    await _storage.putUser(
      u.copyWith(wishlists: u.wishlists.where((w) => w.id != listId).toList()),
    );
  }

  /// Dodaje ili uklanja predmet s liste. Vraća `true` ako je dodan.
  Future<bool> toggleItem(String userId, String listId, String deviceId) async {
    final u = _user(userId);
    final w = _require(u, listId);
    final ids = [...w.deviceIds];
    final added = !ids.remove(deviceId);
    if (added) {
      if (ids.length >= Wishlist.maxItems) {
        throw TradeException(
          t('Lista može imati najviše {0} predmeta.', ['${Wishlist.maxItems}']),
        );
      }
      ids.insert(0, deviceId);
    }
    await _replace(u, w.copyWith(deviceIds: ids));
    return added;
  }
}

/// Priče (stories) trgovina — vidljive 24 sata.
class StoryService {
  StoryService(this._storage);

  final StorageService _storage;
  static const _uuid = Uuid();

  /// Najviše aktivnih priča po korisniku.
  static const maxActive = 10;

  Future<Story> create({
    required String userId,
    String text = '',
    String? deviceId,
    String? imagePath,
    int color = 0,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final u = _storage.userById(userId);
    if (u == null || u.isGuest) {
      throw TradeException(t('Za priču se prijavi.'));
    }
    final body = text.trim();
    if (body.length > Story.maxText) {
      throw TradeException(
        t('Tekst priče može imati najviše {0} znakova.', ['${Story.maxText}']),
      );
    }
    if (body.isEmpty && deviceId == null && imagePath == null) {
      throw TradeException(t('Dodaj tekst, fotografiju ili oglas.'));
    }
    if (deviceId != null) {
      final d = _storage.deviceById(deviceId);
      if (d == null || d.ownerId != userId) {
        throw TradeException(t('U priču možeš staviti samo svoj oglas.'));
      }
    }
    final active = _storage.stories
        .where((s) => s.userId == userId && s.activeAt(at))
        .length;
    if (active >= maxActive) {
      throw TradeException(
        t('Možeš imati najviše {0} aktivnih priča.', ['$maxActive']),
      );
    }
    final story = Story(
      id: _uuid.v4(),
      userId: userId,
      text: body,
      deviceId: deviceId,
      imagePath: imagePath,
      color: color,
      createdAt: at,
    );
    await _storage.putStory(story);
    return story;
  }

  Future<void> delete(String userId, String storyId) async {
    final s = _storage.stories.where((x) => x.id == storyId).firstOrNull;
    if (s == null) return;
    if (s.userId != userId) {
      throw TradeException(t('Možeš obrisati samo svoju priču.'));
    }
    await _storage.deleteStory(storyId);
  }

  /// Briše istekle priče korisnika (vraća putanje fotografija za brisanje).
  Future<List<String>> purgeExpired(String userId, {DateTime? now}) async {
    final at = now ?? DateTime.now();
    final images = <String>[];
    for (final s in _storage.stories) {
      if (s.userId == userId && !s.activeAt(at)) {
        if (s.imagePath != null) images.add(s.imagePath!);
        await _storage.deleteStory(s.id);
      }
    }
    return images;
  }
}
