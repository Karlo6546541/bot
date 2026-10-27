// Isolated screenshot fixture. Production continues to start at lib/main.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/screens/auctions_screen.dart';
import 'package:loop_app/screens/for_you_ranker.dart';
import 'package:loop_app/services/feed_preferences.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = StorageService();
  await storage.init();
  final trade = TradeService(storage);
  await trade.assignPlatformItems();
  await trade.autoListPortfolios();
  final samples = <String>{};
  for (var index = 0; index < 8; index++) {
    final sample = await trade.addDevice(
      userId: SeedData.anaUserId,
      name: 'Sony PSP',
      model: '3004, crna',
      condition: DeviceCondition.good,
      price: 69,
      category: DeviceCategory.console,
      description: 'Nova baterija, 4GB kartica. Ispravan i spreman za igranje.',
      // Public product reference from Wikimedia Commons, loaded only by this fixture.
      imagePaths: const [
        'https://upload.wikimedia.org/wikipedia/commons/5/5d/Sony-PSP-1000-Body.png',
      ],
    );
    samples.add(sample.id);
  }
  final lives = LiveService(storage);
  final liveItem = await trade.addDevice(
    userId: SeedData.markoUserId,
    name: 'Game Boy Pocket',
    model: 'srebrni',
    condition: DeviceCondition.good,
    price: 55,
    category: DeviceCategory.console,
    imagePaths: const [
      'https://upload.wikimedia.org/wikipedia/commons/5/5d/Sony-PSP-1000-Body.png',
    ],
  );
  final previewLive = await lives.create(
    hostId: SeedData.markoUserId,
    items: [(liveItem.id, 21)],
    lotSeconds: 60,
    coverPath:
        'https://upload.wikimedia.org/wikipedia/commons/5/5d/Sony-PSP-1000-Body.png',
    title: 'Konzole uživo',
    category: DeviceCategory.console.name,
  );
  await lives.create(
    hostId: SeedData.demoUserId,
    title: 'Knjige uživo',
    category: DeviceCategory.books.name,
  );
  await lives.startLot(SeedData.markoUserId, previewLive.id);
  await lives.chat(SeedData.anaUserId, previewLive.id, 'Prvi put sam tu 👋');
  await storage.saveSession(userId: SeedData.testUserId);
  // Exercise BOX NOW on the release web runtime, including a duplicate confirm.
  final shipping = DeliveryService(storage);
  final pending = await shipping.createPending(
    id: 'preview-boxnow-0',
    userId: SeedData.testUserId,
    deviceId: liveItem.id,
    deviceName: liveItem.name,
    sellerId: SeedData.markoUserId,
  );
  final selected = await shipping.choose(
    userId: SeedData.testUserId,
    deliveryId: pending.id,
    method: DeliveryMethod.parcelLocker,
    destination: kDemoLockers.first,
  );
  final repeated = await shipping.choose(
    userId: SeedData.testUserId,
    deliveryId: pending.id,
    method: DeliveryMethod.parcelLocker,
    destination: kDemoLockers.first,
  );
  if (selected.pickupPin == null || selected.dropOffPin == null ||
      selected.trackingNumber != repeated.trackingNumber) {
    throw StateError('BOX NOW release-web delivery verification failed');
  }

  final prefs = FeedPreferences();
  for (final i in browseItems(AppState.fromStorage(storage))) {
    if (!samples.contains(i.device?.id)) prefs.hide(ForYouRanker.keyOf(i));
  }
  await storage.saveFeedPreferences(SeedData.testUserId, prefs);
  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        tickIntervalProvider.overrideWithValue(null),
      ],
      child: const LoopApp(),
    ),
  );
}
