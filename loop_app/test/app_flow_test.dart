import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/l10n/tr.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/home_shell.dart';
import 'package:loop_app/widgets/device_card.dart';
import 'package:loop_app/screens/seller_screens.dart';
import 'package:loop_app/screens/swipe_feed_screen.dart';
import 'package:loop_app/widgets/feed.dart' show FeedEntry;
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';

/// Početna počinje feedom — kartica sa stanjem je ispod; skrolaj do nje.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 300, scrollable: vScroll());
  await tester.pumpAndSettle();
}

Future<void> openProfileSettings(WidgetTester tester) async {
  if (find
      .byKey(const ValueKey('profile-settings-close'))
      .evaluate()
      .isNotEmpty) {
    return;
  }
  final gear = find.byKey(const ValueKey('profile-settings'));
  await tester.scrollUntilVisible(gear, -300, scrollable: vScroll());
  await tester.tap(gear);
  await tester.pumpAndSettle();
}

/// Prvi okomiti popis na ekranu (vodoravni redovi filtara se preskaču).
Finder vScroll() => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .first;

/// Moje → Prodajem → Predmeti.
Future<void> openMyItems(WidgetTester tester) async {
  if (find.text('Moje').evaluate().isEmpty) {
    final menu = find.byKey(const ValueKey('home-filters'));
    await tester.tap(
      menu.evaluate().isNotEmpty
          ? menu
          : find.byKey(const ValueKey('shell-library-menu')),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Moje').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('my-selling')));
  await tester.pumpAndSettle();
}

/// Početna → pilula "Aukcije" (Istraži je spojen s Početnom).
Future<void> openAuctionsPill(WidgetTester tester) async {
  // Pilule su na vrhu Početne.
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('home-cats')),
    -300,
    scrollable: vScroll(),
  );
  await tester.tap(find.byKey(const ValueKey('home-filters')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('home-cat-timed')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('home-cat-timed')));
  await tester.pumpAndSettle();
}

/// Profil → Povijest transakcija.
Future<void> openActivity(WidgetTester tester) async {
  await tester.tap(find.text('Profil').last);
  await tester.pumpAndSettle();
  await openProfileSettings(tester);
  await reveal(tester, find.byKey(const ValueKey('open-activity')));
  await tester.tap(find.byKey(const ValueKey('open-activity')));
  await tester.pumpAndSettle();
}

/// Aukcije → kartica (otvara swipe feed) → detalji aukcije.
Future<void> openAuction(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('post-media')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Otvori cijeli oglas'));
  await tester.pumpAndSettle();
}

Future<Widget> buildApp(WidgetTester tester) async {
  final storage = StorageService();
  await tester.runAsync(() => storage.init(inMemory: true));
  addTearDown(() => tester.runAsync(Hive.close));
  return ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      // Bez periodičkih timera (odbrojavanje) — inače pumpAndSettle ne staje.
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: const LoopApp(),
  );
}

void main() {
  accountTests();
  listingTests();
  deletionTests();
  communityTests();
  chatTests();
  logoTests();
  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('početna → aukcije → licitacija → Moje ($size)', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await buildApp(tester));
      await tester.ensureVisible(find.text('Prijavi se'));
      await tester.tap(find.text('Prijavi se'));
      await tester.pumpAndSettle();

      // Početna: "Za tebe" je feed preko cijelog ekrana (kao TikTok).
      expect(find.byKey(const ValueKey('for-you-feed')), findsOneWidget);
      // Uživo: poziv na live; Aukcije: one koje završavaju.
      await tester.tap(find.byKey(const ValueKey('home-cat-live')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('home-go-live')));
      expect(find.byKey(const ValueKey('home-go-live')), findsOneWidget);
      expect(
        find.text('Nitko trenutno nije uživo — budi prvi!'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('home-filters')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-cat-timed')));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('home-ending')));
      expect(find.text('Ulaznica – Ultra Europe'), findsWidgets);
      // Nema više Marketa.
      expect(find.text('Market'), findsNothing);

      // Moji predmeti su u Profilu.
      await openMyItems(tester);
      await tester.scrollUntilVisible(
        find.text('iPhone 13'),
        300,
        scrollable: vScroll(),
      );
      await tester.pumpAndSettle();
      expect(find.text('iPhone 13'), findsOneWidget);
      await tester.tap(find.text('Početna').last);
      await tester.pumpAndSettle();

      // Aukcije → kartica → swipe feed → licitiraj.
      await openAuctionsPill(tester);
      await tester.ensureVisible(find.text('Polaroid SX-70'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Polaroid SX-70'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-bid')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('bid-amount')), '70');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('bid-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Ponuda prihvaćena — vodiš!'), findsOneWidget);
      await tester.tap(find.byTooltip('Natrag'));
      await tester.pumpAndSettle();

      // Moje → Kupljeno (prvo), pa Ponude.
      if (find.text('Moje').evaluate().isEmpty) {
        final menu = find.byKey(const ValueKey('home-filters'));
        await tester.tap(
          menu.evaluate().isNotEmpty
              ? menu
              : find.byKey(const ValueKey('shell-library-menu')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Moje').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('my-bought')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('my-bought')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my-myBids')));
      await tester.pumpAndSettle();
      expect(find.text('Polaroid SX-70'), findsOneWidget);
      expect(find.text('Vodiš'), findsOneWidget);
      // Prodajem → Liveovi.
      await tester.tap(find.byKey(const ValueKey('my-selling')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('my-lives')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('my-lives')));
      await tester.pumpAndSettle();
      expect(find.text('Još nisi bio uživo'), findsOneWidget);
    });
  }

  testWidgets('admin prijava i dashboard', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.tap(find.text('Admin prijava'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'admin123');
    await tester.tap(find.widgetWithText(FilledButton, 'Prijava'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Subhasto Admin'), findsOneWidget);
    expect(find.text('Ukupni volume'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.group_outlined));
    await tester.pumpAndSettle();
    expect(find.text('demo@loop.com'), findsOneWidget);
  });

  testWidgets('odjeljci i grafikon portfolija', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    // Prodajem: svi moji predmeti, filtri po stanju (spremljeno, Kupi
    // odmah, aukcija, live).
    await openMyItems(tester);
    expect(find.text('Vrijednost kroz vrijeme'), findsNothing);
    final all = find.byType(DeviceCard).evaluate().length;
    expect(all, greaterThan(0));
    await tester.tap(find.byKey(const ValueKey('my-items-draft')));
    await tester.pumpAndSettle();
    final drafts = find.byType(DeviceCard).evaluate().length;
    expect(drafts, lessThanOrEqualTo(all));
    if (drafts > 0) expect(find.text('💾 Spremljeno'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('my-items-auction')));
    await tester.pumpAndSettle();
    expect(find.text('💾 Spremljeno'), findsNothing);

    // Dostave: Stiže meni / Šaljem / Dostavljeno su odvojeni.
    await tester.tap(find.byKey(const ValueKey('my-deliveries')));
    await tester.pumpAndSettle();
    if (find.byKey(const ValueKey('my-ship-filter')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('ship-delivered')));
      await tester.pumpAndSettle();
      expect(find.text('Ništa ti trenutno ne stiže.'), findsNothing);
    }
  });

  testWidgets('aukcija: ponuda, vodstvo, zaključan obrazac', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    await openAuctionsPill(tester);
    expect(find.text('Polaroid SX-70'), findsOneWidget);

    await openAuction(tester, 'Polaroid SX-70');
    expect(find.textContaining('Najmanja ponuda: 61 €'), findsOneWidget);

    // Licitiranje u listu: premalo → poruka; zatim prava ponuda.
    await tester.tap(find.byKey(const ValueKey('open-bid')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bid-amount')), '60');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bid-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Najmanja ponuda je 61 €.'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('bid-amount')), '70');
    await tester.pumpAndSettle();
    expect(find.text('Licitiraj 70 €'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('bid-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Ponuda prihvaćena — vodiš!'), findsOneWidget);
    expect(find.text('Vodiš'), findsOneWidget);
    // Vodeći više ne licitira, ali može postaviti automatsku ponudu.
    expect(find.byKey(const ValueKey('open-bid')), findsNothing);
    expect(find.textContaining('ne može se povući'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('raise-auto')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bid-max')), '150');
    await tester.tap(find.byKey(const ValueKey('bid-submit')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Automatski licitiramo za tebe do 150 €'),
      findsOneWidget,
    );

    // Zvono: praćenje aukcije.
    await tester.tap(find.byKey(const ValueKey('watch-auction')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_active), findsOneWidget);
  });

  testWidgets('isplata zarade na IBAN i promjena teme', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    // Zarada (1.250 €) ide na IBAN iz podataka prodavatelja (Moje → Prodajem).
    await openMyItems(tester);
    await tester.tap(find.byKey(const ValueKey('profile-payout')));
    await tester.pumpAndSettle();
    expect(find.text('Isplatiti zaradu?'), findsOneWidget);
    expect(find.textContaining('HR25 •••• 1111'), findsWidgets);
    await tester.tap(find.text('Isplati').last);
    await tester.pumpAndSettle();
    expect(find.text('Isplata je poslana na tvoj račun.'), findsOneWidget);
    expect(find.text('0 €'), findsWidgets);

    // Tamna tema iz Profila: sučelje se ponovno izgradi bez grešaka.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await openProfileSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Tamna'),
      200,
      scrollable: vScroll(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamna'));
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsWidgets); // ostali smo na istom tabu
    expect(
      Theme.of(tester.element(find.text('Tamna'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.text('Početna').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('podaci prodavatelja prije prve objave; pravni dokumenti', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    // Pravni dokumenti su dostupni već na prijavi.
    await tester.ensureVisible(find.text('Uvjeti korištenja').first);
    await tester.tap(find.text('Uvjeti korištenja').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('legal-terms')), findsOneWidget);
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();

    // Gost razgleda; novi račun nema podatke prodavatelja.
    await tester.tap(find.text('Registracija'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'prodavac@loop.com',
    );
    await tester.enterText(
      find.byKey(const ValueKey('username-field')),
      'prodavac',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Lozinka'),
      'lozinka123',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('accept-terms')));
    await tester.tap(find.byKey(const ValueKey('accept-terms')));
    await tester.ensureVisible(find.byKey(const ValueKey('register-submit')));
    await tester.tap(find.byKey(const ValueKey('register-submit')));
    await tester.pumpAndSettle();

    // Testno: live se pokreće bez podataka prodavatelja.
    await tester.tap(find.byKey(const ValueKey('nav-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-live')));
    await tester.pumpAndSettle();
    expect(find.text('Novi live'), findsOneWidget);
    expect(find.text('Podaci prodavatelja'), findsNothing);
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();

    // + Objavi → Aukcija također bez podataka prodavatelja.
    await tester.tap(find.byKey(const ValueKey('nav-create')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-auction')));
    await tester.pumpAndSettle();
    expect(find.text('Podaci prodavatelja'), findsNothing);
    expect(find.text('Nemaš predmeta za aukciju'), findsOneWidget);
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();

    // Podaci prodavatelja (za Kupi odmah i isplatu) — iz Profila.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await openProfileSettings(tester);
    await reveal(tester, find.byKey(const ValueKey('seller-info')));
    await tester.tap(find.byKey(const ValueKey('seller-info')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('seller-name')),
      'Ivo Prodavac',
    );
    await tester.enterText(find.byKey(const ValueKey('seller-oib')), '1234');
    await tester.enterText(
      find.byKey(const ValueKey('seller-address')),
      'Ulica 1, Zagreb',
    );
    await tester.enterText(
      find.byKey(const ValueKey('seller-iban')),
      'HR25 2340 0091 1111 1111 1',
    );
    await tester.tap(find.byKey(const ValueKey('seller-birth')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('U REDU'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('seller-save')));
    await tester.tap(find.byKey(const ValueKey('seller-save')));
    await tester.pumpAndSettle();
    expect(find.text('OIB nije ispravan (11 znamenki).'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('seller-oib')),
      '45678901239',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('seller-save')));
    await tester.tap(find.byKey(const ValueKey('seller-save')));
    await tester.pumpAndSettle();
    // Spremljeno → natrag na Profil.
    expect(find.byKey(const ValueKey('seller-save')), findsNothing);

    // Profil → Pravno → svi dokumenti.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await openProfileSettings(tester);
    await reveal(tester, find.byKey(const ValueKey('open-legal')));
    await tester.tap(find.byKey(const ValueKey('open-legal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('legal-open-imprint')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('legal-imprint')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('engleski jezik: gumb gore i postavka u Profilu', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => Tr.lang = AppLang.hr);
    Tr.missing.clear();

    await tester.pumpWidget(await buildApp(tester));
    // Gumb za jezik na ekranu prijave.
    await tester.tap(find.byKey(const ValueKey('language-button')));
    await tester.pumpAndSettle();
    expect(find.text('Log in'), findsWidgets);
    expect(find.text('Just browse (guest)'), findsOneWidget);

    await tester.ensureVisible(find.text('Log in').last);
    await tester.tap(find.text('Log in').last);
    await tester.pumpAndSettle();
    // Početna na engleskom.
    expect(find.text('For you'), findsOneWidget);

    // Swipe feed aukcija na engleskom.
    await openAuctionsPill(tester);
    await tester.ensureVisible(find.text('Polaroid SX-70'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polaroid SX-70'));
    await tester.pumpAndSettle();
    expect(find.text('Auctions'), findsWidgets);
    expect(find.text('Share'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    // Engleski zapis eura (zarada u Moje → Prodajem).
    await tester.tap(find.byKey(const ValueKey('home-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mine').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('my-selling')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1,250'), findsWidgets);
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();
    expect(find.text('Edit profile'), findsOneWidget);
    await openProfileSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Language / Jezik'),
      200,
      scrollable: vScroll(),
    );
    expect(find.text('Language / Jezik'), findsOneWidget);
    expect(Tr.missing, isEmpty, reason: 'nedostaju prijevodi');

    // Natrag na hrvatski iz Profila.
    // Donja navigacija prekriva dno — skrolaj dok gumb nije iznad nje.
    await openProfileSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Reset demo data'),
      200,
      scrollable: vScroll(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('🇭🇷 Hrvatski'));
    await tester.pumpAndSettle();
    // Promjena jezika ponovno gradi sučelje; ostaje na Profilu.
    expect(find.text('Profil'), findsWidgets);
    await openProfileSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Jezik / Language'),
      200,
      scrollable: vScroll(),
    );
    expect(find.text('Jezik / Language'), findsOneWidget);
    expect(Tr.lang, AppLang.hr);
  });
}

void accountTests() {
  testWidgets('registracija: provjera imena uživo, novi račun, gost', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.tap(find.text('Registracija'));
    await tester.pumpAndSettle();

    // Zauzeto ime → poruka i prijedlozi.
    await tester.enterText(
      find.byKey(const ValueKey('username-field')),
      'Demo',
    );
    await tester.pumpAndSettle();
    expect(find.text('@demo je zauzeto.'), findsOneWidget);
    expect(find.text('Slobodno:'), findsOneWidget);
    // Slobodno ime.
    await tester.enterText(
      find.byKey(const ValueKey('username-field')),
      'novi_korisnik',
    );
    await tester.pumpAndSettle();
    expect(find.text('@novi_korisnik je slobodno ✓'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'novi@loop.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Lozinka'),
      'tajna123',
    );
    // Bez pristanka na Uvjete registracija ne prolazi.
    await tester.ensureVisible(find.byKey(const ValueKey('register-submit')));
    await tester.tap(find.byKey(const ValueKey('register-submit')));
    await tester.pumpAndSettle();
    expect(
      find.text('Za registraciju prihvati Uvjete korištenja.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('accept-terms')));
    await tester.tap(find.byKey(const ValueKey('accept-terms')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('register-submit')));
    await tester.tap(find.byKey(const ValueKey('register-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-cat-live')));
    await tester.pumpAndSettle();
    await reveal(tester, find.byKey(const ValueKey('home-go-live')));
    expect(find.byKey(const ValueKey('home-go-live')), findsOneWidget);

    // Profil prikazuje @ime; odjava.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    expect(find.text('@novi_korisnik'), findsWidgets);
    await openProfileSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Odjavi se'),
      200,
      scrollable: vScroll(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Odjavi se'));
    await tester.pumpAndSettle();

    // Gost može razgledavati, ali ne i licitirati.
    await tester.ensureVisible(find.text('Samo razgledaj (gost)'));
    await tester.tap(find.text('Samo razgledaj (gost)'));
    await tester.pumpAndSettle();
    await openAuctionsPill(tester);
    await tester.ensureVisible(find.text('Polaroid SX-70'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polaroid SX-70'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-bid')));
    await tester.pumpAndSettle();
    // Prijava/registracija se otvori preko predmeta; "natrag" vraća na njega.
    expect(find.text('Napravi besplatan račun'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('login-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-bid')), findsOneWidget);
  });

  testWidgets(
    'prvo pokretanje: odmah u aplikaciju kao gost, prijava tek za kupnju',
    (tester) async {
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final storage = StorageService();
      await tester.runAsync(() => storage.init(inMemory: true));
      addTearDown(() => tester.runAsync(Hive.close));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
            autoGuestProvider.overrideWithValue(true),
          ],
          child: const LoopApp(),
        ),
      );
      await tester.pumpAndSettle();
      // Bez ekrana za prijavu: početna, kao gost.
      expect(find.text('Prijavi se'), findsNothing);
      expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
      expect(storage.currentUserId, 'user-guest');

      // Licitiranje otvara registraciju preko predmeta.
      await openAuctionsPill(tester);
      await tester.ensureVisible(find.text('Polaroid SX-70'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Polaroid SX-70'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-bid')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-close')), findsOneWidget);
      expect(find.text('Novi račun'), findsOneWidget);

      // Prijava → ekran se zatvori, korisnik je i dalje na predmetu.
      await tester.tap(find.text('Prijava').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Prijavi se'));
      await tester.tap(find.text('Prijavi se'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('login-close')), findsNothing);
      expect(find.byKey(const ValueKey('post-bid')), findsOneWidget);
      expect(storage.currentUserId, isNot('user-guest'));

      // Odjava vodi na ekran za prijavu (bez ponovnog automatskog gosta).
    },
  );
}

void listingTests() {
  testWidgets('predmet: na aukciju ili u live, brisanje', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    await openMyItems(tester);
    await tester.scrollUntilVisible(
      find.text('iPhone 13'),
      300,
      scrollable: vScroll(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('iPhone 13'));
    await tester.pumpAndSettle();

    // Vlasnik bira način prodaje: Kupi odmah, aukcija ili live.
    final page = find
        .descendant(
          of: find.byType(Scaffold).last,
          matching: find.byType(Scrollable),
        )
        .first;
    // Demo iPhone je bio na Kupi odmah (isključeno): može se samo maknuti
    // iz prodaje, a nudi se aukcija ili live.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('unlist')),
      200,
      scrollable: page,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('listing-info')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('unlist')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('item-auction')),
      200,
      scrollable: page,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('item-buy-now')), findsNothing);
    expect(find.byKey(const ValueKey('item-live')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('item-auction')));
    await tester.pumpAndSettle();
    expect(find.text('Nova aukcija'), findsOneWidget);
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();

    // Obriši predmet.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('delete-item')),
      200,
      scrollable: page,
    );
    // Pričekaj da nestane obavijest (SnackBar) koja prekriva dno.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-item')));
    await tester.pumpAndSettle();
    expect(find.text('Obrisati predmet?'), findsOneWidget);
    await tester.tap(find.text('Obriši'));
    await tester.pumpAndSettle();
    expect(find.text('Predmet obrisan'), findsOneWidget);
    expect(find.text('iPhone 13'), findsNothing);
  });
}

void deletionTests() {
  testWidgets('brisanje računa uz potvrdu imenom, povratak prijavom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await openProfileSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Obriši račun'),
      200,
      scrollable: vScroll(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obriši račun'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '• Prije brisanja isplati zaradu (1.250 €) na svoj IBAN — poslije to više nije moguće.',
      ),
      findsOneWidget,
    );

    // Gumb je onemogućen dok se ne upiše korisničko ime.
    final button = find.byKey(const ValueKey('delete-schedule'));
    expect(tester.widget<ButtonStyleButton>(button).enabled, isFalse);
    await tester.enterText(
      find.byKey(const ValueKey('delete-confirm')),
      '@demo',
    );
    await tester.pumpAndSettle();
    expect(tester.widget<ButtonStyleButton>(button).enabled, isTrue);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Račun će biti obrisan za 7 dana'),
      findsOneWidget,
    );
    expect(find.text('Prijavi se'), findsWidgets); // odjavljen

    // Ponovna prijava vraća račun.
    await tester.ensureVisible(find.text('Prijavi se').last);
    await tester.tap(find.text('Prijavi se').last);
    await tester.pumpAndSettle();
    expect(
      find.text('Dobro došao natrag! Brisanje računa je otkazano.'),
      findsOneWidget,
    );
  });
}

void communityTests() {
  testWidgets('obavijest "nadmašen", ocjene i prijava oglasa', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> login(String email) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail ili korisničko ime'),
        email,
      );
      await tester.ensureVisible(find.text('Prijavi se').last);
      await tester.tap(find.text('Prijavi se').last);
      await tester.pumpAndSettle();
    }

    Future<void> logout() async {
      await tester.tap(find.text('Profil').last);
      await tester.pumpAndSettle();
      await openProfileSettings(tester);
      await tester.scrollUntilVisible(
        find.text('Odjavi se'),
        200,
        scrollable: vScroll(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Odjavi se'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(await buildApp(tester));
    await login('demo@loop.com');

    // Demo nadmaši Marka na Polaroidu.
    await openAuctionsPill(tester);
    await openAuction(tester, 'Polaroid SX-70');
    await tester.tap(find.byKey(const ValueKey('open-bid')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('bid-amount')), '70');
    await tester.tap(find.byKey(const ValueKey('bid-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Natrag'));
    await tester.pumpAndSettle();
    await logout();

    // Marko vidi obavijest na zvonu.
    await login('@marko');
    final bell = find.byKey(const ValueKey('notification-bell'));
    expect(find.descendant(of: bell, matching: find.text('1')), findsOneWidget);
    await tester.tap(bell);
    await tester.pumpAndSettle();
    final text =
        'Netko te nadmašio na aukciji "Polaroid SX-70" — nova ponuda 70 €.';
    expect(find.text(text), findsOneWidget);
    // Kartica aukcije: Marko je nadmašen → gumb za novu ponudu.
    expect(find.text('Nadmašen'), findsOneWidget);
    expect(find.text('Povisi ponudu'), findsOneWidget);
    // Filter "Aukcije" sa sažetkom mojih aukcija.
    await tester.tap(find.byKey(const ValueKey('notif-filter-auctions')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('auction-summary')), findsOneWidget);
    expect(find.text(text), findsOneWidget);
    // Postavke: isključi "Netko me nadmašio".
    await tester.tap(find.byKey(const ValueKey('notification-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pref-outbid')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byKey(const ValueKey('pref-outbid'))),
    );
    expect(container.read(appProvider).currentUser!.mutedNotifications, [
      'outbid',
    ]);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
    expect(find.text('Povijest ponuda (2)'), findsOneWidget);
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();
    expect(find.descendant(of: bell, matching: find.text('1')), findsNothing);

    // Javni profil prodavateljice: ocjene i izbornik prijave/blokiranja.
    await openAuctionsPill(tester);
    await openAuction(tester, 'Polaroid SX-70');
    await tester.tap(find.textContaining('@ana.kolekcija'));
    await tester.pumpAndSettle();
    // Trgovina: pratitelji, prodaje i gumb "Prati".
    expect(find.text('pratitelja'), findsOneWidget);
    expect(find.byKey(const ValueKey('follow')), findsOneWidget);
    // Ocjene su na svojoj kartici trgovine.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('shop-tabs')),
      300,
      scrollable: vScroll(),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ocjene'));
    await tester.pumpAndSettle();
    expect(find.text('Još nema ocjena'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('profile-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prijavi korisnika'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pošalji prijavu'));
    await tester.pumpAndSettle();
    expect(
      find.text('Prijava poslana. Admin će je pregledati.'),
      findsOneWidget,
    );
  });
}

void chatTests() {
  testWidgets('poruka prodavatelju iz oglasa, odgovor u Porukama', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> login(String id) async {
      await tester.enterText(
        find.widgetWithText(TextFormField, 'E-mail ili korisničko ime'),
        id,
      );
      await tester.ensureVisible(find.text('Prijavi se').last);
      await tester.tap(find.text('Prijavi se').last);
      await tester.pumpAndSettle();
    }

    Future<void> logout() async {
      await tester.tap(find.text('Profil').last);
      await tester.pumpAndSettle();
      await openProfileSettings(tester);
      await tester.scrollUntilVisible(
        find.text('Odjavi se'),
        200,
        scrollable: vScroll(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Odjavi se'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(await buildApp(tester));
    await login('@demo');
    // Demo predmeti su automatski u Marketu.
    await logout();

    // Marko pita prodavatelja (pretraga → profil → Poruka).
    await login('@marko');
    await tester.tap(find.byKey(const ValueKey('home-search')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'demo');
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Računi'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('account-${SeedData.demoUserId}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Poruka'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'Je li još dostupan?',
    );
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('Je li još dostupan?'), findsOneWidget);
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();
    await logout();

    // Demo vidi poruku i odgovara.
    await login('@demo');
    final messages = find.byKey(const ValueKey('messages-button'));
    expect(
      find.descendant(of: messages, matching: find.text('1')),
      findsOneWidget,
    );
    await tester.tap(messages);
    await tester.pumpAndSettle();
    await tester.tap(find.text('@marko'));
    await tester.pumpAndSettle();
    expect(find.text('Je li još dostupan?'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('chat-input')), 'Je!');
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('Je!'), findsOneWidget);
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Natrag').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: messages, matching: find.text('1')),
      findsNothing,
    );
  });
}

void logoTests() {
  for (final size in const [Size(400, 860), Size(1400, 1000)]) {
    testWidgets('logo vodi na početnu ($size)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await buildApp(tester));
      await tester.ensureVisible(find.text('Prijavi se'));
      await tester.tap(find.text('Prijavi se'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-search')), findsOneWidget);

      // Moje → logo → natrag na početnu.
      if (find.text('Moje').evaluate().isEmpty) {
        final menu = find.byKey(const ValueKey('home-filters'));
        await tester.tap(
          menu.evaluate().isNotEmpty
              ? menu
              : find.byKey(const ValueKey('shell-library-menu')),
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Moje').last);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-search')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('logo-home')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
    });
  }

  testWidgets('natrag: kronološki kroz tabove, pa Početna', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('for-you-feed')), findsOneWidget);

    // Za tebe → Uživo → Pratim (dodirom), zatim natrag dvaput.
    await tester.tap(find.byKey(const ValueKey('home-cat-live')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home-cat-following')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-go-live')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('for-you-feed')), findsOneWidget);

    // Swipe lijevo na Uživo pa natrag na Za tebe.
    await tester.fling(
      find.byKey(const ValueKey('home-swipe')),
      const Offset(-300, 0),
      1500,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-go-live')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('for-you-feed')), findsOneWidget);
  });

  testWidgets('Kupi odmah iz swipe feeda: kupljeno, ne "nije dostupan"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    // Swipe feed s tuđim predmetom na Kupi odmah.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
    );
    final me = container.read(appProvider).currentUserId;
    final item = container
        .read(appProvider)
        .devices
        .firstWhere((d) => d.isListed && d.ownerId != me && !d.isDigital);
    SwipeFeedScreen.open(
      tester.element(find.byType(HomeShell)),
      [FeedEntry.item(item.id)],
      0,
      title: 'Kupi odmah',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('post-buy')));
    await tester.pumpAndSettle();
    // Prvo se mora odabrati način dostave — bez toga nema plaćanja.
    final pay = find.byKey(const ValueKey('checkout-pay'));
    expect(find.text('Prvo odaberi način dostave'), findsOneWidget);
    expect(tester.widget<ButtonStyleButton>(pay).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('delivery-hr-gls')));
    await tester.pumpAndSettle();
    expect(tester.widget<ButtonStyleButton>(pay).onPressed, isNotNull);
    // Kartica i adresa demo računa koriste se automatski.
    await tester.ensureVisible(pay);
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(pay));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('celebration')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('post-bought')), findsOneWidget);
    expect(find.text('Oglas više nije dostupan.'), findsNothing);
  });

  testWidgets('prodavatelj kao obrt/tvrtka: naziv tvrtke i oznaka trgovca', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = StorageService();
    await tester.runAsync(() => storage.init(inMemory: true));
    addTearDown(() => tester.runAsync(Hive.close));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storageProvider.overrideWithValue(storage),
          tickIntervalProvider.overrideWithValue(null),
        ],
        child: const LoopApp(),
      ),
    );
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await openProfileSettings(tester);
    await reveal(tester, find.byKey(const ValueKey('seller-info')));
    await tester.tap(find.byKey(const ValueKey('seller-info')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('seller-kind-business')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('seller-company')),
      'Retro Kutak j.d.o.o.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('seller-phone')),
      '+385 91 123 4567',
    );
    // Bez potvrde o propisima ne sprema.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('seller-save')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SellerInfoScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('seller-save')));
    await tester.pumpAndSettle();
    expect(SellerInfoScreenFinder.title, findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('seller-certify')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SellerInfoScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('seller-certify')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('seller-save')),
      200,
      scrollable: find
          .descendant(
            of: find.byType(SellerInfoScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byKey(const ValueKey('seller-save')));
    await tester.pumpAndSettle();
    final seller = storage.userById(storage.currentUserId!)!.seller!;
    expect(seller.isBusiness, isTrue);
    expect(seller.tradeName, 'Retro Kutak j.d.o.o.');
    expect(seller.contactEmail, isNotEmpty);
    expect(find.textContaining('Retro Kutak j.d.o.o.'), findsWidgets);
  });
  testWidgets('kartica Kategorije: samo kategorije, dodir otvara predmete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    if (find.text('Kategorije').evaluate().isEmpty) {
      final menu = find.byKey(const ValueKey('home-filters'));
      await tester.tap(
        menu.evaluate().isNotEmpty
            ? menu
            : find.byKey(const ValueKey('shell-library-menu')),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Kategorije').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('categories')), findsOneWidget);
    // Samo kategorije — bez liveova, aukcija i predmeta.
    expect(find.byKey(const ValueKey('home-live')), findsNothing);
    final camera = find.byKey(const ValueKey('category-camera'));
    expect(camera, findsOneWidget);
    await tester.tap(camera);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('category-items')), findsOneWidget);
    expect(find.text('Polaroid SX-70'), findsOneWidget);
  });
}

/// Ekran podataka prodavatelja je još otvoren.
class SellerInfoScreenFinder {
  static Finder get title => find.byKey(const ValueKey('seller-save'));
}
