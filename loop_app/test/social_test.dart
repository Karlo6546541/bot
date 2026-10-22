import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/story.dart';
import 'package:loop_app/models/wishlist.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/screens/device_detail_screen.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/social_service.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Liste želja i priče (stories).
void main() {
  const demo = SeedData.demoUserId;
  const other = SeedData.testUserId;

  Future<Device> addLamp(TradeService trade, String owner) => trade.addDevice(
    userId: owner,
    name: 'Stolna lampa',
    model: 'Mjed',
    condition: DeviceCondition.good,
    price: 100,
    category: DeviceCategory.values.firstWhere(
      (c) => c.section != ItemSection.digital,
    ),
  );

  group('servisi', () {
    late StorageService storage;
    late WishlistService lists;
    late StoryService stories;
    late TradeService trade;

    setUp(() async {
      storage = StorageService();
      await storage.init(inMemory: true);
      lists = WishlistService(storage);
      stories = StoryService(storage);
      trade = TradeService(storage);
    });
    tearDown(() => Hive.close());

    test(
      'lista: stvori, jedinstven naziv, dodaj/ukloni, uredi, obriši',
      () async {
        final lamp = await addLamp(trade, other);
        final w = await lists.create(demo, '  Za stan ', emoji: '🏠');
        expect(w.name, 'Za stan');
        expect(
          () => lists.create(demo, 'za STAN'),
          throwsA(isA<TradeException>()),
        );
        expect(() => lists.create(demo, '   '), throwsA(isA<TradeException>()));
        expect(
          () => lists.create(demo, 'x' * (Wishlist.maxName + 1)),
          throwsA(isA<TradeException>()),
        );

        expect(await lists.toggleItem(demo, w.id, lamp.id), isTrue);
        expect(storage.userById(demo)!.wishlistById(w.id)!.deviceIds, [
          lamp.id,
        ]);
        expect(await lists.toggleItem(demo, w.id, lamp.id), isFalse);
        expect(storage.userById(demo)!.wishlistById(w.id)!.deviceIds, isEmpty);

        final g = await lists.create(demo, 'Pokloni');
        expect(
          () => lists.edit(demo, g.id, name: 'Za stan'),
          throwsA(isA<TradeException>()),
        );
        await lists.edit(demo, g.id, name: 'Rođendan', emoji: '🎂');
        final edited = storage.userById(demo)!.wishlistById(g.id)!;
        expect((edited.name, edited.emoji), ('Rođendan', '🎂'));

        await lists.delete(demo, w.id);
        expect(storage.userById(demo)!.wishlists.map((x) => x.id), [g.id]);
        expect(
          () => lists.toggleItem(demo, w.id, lamp.id),
          throwsA(isA<TradeException>()),
        );
        // Liste se spremaju u korisnika (i sinkroniziraju s njim).
        final roundTrip = storage.userById(demo)!.toMap();
        expect(roundTrip['wishlists'], isNotEmpty);
      },
    );

    test('lista: najviše ${Wishlist.maxLists} lista', () async {
      for (var i = 0; i < Wishlist.maxLists; i++) {
        await lists.create(demo, 'Lista $i');
      }
      expect(() => lists.create(demo, 'Još'), throwsA(isA<TradeException>()));
    });

    test('priča: sadržaj, samo svoj oglas, ograničenje, brisanje', () async {
      final mine = await addLamp(trade, demo);
      final theirs = await addLamp(trade, other);
      expect(
        () => stories.create(userId: demo),
        throwsA(isA<TradeException>()),
      );
      expect(
        () => stories.create(userId: demo, deviceId: theirs.id),
        throwsA(isA<TradeException>()),
      );
      expect(
        () => stories.create(userId: demo, text: 'x' * (Story.maxText + 1)),
        throwsA(isA<TradeException>()),
      );
      final s = await stories.create(
        userId: demo,
        text: ' Novo stiglo! ',
        deviceId: mine.id,
        color: 2,
      );
      expect(s.text, 'Novo stiglo!');
      expect(storage.stories.map((x) => x.id), contains(s.id));
      expect(() => stories.delete(other, s.id), throwsA(isA<TradeException>()));
      await stories.delete(demo, s.id);
      expect(storage.stories, isEmpty);

      for (var i = 0; i < StoryService.maxActive; i++) {
        await stories.create(userId: demo, text: '$i');
      }
      expect(
        () => stories.create(userId: demo, text: 'previše'),
        throwsA(isA<TradeException>()),
      );
    });

    test('priča traje 24 h; istekle se brišu, grupe i "viđeno"', () async {
      final now = DateTime.now();
      final old = await stories.create(
        userId: other,
        text: 'Jučer',
        now: now.subtract(const Duration(hours: 25)),
      );
      final fresh = await stories.create(userId: other, text: 'Danas');
      expect(old.activeAt(now), isFalse);
      expect(fresh.activeAt(now), isTrue);

      var state = AppState.fromStorage(storage);
      final g = state.storiesOf(other)!;
      expect(g.stories.map((s) => s.id), [fresh.id]);
      expect(g.seen, isFalse);

      await storage.markStorySeen(fresh.id);
      state = AppState.fromStorage(storage);
      expect(state.storiesOf(other)!.seen, isTrue);

      await stories.purgeExpired(other, now: now);
      expect(storage.stories.map((s) => s.id), [fresh.id]);
      // Nakon 24 h nestaje i nova.
      await stories.purgeExpired(
        other,
        now: now.add(Story.lifetime + const Duration(minutes: 1)),
      );
      expect(storage.stories, isEmpty);
    });
  });

  for (final size in const [Size(1400, 1000), Size(400, 860)]) {
    testWidgets('priče i liste želja ($size)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final storage = StorageService();
      late Device lamp;
      await tester.runAsync(() async {
        await storage.init(inMemory: true);
        lamp = await addLamp(TradeService(storage), other);
        await StoryService(
          storage,
        ).create(userId: other, text: 'Novo stiglo!', deviceId: lamp.id);
      });
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

      // Red s pričama na početnoj.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('stories-row')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-$other')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-viewer')), findsOneWidget);
      expect(find.text('Novo stiglo!'), findsOneWidget);
      expect(find.byKey(const ValueKey('story-item')), findsOneWidget);
      expect(find.byKey(const ValueKey('story-delete')), findsNothing);
      expect(storage.seenStories, isNotEmpty);
      await tester.tap(find.byKey(const ValueKey('story-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-viewer')), findsNothing);

      // Moja priča.
      await tester.tap(find.byKey(const ValueKey('my-story')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('story-text')),
        'Danas −20%',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('publish-story')));
      await tester.pumpAndSettle();
      expect(storage.stories.where((s) => s.userId == demo), hasLength(1));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Spremi oglas u novu listu (s oglasa).
      await tester.tap(find.text('Profil').last);
      await tester.pumpAndSettle();
      DeviceDetailScreen.open(
        tester.element(find.byKey(const ValueKey('my-wishlists'))),
        lamp,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-item')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('new-list')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('list-name')),
        'Za stan',
      );
      await tester.tap(find.text('🏠'));
      await tester.tap(find.byKey(const ValueKey('list-save')));
      await tester.pumpAndSettle();
      final list = storage.userById(demo)!.wishlists.single;
      expect(list.name, 'Za stan');
      expect(list.deviceIds, [lamp.id]);
      expect(find.text('Spremljeno u "Za stan"'), findsOneWidget);
      // Ponovni dodir kvačice uklanja i vraća.
      await tester.tap(find.byKey(ValueKey('save-${list.id}')));
      await tester.pumpAndSettle();
      expect(storage.userById(demo)!.wishlists.single.deviceIds, isEmpty);
      await tester.tap(find.byKey(ValueKey('save-${list.id}')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10)); // zatvori listu
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Profil → Liste želja → lista.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('my-wishlists')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Liste želja (2)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('my-wishlists')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('list-likes')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('list-${list.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Stolna lampa'), findsWidgets);
      expect(find.byTooltip('Podijeli listu'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
