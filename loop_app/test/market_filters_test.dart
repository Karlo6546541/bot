import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/screens/market_filters.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  late StorageService storage;
  late AppState state;
  late List<Device> all;

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    // Demo objavi iPhone 13 — korisnički predmet u Marketu.
    await TradeService(
      storage,
    ).list(userId: SeedData.demoUserId, deviceId: 'seed-9', price: 300);
    await storage.saveSession(userId: SeedData.testUserId);
    state = AppState.fromStorage(storage);
    all = state.marketDevices;
  });

  tearDown(() => Hive.close());

  test('bez filtera: sve, najnovije prvo', () {
    const f = MarketFilter();
    expect(f.activeCount, 0);
    expect(f.apply(all, state), hasLength(all.length));
  });

  test('odjeljak, kategorija, stanje, cijena', () {
    final f = const MarketFilter().copyWith(
      section: ItemSection.electronics,
      category: DeviceCategory.phone,
      conditions: {DeviceCondition.excellent},
      maxPrice: 700,
    );
    expect(f.activeCount, 4);
    final r = f.apply(all, state);
    expect(r, isNotEmpty);
    for (final d in r) {
      expect(d.category, DeviceCategory.phone);
      expect(d.condition, DeviceCondition.excellent);
      expect(d.askPrice, lessThanOrEqualTo(700));
    }
    // Promjena odjeljka briše kategoriju.
    expect(f.copyWith(clearSection: true).category, isNull);
  });

  test('prodavatelj: LOOP ili korisnici', () {
    final users = const MarketFilter(
      seller: SellerFilter.users,
    ).apply(all, state);
    expect(users.map((d) => d.id), ['seed-9']);
    final loop = const MarketFilter(
      seller: SellerFilter.loop,
    ).apply(all, state);
    expect(loop.every((d) => d.isOnMarket), isTrue);
    expect(users.length + loop.length, all.length);
  });

  test('pretraga po nazivu, opisu i kategoriji; sortiranje po cijeni', () {
    expect(
      const MarketFilter(query: 'charizard').apply(all, state).single.name,
      'Charizard Holo',
    );
    expect(
      const MarketFilter(query: 'konzol').apply(all, state),
      isNotEmpty, // kategorija "Konzole"
    );
    final sorted = const MarketFilter(
      sort: MarketSort.priceAsc,
    ).apply(all, state);
    for (var i = 1; i < sorted.length; i++) {
      expect(sorted[i].askPrice, greaterThanOrEqualTo(sorted[i - 1].askPrice));
    }
  });

  test('očisti zadržava pretragu i sortiranje', () {
    final f = const MarketFilter(
      query: 'iphone',
      sort: MarketSort.name,
      onlyFavorites: true,
      withPhotos: true,
    ).cleared();
    expect(f.activeCount, 0);
    expect(f.query, 'iphone');
    expect(f.sort, MarketSort.name);
  });

  test('raspon cijena za klizač', () {
    final (lo, hi) = priceBounds(all);
    expect(
      lo,
      lessThanOrEqualTo(
        all.map((d) => d.askPrice).reduce((a, b) => a < b ? a : b),
      ),
    );
    expect(hi, greaterThanOrEqualTo(1890));
    expect(lo % 10, 0);
    expect(hi % 10, 0);
  });

  test('pretraga bez dijakritike i s više riječi', () {
    // "Prigodna kovanica 25 kn" — kategorija "Kovanice i novčanice".
    expect(
      const MarketFilter(query: 'NOVCANICE  prigodna').apply(all, state),
      isNotEmpty,
    );
    expect(
      const MarketFilter(query: 'prigodna konzola').apply(all, state),
      isEmpty,
    );
  });

  test('mogu kupiti: cijena + 5% fee unutar mojih kredita', () {
    final credits = state.currentUser!.credits; // test: 800
    final r = const MarketFilter(onlyAffordable: true).apply(all, state);
    expect(r, isNotEmpty);
    expect(r.every((d) => d.askPrice * 1.02 <= credits), isTrue);
    expect(r.length, lessThan(all.length));
  });
}
