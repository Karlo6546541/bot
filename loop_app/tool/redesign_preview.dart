import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/screens/account_health_screen.dart';
import 'package:loop_app/screens/inventory_screen.dart';
import 'package:loop_app/screens/deliveries_screen.dart';
import 'package:loop_app/screens/activity_screen.dart';
import 'package:loop_app/screens/search_screen.dart';
import 'package:loop_app/screens/profile_screen.dart';
import 'package:loop_app/widgets/trade_actions.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/widgets/purchase_confirmation.dart';
import 'package:loop_app/services/stripe_backend.dart';
// Isolated screenshot fixture. Production continues to start at lib/main.dart.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loop_app/app.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:loop_app/theme/app_theme.dart';
import 'package:loop_app/models/seller_info.dart';
import 'package:loop_app/screens/seller_screens.dart';
import 'package:loop_app/screens/seller_hub.dart';
import 'package:loop_app/screens/messages_screen.dart';
import 'package:loop_app/screens/notifications_screen.dart';
import 'package:loop_app/screens/seller_finance_screens.dart';
import 'package:loop_app/screens/device_detail_screen.dart';
import 'package:loop_app/screens/login_screen.dart';
import 'package:loop_app/screens/public_profile_screen.dart';
import 'package:loop_app/screens/live_screens.dart';
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

class _PreviewTab extends HomeTab {
  _PreviewTab(this.index);
  final int index;
  @override
  int build() => index;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final route = Uri.base.queryParameters['preview'] ?? 'home';
  final profilePreview = [
    'profile',
    'categories',
    'activity',
    'studio',
    'settings',
  ].contains(route);
  previewSemanticsHandle = SemanticsBinding.instance.ensureSemantics();
  final storage = StorageService();
  await storage.init(inMemory: true);
  await storage.setThemeMode(Uri.base.queryParameters['theme'] ?? 'light');
  final trade = TradeService(storage);
  await trade.assignPlatformItems();
  await trade.autoListPortfolios();
  final samples = <String>{};
  const products = [
    ('Sony WH-1000XM3', 'Slušalice', 66.0, 'photo-1546435770-a3e426bf472b'),
    (
      'Fender Stratocaster',
      'Električna gitara',
      96.0,
      'photo-1510915361894-db8b60106cb1',
    ),
    (
      'Canon EOS',
      'Digitalni fotoaparat',
      180.0,
      'photo-1516035069371-29a1b244cc32',
    ),
    ('Vintage sat', 'Čelik, 38 mm', 48.0, 'photo-1524805444758-089113d48a6d'),
    ('Nike Air', 'Veličina 42', 54.0, 'photo-1542291026-7eec264c27ff'),
    ('Monstera', 'Sobna biljka', 24.0, 'photo-1416879595882-3373a0480b5b'),
  ];
  for (var index = 0; index < products.length; index++) {
    final sample = await trade.addDevice(
      userId: index < 2 ? SeedData.testUserId : SeedData.anaUserId,
      name: products[index].$1,
      model: products[index].$2,
      condition: DeviceCondition.good,
      price: products[index].$3,
      category: DeviceCategory.console,
      description: 'Odlično očuvano. Sve radi, spremno za novog vlasnika.',
      // Public sample photos, loaded only by this isolated fixture.
      imagePaths: [
        'https://images.unsplash.com/${products[index].$4}?auto=format&fit=crop&w=800&q=85',
      ],
    );
    samples.add(sample.id);
  }
  final lives = LiveService(storage);
  final liveItem = await trade.addDevice(
    userId: SeedData.markoUserId,
    name: 'Seiko Automatic',
    model: 'Vintage kolekcija',
    condition: DeviceCondition.good,
    price: 55,
    category: DeviceCategory.watches,
    imagePaths: const [
      'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=900&q=85',
    ],
  );
  final previewLive = await lives.create(
    hostId: SeedData.markoUserId,
    items: [(liveItem.id, 21)],
    lotSeconds: 60,
    coverPath:
        'https://images.unsplash.com/photo-1523275335684-37898b6baf30?auto=format&fit=crop&w=900&q=85',
    title: 'Satovi s pričom.',
    category: DeviceCategory.watches.name,
  );
  final secondLive = await lives.create(
    hostId: SeedData.demoUserId,
    title: 'Sneaker kolekcija',
    coverPath:
        'https://images.unsplash.com/photo-1552346154-21d32810aba3?auto=format&fit=crop&w=600&q=85',
    category: DeviceCategory.sneakers.name,
  );
  await storage.putUser(
    AppUser(
      id: 'preview-retro-host',
      email: 'retro@example.test',
      name: 'Retro Studio',
      username: 'retro.studio',
      credits: 0,
      createdAt: DateTime(2026),
      seller: storage.userById(SeedData.anaUserId)!.seller,
    ),
  );
  final thirdLive = await lives.create(
    hostId: 'preview-retro-host',
    title: 'Analogni klasici',
    coverPath:
        'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?auto=format&fit=crop&w=600&q=85',
  );
  final upcomingLive = await lives.create(
    hostId: SeedData.anaUserId,
    title: 'Vintage pronalasci',
    startsAt: DateTime.now().add(const Duration(hours: 2)),
  );
  await lives.create(
    hostId: SeedData.testUserId,
    title: 'Moj sljedeći live',
    startsAt: DateTime.now().add(const Duration(hours: 3)),
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
    if (!samples.contains(i.device?.id) &&
        !{
          previewLive.id,
          secondLive.id,
          thirdLive.id,
          upcomingLive.id,
        }.contains(i.show?.id)) {
      prefs.hide(ForYouRanker.keyOf(i));
    }
  }
  await storage.saveFeedPreferences(SeedData.testUserId, prefs);
  await storage.putUser(
    storage
        .userById(SeedData.testUserId)!
        .copyWith(
          seller: SellerInfo(
            legalName: 'Test Prodavatelj',
            oib: '12345678903',
            address: 'Ilica 1, 10000 Zagreb',
            iban: 'HR1723600001101234565',
            birthDate: DateTime(1990),
            updatedAt: DateTime(2026),
          ),
        ),
  );

  // Additional records belong only to the in-memory visual fixture.
  final previewNow = DateTime.now();
  for (var i = 0; i < 4; i++) {
    final device = storage.deviceById(samples.elementAt(i % 2))!;
    await storage.putDelivery(
      Delivery(
        id: 'preview-seller-$i',
        deviceId: device.id,
        deviceName: device.name,
        buyerId: SeedData.anaUserId,
        sellerId: SeedData.testUserId,
        createdAt: previewNow.subtract(Duration(hours: i)),
        method: DeliveryMethod.courier,
        destination: 'Ilica 1, Zagreb',
        startedAt: previewNow,
        trackingNumber: 'DEMO-$i',
        handedOverAt: i >= 2 ? previewNow : null,
        confirmedAt: i == 3 ? previewNow : null,
      ),
    );
    await storage.putTransaction(
      LoopTransaction(
        id: 'preview-sale-$i',
        type: TransactionType.sell,
        userId: SeedData.testUserId,
        sellerId: SeedData.testUserId,
        buyerId: SeedData.anaUserId,
        deviceId: device.id,
        deviceName: device.name,
        price: device.price,
        fee: device.price * .06,
        amount: device.price * .94,
        buyerLabel: 'Ana',
        sellerLabel: 'Test',
        createdAt: previewNow.subtract(Duration(days: i)),
      ),
    );
  }
  final boughtDevice = storage.deviceById(samples.elementAt(2))!;
  await shipping.createPending(
    id: 'preview-wallet-ticket',
    userId: SeedData.testUserId,
    deviceId: boughtDevice.id,
    deviceName: boughtDevice.name,
    sellerId: SeedData.anaUserId,
  );
  await storage.putNotification(
    AppNotification(
      id: 'preview-important',
      userId: SeedData.testUserId,
      kind: NotificationKind.bargainAccepted,
      createdAt: previewNow,
      targetId: boughtDevice.id,
      args: const ['Ana', '25 €', 'Canon EOS'],
    ),
  );
  await storage.putNotification(
    AppNotification(
      id: 'preview-update',
      userId: SeedData.testUserId,
      kind: NotificationKind.newFollower,
      createdAt: previewNow.subtract(const Duration(hours: 2)),
      targetId: SeedData.anaUserId,
      args: const ['Ana'],
    ),
  );
  if (route == 'host') await storage.saveSession(userId: SeedData.markoUserId);
  runApp(
    ProviderScope(
      overrides: [
        if (route == 'settings')
          profileSettingsProvider.overrideWith(_PreviewSettings.new),
        if (profilePreview)
          homeTabProvider.overrideWith(
            () => _PreviewTab(switch (route) {
              'categories' => 1,
              'activity' => 2,
              'studio' => 4,
              'settings' => 3,
              _ => 3,
            }),
          ),
        storageProvider.overrideWithValue(storage),
        tickIntervalProvider.overrideWithValue(null),
      ],
      child: _PreviewRoot(
        route: route,
        item: storage.deviceById(samples.skip(2).first)!,
        showId: previewLive.id,
      ),
    ),
  );
}

class _PreviewRoot extends StatelessWidget {
  const _PreviewRoot({
    required this.route,
    required this.item,
    required this.showId,
  });
  final String route;
  final Device item;
  final String showId;
  @override
  Widget build(BuildContext context) {
    final page = switch (route) {
      'purchase' => _PurchasePreview(item: item),
      'shop' => const PublicProfileScreen(userId: SeedData.anaUserId),
      'live' || 'host' => LiveRoomScreen(showId: showId),
      'seller' => const SellerHubScreen(),
      'inventory' => const InventoryScreen(),
      'shipping' => const DeliveryNotesScreen(),
      'health' => const AccountHealthScreen(),
      'history' => const ActivityPage(),
      'search' => const SearchScreen(),
      'sales' => const MyAuctionsScreen(),
      'wallet' => const _WalletPreview(),
      'form' => const SellerInfoScreen(),
      'messages' => const MessagesScreen(),
      'notifications' => const NotificationsScreen(),
      'finance' => const FinancialsScreen(),
      'listing' => DeviceDetailScreen(deviceId: item.id),
      'login' => const LoginScreen(),
      _ => null,
    };
    if (page == null) return const LoopApp();
    LoopColors.use(
      Uri.base.queryParameters['theme'] == 'dark'
          ? Brightness.dark
          : Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildLoopTheme(),
      locale: const Locale('hr'),
      supportedLocales: const [Locale('hr'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: page,
    );
  }
}

// An isolated visual confirmation. It cannot contact a payment provider.
class _PurchasePreview extends StatefulWidget {
  const _PurchasePreview({required this.item});
  final Device item;
  @override
  State<_PurchasePreview> createState() => _PurchasePreviewState();
}

class _PurchasePreviewState extends State<_PurchasePreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showPurchaseConfirmation(
        context,
        PurchaseConfirmationSheet(
          title: widget.item.name,
          totalCents: 6600,
          address: 'Ilica 1, 10000 Zagreb',
          loadCard: () async => (hasCard: true, last4: '4242'),
          addCard: (_) async => false,
          reserve: () async => {'id': 'preview-only', 'total_cents': 6600},
          chooseDelivery: (_, _) async {},
          charge: (_, _) async => SavedCardChargeStatus.processing,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      DeviceDetailScreen(deviceId: widget.item.id);
}

class _PreviewSettings extends ProfileSettingsController {
  @override
  bool build() => true;
}

class _WalletPreview extends ConsumerStatefulWidget {
  const _WalletPreview();
  @override
  ConsumerState<_WalletPreview> createState() => _WalletPreviewState();
}

class _WalletPreviewState extends ConsumerState<_WalletPreview> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showWallet(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold();
}
