import 'package:loop_app/widgets/reference_sheet.dart';
import 'package:loop_app/widgets/reference_order_row.dart';
import 'package:loop_app/widgets/wallet_ticket.dart';
import 'package:loop_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/config/features.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/config/design_variant.dart';
import 'package:loop_app/models/auction.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/price_offer.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/activity_view.dart';
import 'package:loop_app/screens/public_profile_screen.dart';
import 'package:loop_app/screens/live_screens.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'helpers/vision_navigation.dart';

void main() {
  if (!kSimpleDesign) {
    test(
      'the simplified design is opt-in',
      () => expect(kSimpleDesign, isFalse),
    );
    return;
  }
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    await TradeService(storage).assignPlatformItems();
    await TradeService(storage).autoListPortfolios();
  });
  tearDown(Hive.close);
  Widget app({Widget? home}) => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: home == null
        ? const LoopApp()
        : MaterialApp(home: Scaffold(body: home)),
  );

  testWidgets('several purchases fit on the phone; tracking opens on demand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var openedOriginalDetails = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLoopTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => openScreen<void>(
                context,
                title: 'Moje',
                builder: (_) => ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  children: [
                    for (var i = 0; i < 6; i++)
                      WalletTicket(
                        title: 'Kupnja $i',
                        status: 'Čeka slanje',
                        date: DateTime(2026, 11, 5),
                        price: '42 €',
                        onTap: () => openedOriginalDetails = true,
                        footer: const CinematicTracking(
                          stage: 0,
                          animate: false,
                        ),
                      ),
                  ],
                ),
              ),
              child: const Text('Otvori kupnje'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Otvori kupnje'));
    await tester.pumpAndSettle();
    expect(find.byType(ReferenceOrderRow).hitTestable(), findsNWidgets(6));
    expect(find.byType(CinematicTracking), findsNothing);
    expect(
      tester.getSize(find.byType(ReferenceOrderRow).first).height,
      lessThanOrEqualTo(72),
    );
    await tester.tap(find.text('Kupnja 0'));
    await tester.pumpAndSettle();
    expect(find.text('Detalji narudžbe'), findsOneWidget);
    expect(
      tester.widget<CinematicTracking>(find.byType(CinematicTracking)).stage,
      0,
    );
    await tester.tap(find.text('Pogledaj'));
    expect(openedOriginalDetails, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CinematicTracking), findsNothing);
    expect(find.text('Kupnja 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sheet remains usable above the mobile keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildLoopTheme(),
        home: const Scaffold(
          resizeToAvoidBottomInset: false,
          body: ReferenceSheet(
            title: 'Pretraži',
            child: Padding(
              padding: EdgeInsets.all(24),
              child: TextField(key: ValueKey('keyboard-search')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('keyboard-search'));
    expect(tester.getTopLeft(field).dy, lessThan(180));
    expect(tester.getBottomRight(find.byType(ReferenceSheet)).dy, 844);
    expect(tester.getBottomRight(field).dy, lessThan(524));
    expect(buildLoopTheme().textTheme.bodyMedium?.fontFamily, kFontFamily);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reference home keeps all five destinations and discovery routes accessible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      // Aplikacija se otvara na Početnoj s pet odredišta.
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(ValueKey('simple-nav-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('home-sellers')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
      await mainTab(tester, 'Moje');
      expect(
        find.byKey(const ValueKey('activity-tab-purchases')),
        findsOneWidget,
      );
      await mainTab(tester, 'Početna');
      expect(find.byKey(const ValueKey('home-categories')), findsOneWidget);
      expect(find.byKey(const ValueKey('messages-button')), findsOneWidget);
      // Zaglavlje: tekstualni tabovi, pretraga, poruke i obavijesti.
      expect(find.byKey(const ValueKey('home-view-for-you')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-view-following')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-view-following')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('home-following-empty')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('pretraga proizvoda prvo prikazuje showove prodavača', (
    tester,
  ) async {
    final device = await TradeService(storage).addDevice(
      userId: SeedData.anaUserId,
      name: 'Zvjezdarnica Zeta',
      model: 'Z',
      condition: DeviceCondition.good,
      price: 40,
      category: DeviceCategory.camera,
    );
    final show = await LiveService(
      storage,
    ).create(hostId: SeedData.anaUserId, title: 'Nedjeljni izlog', shop: true);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await mainTab(tester, 'Početna');
    await tester.tap(find.byKey(const ValueKey('home-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reference-search-input')),
      device.name,
    );
    await tester.pumpAndSettle();
    final shows = find.byKey(ValueKey('search-live-${show.id}'));
    final sellers = find.byKey(ValueKey('reference-shop-${device.ownerId}'));
    expect(shows, findsOneWidget);
    if (sellers.evaluate().isNotEmpty) {
      expect(
        tester.getTopLeft(shows.first).dy,
        lessThan(tester.getTopLeft(sellers.first).dy),
      );
    }
    await tester.pumpWidget(const SizedBox());
  }, skip: !kBuyNowEnabled);

  testWidgets('home searches a real shop and opens that seller profile', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await mainTab(tester, 'Početna');
    final shops = find.byWidgetPredicate(
      (widget) =>
          widget.runtimeType.toString() == '_SellerChip' &&
          widget.key is ValueKey<String> &&
          (widget.key as ValueKey<String>).value.startsWith('home-seller-'),
    );
    expect(shops, findsWidgets);
    final key = tester.widget(shops.first).key! as ValueKey<String>;
    final owner = storage.userById(key.value.substring('home-seller-'.length))!;
    await tester.tap(find.byKey(const ValueKey('home-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reference-search-input')),
      owner.username,
    );
    await tester.pumpAndSettle();
    final result = find.byKey(ValueKey('reference-shop-${owner.id}'));
    expect(result, findsOneWidget);
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PublicProfileScreen>(find.byType(PublicProfileScreen))
          .userId,
      owner.id,
    );
    // Kompaktna traka: dodatne radnje (o prodavatelju, dijeljenje) su u izborniku.
    await tester.tap(find.byKey(const ValueKey('profile-menu')));
    await tester.pumpAndSettle();
    expect(find.text('O prodavatelju'), findsOneWidget);
    expect(find.text('Podijeli profil'), findsOneWidget);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'bids and negotiated offers remain reachable as separate activity sections',
    (tester) async {
      final auction = storage.auctions.firstWhere(
        (a) => a.sellerId != SeedData.testUserId,
      );
      await storage.putAuction(
        auction.copyWith(
          endsAt: DateTime.now().add(const Duration(hours: 1)),
          bids: [
            Bid(
              userId: SeedData.testUserId,
              userLabel: 'Test',
              amount: 75,
              time: DateTime.now(),
            ),
          ],
        ),
      );
      await storage.putBargain(
        PriceOffer(
          id: 'simple-offer',
          deviceId: 'seed-1',
          deviceName: 'Ponuda za telefon',
          buyerId: SeedData.testUserId,
          sellerId: SeedData.anaUserId,
          amount: 25,
          listPrice: 30,
          createdAt: DateTime.now(),
          status: BargainStatus.accepted,
          validUntil: DateTime.now().add(const Duration(days: 1)),
        ),
      );
      await tester.pumpWidget(app(home: const ActivityView()));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('activity-tab-bids')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-tab-bids')));
      await tester.pumpAndSettle();
      expect(find.text(auction.deviceName), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('activity-tab-offers')));
      await tester.pumpAndSettle();
      expect(find.text(auction.deviceName), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('Ponuda za telefon'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.textContaining('Ponuda za telefon'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Studio keeps tools without duplicate cards or menu at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await mainTab(tester, 'Prodavač');
    expect(find.byKey(const ValueKey('seller-hub-live')), findsOneWidget);
    expect(find.text('Tvoj prostor za live.'), findsNothing);
    expect(find.byKey(const ValueKey('seller-hub-menu')), findsNothing);
    final list = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .last;
    for (final id in [
      'finance',
      'inventory',
      'shipments',
      'offers',
      'shows',
      'auction',
      'sales',
      'messages',
    ]) {
      final target = find.byKey(ValueKey('seller-hub-$id'));
      await tester.scrollUntilVisible(target, 180, scrollable: list);
      expect(target, findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pet odredišta; Kategorije su zaseban ekran', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    for (final label in [
      'Početna',
      'Kategorije',
      'Prodaj',
      'Kupnje',
      'Profil',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Istraži'), findsNothing);
    expect(find.text('Pozornica'), findsNothing);
    await mainTab(tester, 'Kategorije');
    expect(find.byKey(const ValueKey('categories')), findsOneWidget);
    expect(find.byKey(const ValueKey('categories-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sadržaj nikad nije ispod donje navigacije', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await mainTab(tester, 'Kategorije');
    final dock = tester.getRect(find.byKey(const ValueKey('floating-dock')));
    final content = tester.getRect(find.byKey(const ValueKey('categories')));
    expect(content.bottom, lessThanOrEqualTo(dock.top + 0.5));
  });

  testWidgets('Početna je live-first: Za tebe/Pratim/Uskoro, bez proizvoda', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-categories')), findsOneWidget);
    for (final id in ['for-you', 'following', 'soon']) {
      expect(find.byKey(ValueKey('home-view-$id')), findsOneWidget, reason: id);
    }
    // Nema zasebnog taba Proizvodi ni mreže pojedinačnih oglasa.
    expect(find.byKey(const ValueKey('home-view-buy')), findsNothing);
    expect(find.byKey(const ValueKey('home-shop-discovery')), findsNothing);
    expect(find.byKey(const ValueKey('home-sellers')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-view-soon')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-view-soon')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Kategorija: lajvovi, najavljeno i prodavači', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await mainTab(tester, 'Kategorije');
    await tester.tap(find.byKey(const ValueKey('category-all-electronics')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category-views')), findsNothing);
    expect(find.byKey(const ValueKey('category-items')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Pretraga u Instagram stilu: nedavno, tabovi, povratak', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('search-back')), findsOneWidget);
    expect(find.byKey(const ValueKey('search-tab-top')), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('reference-search-input')),
      'a',
    );
    await tester.pumpAndSettle();
    for (final id in ['top', 'accounts', 'live', 'soon']) {
      expect(find.byKey(ValueKey('search-tab-$id')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('search-tab-accounts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('search-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prodavač je normalan ekran; povratak čuva upit pretrage', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final shops = find.byWidgetPredicate(
      (w) =>
          w.runtimeType.toString() == '_SellerChip' &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('home-seller-'),
    );
    final key = tester.widget(shops.first).key! as ValueKey<String>;
    final owner = storage.userById(key.value.substring('home-seller-'.length))!;
    await tester.tap(find.byKey(const ValueKey('home-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('reference-search-input')),
      owner.username,
    );
    await tester.pumpAndSettle();
    final result = find.byKey(ValueKey('reference-shop-${owner.id}'));
    await tester.ensureVisible(result);
    await tester.tap(result);
    await tester.pumpAndSettle();
    // Normalan ekran: AppBar s nazivom i povratkom, bez panela.
    expect(find.byType(PublicProfileScreen), findsOneWidget);
    expect(find.byType(AppBar), findsWidgets);
    expect(find.byKey(const ValueKey('reference-sheet-close')), findsNothing);
    expect(find.text(owner.shopTitle), findsWidgets);
    // Sistemski Back (Android) vraća na pretragu.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('reference-search-input')),
          )
          .controller!
          .text,
      owner.username,
    );
    await tester.tap(find.byKey(const ValueKey('search-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(360, 740),
    const Size(430, 932),
    const Size(1280, 800),
  ]) {
    testWidgets('Početna: kartice showova, avatar vodi na profil na $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final live = LiveService(storage);
      final show = await live.create(
        hostId: SeedData.anaUserId,
        title: 'Ana uživo',
      );
      final soon = await live.create(
        hostId: SeedData.markoUserId,
        title: 'Marko uskoro',
        startsAt: DateTime.now().add(const Duration(days: 2)),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      // Tabovi i kategorije su zasebni redovi.
      expect(find.byKey(const ValueKey('home-tabs')), findsOneWidget);
      expect(find.byKey(const ValueKey('home-categories')), findsOneWidget);
      final card = find.byKey(ValueKey('home-featured-live-${show.id}'));
      expect(card, findsOneWidget);
      expect(
        find.byKey(ValueKey('home-featured-live-${soon.id}')),
        findsOneWidget,
      );
      // Nema velikih gumba Prati / Posjeti shop na karticama.
      expect(find.byKey(const ValueKey('follow')), findsNothing);
      expect(tester.takeException(), isNull, reason: 'home');
      // Dodir avatara/imena otvara profil, ne show.
      await tester.tap(find.byKey(ValueKey('card-host-${show.id}')));
      await tester.pumpAndSettle();
      expect(find.byType(PublicProfileScreen), findsOneWidget);
      expect(find.byType(LiveRoomScreen), findsNothing);
      expect(tester.takeException(), isNull, reason: 'profile');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      // Dodir kartice otvara upravo taj live.
      await tester.tap(card);
      await tester.pumpAndSettle();
      expect(
        tester.widget<LiveRoomScreen>(find.byType(LiveRoomScreen)).showId,
        show.id,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-tabs')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
