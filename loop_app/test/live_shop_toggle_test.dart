import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/live_show.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
  });
  tearDown(() => Hive.close());

  test('trgovina u liveu je zadano isključena i sprema se u zapis', () async {
    final live = LiveService(storage);
    final show = await live.create(
      hostId: SeedData.anaUserId,
      title: 'Bez trgovine',
    );
    expect(show.shop, isFalse);
    final restored = LiveShow.fromMap(show.toMap());
    expect(restored.shop, isFalse);
    final on = await live.create(
      hostId: SeedData.markoUserId,
      title: 'S trgovinom',
      shop: true,
    );
    expect(LiveShow.fromMap(on.toMap()).shop, isTrue);
  });

  test(
    'samo domaćin uključuje i isključuje trgovinu; uređivanje je ne gubi',
    () async {
      final live = LiveService(storage);
      final show = await live.create(
        hostId: SeedData.anaUserId,
        title: 'Zakazani show',
        startsAt: DateTime.now().add(const Duration(hours: 2)),
        shop: true,
      );
      expect(
        () => live.setShop(SeedData.markoUserId, show.id, false),
        throwsA(isA<TradeException>()),
      );
      final edited = await live.edit(
        SeedData.anaUserId,
        show.id,
        title: 'Novi naslov',
      );
      expect(edited.shop, isTrue);
      await live.setShop(SeedData.anaUserId, show.id, false);
      expect(storage.liveShowById(show.id)!.shop, isFalse);
      await live.setShop(SeedData.anaUserId, show.id, true);
      expect(storage.liveShowById(show.id)!.shop, isTrue);
    },
  );
}
