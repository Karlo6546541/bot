import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/screens/auctions_screen.dart';
import 'package:loop_app/screens/for_you_ranker.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Algoritam "Za tebe".
void main() {
  late StorageService storage;
  const me = SeedData.testUserId;
  const ana = SeedData.anaUserId;
  const marko = SeedData.markoUserId;

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: me);
  });
  tearDown(() => Hive.close());

  Future<Device> add(String owner, String name, DeviceCategory c) =>
      TradeService(storage).addDevice(
        userId: owner,
        name: name,
        model: 'X',
        condition: DeviceCondition.good,
        price: 40,
        category: c,
      );

  List<Pick> rank({
    List<String> recent = const [],
    Map<DeviceCategory, double> boost = const {},
  }) {
    final s = AppState.fromStorage(storage);
    return ForYouRanker(
      s,
      now: DateTime.now(),
      recentCategories: recent,
      boost: boost,
    ).rank(browseItems(s), limit: 50);
  }

  int pos(List<Pick> picks, String deviceId) =>
      picks.indexWhere((p) => p.item.device?.id == deviceId);

  final cats = DeviceCategory.values
      .where((c) => c.section != ItemSection.digital)
      .toList();

  test('ukus: otvarane kategorije idu naprijed, s razlogom', () async {
    final a = await add(ana, 'Retro predmet A', cats[0]);
    final b = await add(marko, 'Retro predmet B', cats[1]);
    final picks = rank(recent: List.filled(10, cats[1].name));
    expect(pos(picks, b.id), lessThan(pos(picks, a.id)));
    expect(picks[pos(picks, b.id)].reason, contains(cats[1].label));
  });

  test('prodavači koje pratim dobivaju prednost', () async {
    final a = await add(ana, 'Predmet od Ane', cats[2]);
    final b = await add(marko, 'Predmet od Marka', cats[2]);
    final u = storage.userById(me)!;
    await storage.putUser(u.copyWith(following: [...u.following, marko]));
    final picks = rank();
    expect(pos(picks, b.id), lessThan(pos(picks, a.id)));
    expect(picks[pos(picks, b.id)].reason, contains('pratiš'));
  });

  test('pretraga: naziv koji sam tražio', () async {
    final a = await add(ana, 'Obični predmet', cats[3]);
    final b = await add(ana, 'Gameboy Color', cats[3]);
    await storage.addSearch('gameboy');
    final picks = rank();
    expect(pos(picks, b.id), lessThan(pos(picks, a.id)));
  });

  test('bez vlastitih oglasa; raznolikost prodavača', () async {
    final mine = await add(me, 'Moj predmet', cats[0]);
    for (var i = 0; i < 4; i++) {
      await add(ana, 'Ana $i', cats[0]);
    }
    await add(marko, 'Marko 1', cats[1]);
    final picks = rank();
    expect(pos(picks, mine.id), -1);
    // Nema tri ista prodavača zaredom dok postoji drugi izbor.
    String? seller(Pick p) =>
        p.item.show?.hostId ??
        p.item.auction?.sellerId ??
        p.item.device?.ownerId;
    final firstThree = picks.take(3).map(seller).toSet();
    expect(firstThree.length, greaterThan(1));
  });

  test('isti dan — isti redoslijed (stabilno)', () async {
    await add(ana, 'A', cats[0]);
    await add(marko, 'B', cats[1]);
    final x = rank().map(
      (p) => p.item.entry.deviceId ?? p.item.entry.auctionId,
    );
    final y = rank().map(
      (p) => p.item.entry.deviceId ?? p.item.entry.auctionId,
    );
    expect(x.toList(), y.toList());
  });

  test('feed uči: dugo gledano gore, preskočeno dolje', () async {
    final a = await add(ana, 'Predmet A', cats[4]);
    final b = await add(marko, 'Predmet B', cats[5]);
    var picks = rank(boost: {cats[4]: 4, cats[5]: -3});
    expect(pos(picks, a.id), lessThan(pos(picks, b.id)));
    expect(picks[pos(picks, a.id)].reason, contains(cats[4].label));
    picks = rank(boost: {cats[4]: -3, cats[5]: 4});
    expect(pos(picks, b.id), lessThan(pos(picks, a.id)));
  });
}
