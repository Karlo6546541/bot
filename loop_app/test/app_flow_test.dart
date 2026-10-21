import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
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
      expect(find.text('Fee (5%)'), findsOneWidget);
      await tester.tap(find.text('Potvrdi prodaju'));
      await tester.pumpAndSettle();
      expect(find.text('Uspješno prodano'), findsOneWidget);
      expect(find.text('1.544,50'), findsWidgets);

      // Kupnja (AirPods Pro 2: 185 + 5% = 194.25)
      await tester.tap(find.text('Market').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'AirPods');
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
      await tester.scrollUntilVisible(find.text('+294,50 kredita'), 200);
      expect(find.text('+294,50 kredita'), findsOneWidget);
      expect(find.text('−194,25 kredita'), findsOneWidget);
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

    // Favorit pa filter "Favoriti".
    await tester.tap(find.byIcon(Icons.favorite_border).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Favoriti'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Favoriti'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.favorite), findsWidgets);

    // Detalji uređaja.
    await tester.ensureVisible(find.text('Sve'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sve'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sony A7 III'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sony A7 III'));
    await tester.pumpAndSettle();
    expect(find.text('Ukupno plaćaš'), findsOneWidget);
    expect(find.text('1.029 kredita'), findsOneWidget); // 980 + 5%
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
    expect(find.textContaining('Najmanja ponuda: 63 kredita'), findsOneWidget);

    // Manje od minimuma → poruka uz polje.
    await tester.enterText(find.byType(TextField), '61');
    await tester.tap(find.text('Licitiraj'));
    await tester.pumpAndSettle();
    expect(find.text('Najmanje 63 kredita'), findsOneWidget);

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

  testWidgets('kupnja kredita i promjena teme', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(await buildApp(tester));
    await tester.ensureVisible(find.text('Prijavi se'));
    await tester.tap(find.text('Prijavi se'));
    await tester.pumpAndSettle();

    // Gumb na glavnoj kartici otvara kupnju; zadani paket je 500 (+30).
    await tester.tap(find.text('Dopuni kredite'));
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
    expect(find.text('1.780'), findsWidgets); // 1250 + 500 + 30 bonus

    // Tamna tema iz Profila: sučelje se ponovno izgradi bez grešaka.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Tamna'));
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

  testWidgets('premalo kredita nudi kupnju kredita', (tester) async {
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
    await tester.tap(find.text('Kupi odmah')); // 1890 + 5% > 1250
    await tester.pumpAndSettle();
    expect(find.text('Nemaš dovoljno kredita'), findsOneWidget);
    await tester.tap(find.text('Kupi kredite'));
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
    expect(find.text('200,25 kredita'), findsOneWidget); // 185 + 9,25 + 6
    await tester.ensureVisible(find.text('Potvrdi kupnju'));
    await tester.tap(find.text('Potvrdi kupnju'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Uspješno kupljeno'), findsOneWidget);

    // Moje dostave iz Profila.
    await tester.tap(find.text('Profil').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Moje dostave (1 u tijeku)'));
    await tester.tap(find.text('Moje dostave (1 u tijeku)'));
    await tester.pumpAndSettle();
    expect(find.text('AirPods Pro 2 USB-C'), findsOneWidget);
    expect(find.text('Naručeno'), findsOneWidget);
    expect(find.textContaining('LOOP-'), findsOneWidget);
  });
}
