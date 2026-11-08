import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/device_detail_screen.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/theme/app_theme.dart';

/// Kupovna zona (cijena + Kupi odmah) mora ostati vidljiva i dostupna na
/// svim veličinama, uz dug opis i povećan tekst.
void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
  });
  tearDown(Hive.close);

  for (final c in [
    (name: '400x777', size: const Size(400, 777), scale: 1.0),
    (name: '360x640', size: const Size(360, 640), scale: 1.0),
    (name: '390x844 tekst 1.5', size: const Size(390, 844), scale: 1.5),
    (name: '1280x800', size: const Size(1280, 800), scale: 1.0),
    (name: '1280x600 tekst 1.3', size: const Size(1280, 600), scale: 1.3),
  ]) {
    testWidgets('Kupi odmah ostaje vidljiv na ${c.name}', (tester) async {
      tester.view.physicalSize = c.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      LoopColors.use(Brightness.light);
      final seed = storage.devices.firstWhere(
        (d) => d.ownerId != SeedData.testUserId && d.isForSale,
      );
      final long = List.filled(
        60,
        'Dugi opis predmeta s mnogo detalja.',
      ).join(' ');
      await storage.putDevice(
        Device.fromMap({...seed.toMap(), 'description': long}),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storageProvider.overrideWithValue(storage),
            tickIntervalProvider.overrideWithValue(null),
          ],
          child: MaterialApp(
            theme: buildLoopTheme(),
            locale: const Locale('hr'),
            supportedLocales: const [Locale('hr'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(c.scale)),
              child: child!,
            ),
            home: DeviceDetailScreen(deviceId: seed.id),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final buy = find.byKey(const ValueKey('buy-now'));
      expect(buy, findsOneWidget);
      final rect = tester.getRect(buy);
      final view = Offset.zero & c.size;
      expect(view.contains(rect.topLeft), isTrue, reason: '$rect');
      expect(view.contains(rect.bottomRight), isTrue, reason: '$rect');
      expect(rect.height, greaterThanOrEqualTo(44));
      // Niska traka: samo gumb (bez ponovljene cijene), naziv samo jednom.
      expect(rect.height, lessThanOrEqualTo(56));
      expect(find.byKey(const ValueKey('item-title')), findsOneWidget);
      expect(find.byKey(const ValueKey('delivery-estimate')), findsOneWidget);
      expect(find.text(seed.name), findsOneWidget);
      // Opis se pomiče, kupovna traka ostaje na mjestu.
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pump();
      expect(tester.getRect(buy), rect);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('seller-block')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const ValueKey('seller-block')), findsOneWidget);
      expect(tester.getRect(buy), rect);
      expect(tester.takeException(), isNull);
    });
  }
}
