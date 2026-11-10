import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/live_screens.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/theme/app_theme.dart';

Future<void> _loadInter(WidgetTester tester) async {
  await tester.runAsync(() async {
    final loader = FontLoader('Inter');
    for (final name in [
      'Inter_400Regular.ttf',
      'Inter_500Medium.ttf',
      'Inter_600SemiBold.ttf',
      'Inter_700Bold.ttf',
    ]) {
      final bytes = File('assets/fonts/$name').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  });
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await _frames(tester);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('viewer-shot')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = data!.buffer.asUint8List();
    final dir = Directory('/opt/cursor/artifacts');
    if (dir.existsSync()) {
      await File('${dir.path}/$name.png').writeAsBytes(bytes, flush: true);
    }
    expect(image.width, 390, reason: name);
    expect(image.height, 844, reason: name);
    image.dispose();
  });
}

void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
  });
  tearDown(Hive.close);

  Widget app(Widget page) => ProviderScope(
    overrides: [
      storageProvider.overrideWithValue(storage),
      tickIntervalProvider.overrideWithValue(null),
    ],
    child: MaterialApp(
      theme: buildLoopTheme(),
      locale: const Locale('hr'),
      supportedLocales: const [Locale('hr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: RepaintBoundary(key: const ValueKey('viewer-shot'), child: page),
    ),
  );

  testWidgets('gledatelj: aukcija i bez videa u donjoj trećini', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const photo = '/tmp/viewer-item.png';
    await _loadInter(tester);
    final trade = TradeService(storage);
    final camera = await trade.addDevice(
      userId: SeedData.anaUserId,
      name: 'Canon AE-1 s objektivom',
      model: 'AE-1',
      condition: DeviceCondition.veryGood,
      price: 12,
      category: DeviceCategory.camera,
      imagePaths: [photo],
    );
    await trade.addDevice(
      userId: SeedData.anaUserId,
      name: 'QA objektiv',
      model: '50mm',
      condition: DeviceCondition.good,
      price: 40,
      category: DeviceCategory.camera,
    );
    final live = LiveService(storage);
    final show = await live.create(
      hostId: SeedData.anaUserId,
      title: 'Aukcija uživo',
      items: [(camera.id, 12)],
      lotSeconds: 60,
      shop: true,
      video: false,
    );
    await live.startLot(SeedData.anaUserId, show.id);
    await live.chat(SeedData.markoUserId, show.id, 'Koliko je dostava?');
    await live.chat(SeedData.anaUserId, show.id, 'Dostava BOX NOW 3 €');

    await tester.pumpWidget(app(LiveRoomScreen(showId: show.id)));
    await _frames(tester);

    expect(find.byKey(const ValueKey('live-no-video')), findsOneWidget);
    expect(find.text('Video trenutno nije uključen'), findsNothing);
    expect(find.byKey(const ValueKey('live-lot')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-featured')), findsNothing);
    expect(find.textContaining('AUKCIJA'), findsOneWidget);
    expect(find.textContaining('Licitiraj'), findsOneWidget);
    expect(find.text('Početna'), findsNothing);
    expect(find.text('Boostaj show'), findsNothing);
    expect(find.textContaining('Koliko je dostava?'), findsOneWidget);

    final height = tester.view.physicalSize.height;
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('live-lot'))).dy,
      greaterThan(height * 0.55),
    );
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('live-bid'))).dy,
      greaterThan(height * 0.75),
    );

    await tester.enterText(
      find.byKey(const ValueKey('live-chat')),
      'Ima li još objektiva?',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('live-send')));
    await _frames(tester);
    expect(find.textContaining('Ima li još objektiva?'), findsOneWidget);
    expect(
      storage
          .liveEventsOf(show.id)
          .where((e) => e.text == 'Ima li još objektiva?'),
      hasLength(1),
    );
    await _frames(tester);
    await _shoot(tester, 'viewer-auction-390x844');
    await _frames(tester);
    await _shoot(tester, 'viewer-auction-390x844');
    await _shoot(tester, 'viewer-no-video-390x844');

    await tester.tap(find.byKey(const ValueKey('live-room-tools')));
    await _frames(tester);
    expect(find.text('Boostaj show'), findsNothing);
    expect(find.byKey(const ValueKey('live-share')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-react-0')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
