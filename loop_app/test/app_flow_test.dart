import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/screens/market_screen.dart';
import 'package:loop_app/l10n/tr.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/services/storage_service.dart';

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
  digitalTests();
  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('login → prodaja → kupnja → aktivnost ($size)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(await buildApp(tester));
      await tester.ensureVisible(find.text('Prijavi se'));
      await tester.tap(find.text('Prijavi se'));
      await tester.pumpAndSettle();

      // Portfolio demo korisnika
      expect(find.text('1.250'), findsWidgets); // kartica + traka
      expect(find.text('SILVER'), findsOneWidget);
      // Popis predmeta je ispod grafikona — skrolaj do njega.
      await tester.scrollUntilVisible(find.text('iPhone 13'), 300);
      await tester.pumpAndSettle();
      expect(find.text('iPhone 13'), findsOneWidget);

      // Prodaja
      await tester.ensureVisible(find.text('Prodaj odmah').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prodaj odmah').first);
      await tester.pumpAndSettle();
      expect(find.text('bez naknade'), findsOneWidget);
      await tester.tap(find.text('Potvrdi prodaju'));
      await tester.pumpAndSettle();
      expect(find.text('Uspješno prodano'), findsOneWidget);
      expect(find.textContaining('1.560'), findsWidgets);

      // Kupnja (AirPods Pro 2: 185 + 2% = 188.70)
      await tester.tap(find.text('Market').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'AirPods');
      await tester.pumpAndSettle();
      // Novi filteri dodaju jedan red; na mobitelu gumb može biti
      // niže u listi i zato ga treba dovesti u vidljivo područje.
      await tester.ensureVisible(find.text('Kupi odmah'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kupi odmah'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Potvrdi kupnju'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Potvrdi kupnju'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Uspješno kupljeno'), findsOneWidget);

      // Aktivnost: najnovije na vrhu
      await tester.tap(find.text('Aktivnost').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('+310 €'), 200);
      expect(find.text('+310 €'), findsOneWidget);
      expect(find.text('−188,70 €'), findsOneWidget);
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

    expect(find.textContaining('LOOP Admin'), findsOneWidget);
    expect(find.text('Ukupni volume'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.group_outlined));
    await tester.pumpAndSettle();
    expect(find.text('demo@loop.com'), findsOneWidget);
  });

  testWidgets('kategorije, favoriti i detalji uređaja', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();

    // Odjeljak "Elektronika", pa čip "Konzole" filtrira na PS5 i Switch.
    await tester.tap(find.text('Elektronika'));
    await tester.pumpAndSettle();
    expect(find.text('Charizard Holo'), findsNothing);
    await tester.ensureVisible(find.text('Konzole'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konzole'));
    await tester.pumpAndSettle();
    expect(find.text('PlayStation 5'), findsOneWidget);
    expect(find.text('Nintendo Switch OLED'), findsOneWidget);
    expect(find.text('iPhone 15 Pro'), findsNothing);

    expect(find.text('2 predmeta'), findsOneWidget);

    // Favorit, pa u listu filtera "Samo favoriti" (broj rezultata uživo).
    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filters-button')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Samo s fotografijom'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('filters-list')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Samo favoriti'));
    await tester.pumpAndSettle();
    expect(find.text('Prikaži 1 rezultata'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('filters-apply')));
    await tester.pumpAndSettle();
    expect(find.text('1 predmeta'), findsOneWidget);
    expect(
      find.text('Filteri (3)'),
      findsOneWidget,
    ); // odjeljak, kategorija, favoriti
    // Aktivni filteri se vide kao čipovi i brišu jednim dodirom.
    await tester.tap(find.byKey(const ValueKey('filters-clear-all')));
    await tester.pumpAndSettle();
    expect(find.text('Filteri'), findsOneWidget);

    // Sortiranje: prikazuje trenutni izbor.
    await tester.tap(find.byKey(const ValueKey('sort-button')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(
        CheckedPopupMenuItem<MarketSort>,
        'Cijena: viša prvo',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cijena: viša prvo'), findsOneWidget); // na čipu
    expect(find.text('Najnovije'), findsNothing); // izbornik zatvoren

    // Detalji uređaja.
    await tester.ensureVisible(find.text('Sony A7 III'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sony A7 III'));
    await tester.pumpAndSettle();
    expect(find.text('Ukupno plaćaš'), findsOneWidget);
    expect(find.text('999,60 €'), findsOneWidget); // 980 + 2%
  });

  testWidgets('odjeljci i grafikon portfolija', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    // Grafikon i promjena raspona.
    expect(find.text('Vrijednost portfolija'), findsOneWidget);
    await tester.tap(find.text('Sve'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ukupno'), findsOneWidget);
    // Hover/dodir na grafikon prikazuje tooltip s iznosom.
    final chart = find
        .byType(CustomPaint)
        .evaluate()
        .map((e) => e.widget)
        .whereType<CustomPaint>()
        .where((w) => w.painter?.runtimeType.toString() == '_ChartPainter');
    expect(chart, isNotEmpty);
    // Tablični prikaz.
    await tester.tap(find.byTooltip('Prikaži tablicu'));
    await tester.pumpAndSettle();
    expect(find.text('Ukupno'), findsOneWidget);

    // Market: odjeljak Rukotvorine.
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Rukotvorine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rukotvorine'));
    await tester.pumpAndSettle();
    expect(find.text('Keramička šalica'), findsOneWidget);
    expect(find.text('iPhone 15 Pro'), findsNothing);
    expect(find.text('Nakit'), findsWidgets); // čip kategorije + kartica
  });

  testWidgets('aukcija: ponuda, vodstvo, zaključan obrazac', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aukcije').last);
    await tester.pumpAndSettle();
    expect(find.text('Polaroid SX-70'), findsOneWidget);

    await tester.tap(find.text('Polaroid SX-70'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Najmanja ponuda: 63 €'), findsOneWidget);

    // Manje od minimuma → poruka uz polje.
    await tester.enterText(find.byType(TextField), '61');
    await tester.tap(find.text('Licitiraj'));
    await tester.pumpAndSettle();
    expect(find.text('Najmanje 63 €'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '70');
    await tester.tap(find.text('Licitiraj'));
    await tester.pumpAndSettle();
    expect(find.textContaining('NE MOŽE se povući'), findsOneWidget);
    await tester.tap(find.text('Licitiraj').last);
    await tester.pumpAndSettle();

    expect(find.text('Ponuda prihvaćena — vodiš!'), findsOneWidget);
    expect(find.text('Vodiš'), findsOneWidget);
    // Vodeći ponuđač više nema obrazac za ponudu.
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('ne može se povući'), findsOneWidget);
  });

  testWidgets('uplata novca i promjena teme', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    // Gumb na glavnoj kartici otvara uplatu; zadani iznos je 500 €.
    await tester.tap(find.text('Uplati novac').first);
    await tester.pumpAndSettle();
    expect(find.text('Najpopularnije'), findsOneWidget);
    await tester.tap(find.text('PayPal'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Plati 500,00 €'), 200);
    await tester.tap(find.text('Plati 500,00 €'));
    await tester.pumpAndSettle();
    expect(find.text('Plaćanje uspješno! 🎉'), findsOneWidget);
    await tester.tap(find.text('Super'));
    await tester.pumpAndSettle();
    expect(find.textContaining('1.750'), findsWidgets); // 1250 + 500

    // Tamna tema iz Profila: sučelje se ponovno izgradi bez grešaka.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tamna'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tamna'));
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsWidgets); // ostali smo na istom tabu
    expect(
      Theme.of(tester.element(find.text('Tamna'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.text('Portfolio').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('premalo novca nudi uplatu', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'MacBook Pro');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kupi odmah')); // 1890 + 2% > 1250
    await tester.pumpAndSettle();
    expect(find.text('Nemaš dovoljno novca'), findsOneWidget);
    await tester.tap(find.text('Uplati novac'));
    await tester.pumpAndSettle();
    // Predložen je najmanji paket koji pokriva manjak (734,50 → 1000).
    await tester.scrollUntilVisible(find.text('Plati 1.000,00 €'), 200);
    expect(find.text('Plati 1.000,00 €'), findsOneWidget);
  });

  testWidgets('kupnja s dostavom kurirom i praćenje pošiljke', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'AirPods');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kupi odmah'));
    await tester.pumpAndSettle();

    // Kurir bez adrese → greška; s adresom → kupnja.
    await tester.tap(find.text('Kurir na adresu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Potvrdi kupnju'));
    await tester.tap(find.text('Potvrdi kupnju'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Upiši adresu'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Adresa za dostavu'),
      'Ilica 1, 10000 Zagreb',
    );
    await tester.pumpAndSettle();
    expect(find.text('194,70 €'), findsOneWidget); // 185 + 3,70 + 6
    await tester.ensureVisible(find.text('Potvrdi kupnju'));
    await tester.tap(find.text('Potvrdi kupnju'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Uspješno kupljeno'), findsOneWidget);

    // Moje dostave iz Profila.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Moje dostave (1 u tijeku)'),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Moje dostave (1 u tijeku)'));
    await tester.pumpAndSettle();
    expect(find.text('AirPods Pro 2 USB-C'), findsOneWidget);
    expect(find.text('Naručeno'), findsOneWidget);
    expect(find.textContaining('LOOP-'), findsOneWidget);
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
    // Engleski zapis brojeva i eura.
    expect(find.textContaining('1,250'), findsWidgets);
    expect(find.text('Your balance'), findsOneWidget);
    expect(find.text('Total €2,010 · 2 items'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('iPhone 13'), 300);
    await tester.pumpAndSettle();

    // Prodaja na engleskom.
    await tester.ensureVisible(find.text('Sell now').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sell now').first);
    await tester.pumpAndSettle();
    expect(find.text('Confirm sale'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    for (final tab in ['Market', 'Auctions', 'Activity', 'Profile']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    expect(find.text('Edit profile'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Language / Jezik'), 200);
    expect(find.text('Language / Jezik'), findsOneWidget);
    expect(Tr.missing, isEmpty, reason: 'nedostaju prijevodi');

    // Natrag na hrvatski iz Profila.
    // Donja navigacija prekriva dno — skrolaj dok gumb nije iznad nje.
    await tester.scrollUntilVisible(find.text('Reset demo data'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('🇭🇷 Hrvatski'));
    await tester.pumpAndSettle();
    // Promjena jezika ponovno gradi sučelje; ostaje na Profilu.
    expect(find.text('Profil'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Jezik / Language'), 200);
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
    await tester.ensureVisible(find.byKey(const ValueKey('register-submit')));
    await tester.tap(find.byKey(const ValueKey('register-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Bok, @novi_korisnik 👋'), findsOneWidget);

    // Profil prikazuje @ime; odjava.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    expect(find.text('@novi_korisnik'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Odjavi se'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Odjavi se'));
    await tester.pumpAndSettle();

    // Gost može razgledavati, ali ne i kupovati.
    await tester.ensureVisible(find.text('Samo razgledaj (gost)'));
    await tester.tap(find.text('Samo razgledaj (gost)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'AirPods');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kupi odmah'));
    await tester.pumpAndSettle();
    expect(find.text('Napravi besplatan račun'), findsOneWidget);
    await tester.tap(find.text('Nastavi razgledavati'));
    await tester.pumpAndSettle();
  });
}

void listingTests() {
  testWidgets('objavi u Marketu, ukloni, obriši predmet', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('iPhone 13'), 300);
    await tester.pumpAndSettle();
    await tester.tap(find.text('iPhone 13'));
    await tester.pumpAndSettle();

    // Stari predmet iz portfolija je automatski objavljen u Marketu.
    expect(find.text('🏷️ U Marketu'), findsWidgets);
    // Promjena cijene.
    await tester.scrollUntilVisible(find.text('Promijeni cijenu'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Promijeni cijenu'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Cijena'), '350');
    await tester.pumpAndSettle();
    expect(find.text('Ti dobivaš 350 € (bez naknade)'), findsOneWidget);
    await tester.tap(find.text('Objavi'));
    await tester.pumpAndSettle();
    expect(find.text('Objavljeno u Marketu 🏷️'), findsOneWidget);
    expect(find.textContaining('U Marketu za 350 €'), findsOneWidget);

    // Ukloni iz Marketa.
    await tester.scrollUntilVisible(find.byKey(const ValueKey('unlist')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unlist')));
    await tester.pumpAndSettle();
    expect(find.text('Uklonjeno iz Marketa'), findsOneWidget);
    expect(find.text('🏷️ U Marketu'), findsNothing);

    // Obriši predmet (pričekaj da poruka na dnu nestane).
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('delete-item')),
      200,
    );
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
    await tester.scrollUntilVisible(find.text('Obriši račun'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Obriši račun'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '• Gubiš preostalo stanje (1.250 €) — u demo verziji nema isplate.',
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
      await tester.scrollUntilVisible(find.text('Odjavi se'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Odjavi se'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(await buildApp(tester));
    await login('demo@loop.com');

    // Demo nadmaši Marka na Polaroidu.
    await tester.tap(find.text('Aukcije').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polaroid SX-70'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '70');
    await tester.tap(find.text('Licitiraj'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Licitiraj').last);
    await tester.pumpAndSettle();
    await tester.pageBack();
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
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
    expect(find.text('Povijest ponuda (2)'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.descendant(of: bell, matching: find.text('1')), findsNothing);

    // Javni profil prodavateljice: ocjene i izbornik prijave/blokiranja.
    await tester.tap(find.text('Aukcije').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Polaroid SX-70'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('@ana.kolekcija'));
    await tester.pumpAndSettle();
    expect(find.text('Ocjene (0)'), findsOneWidget);
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
      await tester.scrollUntilVisible(find.text('Odjavi se'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Odjavi se'));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(await buildApp(tester));
    await login('@demo');
    // Demo predmeti su automatski u Marketu.
    await logout();

    // Marko pita prodavatelja.
    await login('@marko');
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'iPhone 13');
    await tester.pumpAndSettle();
    expect(find.text('@demo'), findsWidgets); // oznaka prodavatelja
    await tester.tap(find.text('iPhone 13').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('message-seller')),
      200,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-seller')));
    await tester.pumpAndSettle();
    expect(find.text('O predmetu: iPhone 13'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      'Je li još dostupan?',
    );
    await tester.tap(find.byKey(const ValueKey('chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('Je li još dostupan?'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Zamjena: Marko nema svojih predmeta.
    await tester.tap(find.byKey(const ValueKey('offer-swap')));
    await tester.pumpAndSettle();
    expect(
      find.text('Nemaš predmeta za zamjenu — dodaj ga u portfolio.'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10)); // zatvori list
    await tester.pumpAndSettle();
    await tester.pageBack();
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
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
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
      expect(find.text('Bok, Demo 👋'), findsOneWidget);

      // Market → detalji predmeta → logo.
      await tester.tap(find.text('Market').last);
      await tester.pumpAndSettle();
      expect(find.text('Bok, Demo 👋'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('logo-home')));
      await tester.pumpAndSettle();
      expect(find.text('Bok, Demo 👋'), findsOneWidget);
    });
  }
}

void digitalTests() {
  testWidgets('digitalni proizvod: kupnja bez dostave, moje kupnje, obrazac', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    // Market → odjeljak Digitalno → kocka (STL).
    await tester.tap(find.text('Market').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'kocka');
    await tester.pumpAndSettle();
    expect(find.text('⬇ STL'), findsOneWidget);
    await tester.tap(find.text('Kocka za kalibraciju'));
    await tester.pumpAndSettle();
    expect(find.text('kocka_20mm.stl'), findsOneWidget);
    expect(find.text('Stanje'), findsNothing); // digitalno nema stanja

    await tester.scrollUntilVisible(find.byKey(const ValueKey('buy-now')), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('buy-now')));
    await tester.pumpAndSettle();
    expect(find.text('Kupi i preuzmi'), findsWidgets); // dijalog, bez dostave
    expect(find.text('Kurir na adresu'), findsNothing);
    await tester.tap(find.text('Plati i preuzmi'));
    await tester.pumpAndSettle();
    // Nakon kupnje: gumb za preuzimanje umjesto kupnje.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('download-file')),
      200,
    );
    expect(find.byKey(const ValueKey('download-file')), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('✓ Kupljeno'), findsOneWidget);

    // Profil → Moje digitalne kupnje.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('my-downloads')),
      200,
    );
    await tester.pumpAndSettle();
    expect(find.text('Moje digitalne kupnje (1)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('my-downloads')));
    await tester.pumpAndSettle();
    expect(find.text('Kocka za kalibraciju'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // Obrazac: "Digitalno" skriva stanje i traži datoteku.
    await tester.tap(find.text('Portfolio').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dodaj predmet').first);
    await tester.pumpAndSettle();
    expect(find.text('Stanje'), findsOneWidget);
    await tester.ensureVisible(find.text('Digitalno'));
    await tester.tap(find.text('Digitalno'));
    await tester.pumpAndSettle();
    expect(find.text('Stanje'), findsNothing);
    expect(find.text('Dodaj datoteku'), findsOneWidget);
  });
}
