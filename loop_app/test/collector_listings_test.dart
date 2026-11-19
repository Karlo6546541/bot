import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/device_detail_screen.dart';
import 'package:loop_app/screens/my_listings_screen.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/theme/app_theme.dart';

void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.anaUserId);
  });
  tearDown(Hive.close);

  Widget app(Widget home) => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      theme: buildLoopTheme(),
      locale: const Locale('hr'),
      supportedLocales: const [Locale('hr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: home,
    ),
  );

  test('certifikat se sprema uz predmet i daje poveznicu za provjeru', () {
    const cert = GradingCertificate(
      grader: Grader.psa,
      grade: '10',
      number: '12345678',
    );
    expect(cert.badge, 'PSA 10');
    expect(cert.verifyUrl.toString(), 'https://www.psacard.com/cert/12345678');
    final back = GradingCertificate.fromMap(cert.toMap());
    expect(back.grader, Grader.psa);
    expect(back.number, '12345678');
    expect(
      const GradingCertificate(grader: Grader.other, grade: 'Mint').verifyUrl,
      isNull,
    );
  });

  testWidgets('oglas s certifikatom pokazuje ocjenu i gumb Provjeri', (
    tester,
  ) async {
    final d = await TradeService(storage).addDevice(
      userId: SeedData.anaUserId,
      name: 'Charizard Holo',
      model: '',
      condition: DeviceCondition.good,
      price: 500,
      category: DeviceCategory.values.first,
      certificate: const GradingCertificate(
        grader: Grader.psa,
        grade: '9',
        number: '555',
      ),
    );
    expect(storage.deviceById(d.id)!.certificate!.badge, 'PSA 9');
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await storage.saveSession(userId: SeedData.testUserId);
    await tester.pumpWidget(app(DeviceDetailScreen(deviceId: d.id)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('certificate-card')), findsOneWidget);
    expect(find.text('Ocijenjeno: PSA 9'), findsOneWidget);
    expect(find.byKey(const ValueKey('certificate-verify')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Moji oglasi: Aktivni i Prodano', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const MyListingsScreen()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('my-listings-active')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey &&
            '${(w.key as ValueKey).value}'.startsWith('my-listing-'),
      ),
      findsWidgets,
    );
    await tester.tap(find.byKey(const ValueKey('my-listings-sold')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
