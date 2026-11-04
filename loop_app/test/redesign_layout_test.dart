import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/seller_info.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/screens/activity_view.dart';
import 'package:loop_app/screens/add_device_screen.dart';
import 'package:loop_app/screens/categories_screen.dart';
import 'package:loop_app/screens/create_auction_screen.dart';
import 'package:loop_app/screens/device_detail_screen.dart';
import 'package:loop_app/screens/live_home_screen.dart';
import 'package:loop_app/screens/login_screen.dart';
import 'package:loop_app/screens/messages_screen.dart';
import 'package:loop_app/screens/notifications_screen.dart';
import 'package:loop_app/screens/search_screen.dart';
import 'package:loop_app/screens/seller_finance_screens.dart';
import 'package:loop_app/screens/seller_hub.dart';
import 'package:loop_app/screens/seller_screens.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/theme/app_theme.dart';

void main() {
  late StorageService storage;
  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    await storage.saveSession(userId: SeedData.testUserId);
    await storage.putUser(
      storage
          .userById(SeedData.testUserId)!
          .copyWith(
            seller: SellerInfo(
              legalName: 'Test Seller',
              oib: '12345678903',
              address: 'Ilica 1, Zagreb',
              iban: 'HR1723600001101234565',
              birthDate: DateTime(1990),
              updatedAt: DateTime(2026),
            ),
          ),
    );
  });
  tearDown(Hive.close);
  final pages = <String, Widget Function()>{
    'home': () => const Scaffold(body: LiveHomeScreen()),
    'categories': () => const Scaffold(body: CategoriesScreen()),
    'activity': () => const Scaffold(body: ActivityView()),
    'seller hub': () => const SellerHubScreen(),
    'seller details': () => const SellerInfoScreen(),
    'listing': () => DeviceDetailScreen(
      deviceId: storage.devices
          .firstWhere((d) => d.ownerId != SeedData.testUserId)
          .id,
    ),
    'search': () => const SearchScreen(),
    'messages': () => const MessagesScreen(),
    'notifications': () => const NotificationsScreen(),
    'finances': () => const FinancialsScreen(),
    'publish item': () => const AddDeviceScreen(),
    'publish auction': () => const CreateAuctionScreen(),
    'login': () => const LoginScreen(),
  };
  for (final config in [
    (
      name: 'small phone',
      size: const Size(320, 640),
      scale: 1.0,
      brightness: Brightness.light,
    ),
    (
      name: 'large text',
      size: const Size(390, 844),
      scale: 1.5,
      brightness: Brightness.light,
    ),
    (
      name: 'dark phone',
      size: const Size(390, 844),
      scale: 1.0,
      brightness: Brightness.dark,
    ),
    (
      name: 'tablet',
      size: const Size(768, 1024),
      scale: 1.0,
      brightness: Brightness.light,
    ),
    (
      name: 'desktop',
      size: const Size(1440, 900),
      scale: 1.0,
      brightness: Brightness.light,
    ),
  ]) {
    testWidgets('core routes render and dispose on ${config.name}', (
      tester,
    ) async {
      tester.view.physicalSize = config.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final report = FlutterError.onError;
      FlutterError.onError = (details) {
        FlutterError.dumpErrorToConsole(details);
        report?.call(details);
      };
      addTearDown(() => FlutterError.onError = report);
      LoopColors.use(config.brightness);
      for (final page in pages.entries) {
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
                ).copyWith(textScaler: TextScaler.linear(config.scale)),
                child: child!,
              ),
              home: page.value(),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.key} on ${config.name}',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'dispose ${page.key}');
      }
    });
  }
}
