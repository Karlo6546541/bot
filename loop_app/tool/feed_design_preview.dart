// Isolated screenshot fixture. Production continues to start at lib/main.dart.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/delivery.dart';
import 'package:loop_app/services/delivery_service.dart';
import 'package:loop_app/services/boxnow/boxnow.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/screens/auctions_screen.dart';
import 'package:loop_app/screens/for_you_ranker.dart';
import 'package:loop_app/services/feed_preferences.dart';
import 'package:loop_app/services/live_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

SemanticsHandle? previewSemanticsHandle;

class _ProfilePreviewTab extends HomeTab {
  @override
  int build() => 3;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final profilePreview = Uri.base.queryParameters['preview'] == 'profile';
  if (profilePreview) {
    previewSemanticsHandle = SemanticsBinding.instance.ensureSemantics();
  }
  final storage = StorageService();
  await storage.init();
  final trade = TradeService(storage);
  await trade.assignPlatformItems();
  await trade.autoListPortfolios();
  final samples = <String>{};
  for (var index = 0; index < 8; index++) {
    final sample = await trade.addDevice(
      userId: index < 2 ? SeedData.testUserId : SeedData.anaUserId,
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
  await trade.toggleFavorite(SeedData.testUserId, samples.last);
  // Exercise BOX NOW on the release web runtime, including a duplicate confirm.
  final shipping = DeliveryService(storage);
  const locker = BoxNowLocker(
    id: '1234',
    address: 'Ilica 1',
    postalCode: '10000',
    name: 'BOX NOW Ilica',
  );
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
    destination: locker.destination,
  );
  final repeated = await shipping.choose(
    userId: SeedData.testUserId,
    deliveryId: pending.id,
    method: DeliveryMethod.parcelLocker,
    destination: locker.destination,
  );
  if (selected.pickupPin == null ||
      selected.dropOffPin == null ||
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
        if (profilePreview)
          homeTabProvider.overrideWith(_ProfilePreviewTab.new),
        storageProvider.overrideWithValue(storage),
        tickIntervalProvider.overrideWithValue(null),
      ],
      child: const LoopApp(),
    ),
  );
}
