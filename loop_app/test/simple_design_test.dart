import 'package:loop_app/widgets/reference_sheet.dart';
import 'package:loop_app/widgets/reference_order_row.dart';
import 'package:loop_app/widgets/wallet_ticket.dart';
import 'package:loop_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/config/design_variant.dart';
import 'package:loop_app/models/auction.dart';
import 'package:loop_app/models/price_offer.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/activity_view.dart';
import 'package:loop_app/screens/public_profile_screen.dart';
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
              onPressed: () => openReferenceSheet<void>(
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
    await tester.tap(find.byKey(const ValueKey('reference-sheet-close')).last);
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

  testWidgets('home searches a real shop and opens that seller profile', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await mainTab(tester, 'Početna');
    final shops = find.byWidgetPredicate(
      (widget) =>
          widget.runtimeType.toString() == '_SellerCard' &&
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
    expect(find.byTooltip('O prodavatelju').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Podijeli trgovinu').hitTestable(), findsOneWidget);
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
}
