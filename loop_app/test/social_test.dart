import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/app.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/story.dart';
import 'package:loop_app/models/wishlist.dart';
import 'package:loop_app/providers/app_providers.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/screens/device_detail_screen.dart';
import 'package:loop_app/services/inbox.dart';
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

    test('isključene obavijesti ne stižu, važne stižu uvijek', () async {
      final inbox = Inbox(storage);
      final u = storage.userById(demo)!;
      await storage.putUser(
        u.copyWith(mutedNotifications: [NotificationPref.outbid.name]),
      );
      await inbox.send(demo, NotificationKind.outbid, args: ['X', 10]);
      await inbox.send(demo, NotificationKind.outbidAuto, args: ['X', 10]);
      await inbox.send(demo, NotificationKind.auctionWon, args: ['X', 10]);
      await inbox.send(demo, NotificationKind.newBid, args: ['X', 10]);
      final kinds = storage.notifications
          .where((n) => n.userId == demo)
          .map((n) => n.kind)
          .toSet();
      expect(kinds, {NotificationKind.auctionWon, NotificationKind.newBid});
      expect(NotificationPref.of(NotificationKind.auctionWon), isNull);
      expect(NotificationKind.outbid.group, NotificationGroup.auctions);
      expect(
        AppUser.fromMap(storage.userById(demo)!.toMap()).mutedNotifications,
        ['outbid'],
      );
    });

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

    test('priča s tekstovima: spremanje, granice, starije priče', () async {
      final s = await stories.create(
        userId: demo,
        color: 3,
        texts: const [
          StoryText(
            text: ' Akcija ',
            x: 1.4,
            y: -0.2,
            size: 0.9,
            rotation: 0.3,
            font: StoryFont.neon,
            color: 0xFFFF2D55,
            align: TextAlign.right,
            background: StoryTextBackground.soft,
          ),
          StoryText(text: '   '), // prazan tekst se preskače
        ],
      );
      final saved = storage.stories.single;
      expect(saved.texts, hasLength(1));
      final l = saved.texts.single;
      expect(l.text, 'Akcija');
      expect((l.x, l.y, l.size), (1.0, 0.0, StoryText.maxSize));
      expect(l.rotation, 0.3);
      expect(l.font, StoryFont.neon);
      expect(l.align, TextAlign.right);
      expect(l.background, StoryTextBackground.soft);
      expect(saved.text, 'Akcija'); // za starije verzije
      expect(Story.fromMap(s.toMap()).texts.single.color, 0xFFFF2D55);

      expect(
        () => stories.create(
          userId: demo,
          texts: [
            for (var i = 0; i <= Story.maxTexts; i++) StoryText(text: '$i'),
          ],
        ),
        throwsA(isA<TradeException>()),
      );
      expect(
        () => stories.create(
          userId: demo,
          texts: [StoryText(text: 'x' * (Story.maxText + 1))],
        ),
        throwsA(isA<TradeException>()),
      );
      // Starija priča (samo tekst) prikazuje se kao jedan tekst u sredini.
      final legacy = Story.fromMap({
        'id': 'a',
        'userId': demo,
        'text': 'Stara',
        'createdAt': DateTime.now().toIso8601String(),
      });
      expect(legacy.layers.single.text, 'Stara');
      expect(legacy.layers.single.x, 0.5);
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

      // Moja priča u uredniku (kao na Instagramu).
      await tester.tap(find.byKey(const ValueKey('my-story')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-canvas')), findsOneWidget);
      expect(find.text('Dodirni za tekst'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-add-text')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('story-text')),
        'Danas −20%',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('story-font-script')),
        100,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('story-fonts')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('story-font-script')));
      await tester.tap(find.byKey(const ValueKey('story-color-4')));
      await tester.tap(find.byKey(const ValueKey('story-text-bg')));
      await tester.tap(find.byKey(const ValueKey('story-align')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('story-text-done')));
      await tester.pumpAndSettle();
      final layer0 = find.byKey(const ValueKey('story-layer-0'));
      expect(layer0, findsOneWidget);
      // Povuci tekst niže.
      await tester.drag(layer0, const Offset(30, 110));
      await tester.pumpAndSettle();

      // Drugi tekst (dodir na prazno mjesto) pa ga povuci u kantu.
      final canvas = tester.getRect(find.byKey(const ValueKey('story-canvas')));
      await tester.tapAt(canvas.topLeft + const Offset(40, 100));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('story-text')), 'Briši');
      await tester.tap(find.byKey(const ValueKey('story-text-done')));
      await tester.pumpAndSettle();
      final layer1 = find.byKey(const ValueKey('story-layer-1'));
      expect(layer1, findsOneWidget);
      final start = tester.getCenter(layer1);
      await tester.dragFrom(
        start,
        canvas.bottomCenter - const Offset(0, 56) - start,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('story-layer-1')), findsNothing);

      // Ponovno uređivanje prvog teksta.
      await tester.tap(layer0);
      await tester.pumpAndSettle();
      expect(find.text('Danas −20%'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('story-text-done')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('publish-story')));
      await tester.pumpAndSettle();
      expect(storage.stories.where((s) => s.userId == demo), hasLength(1));
      final mine = storage.stories.firstWhere((s) => s.userId == demo);
      final l = mine.texts.single;
      expect(l.text, 'Danas −20%');
      expect(l.font, StoryFont.script);
      expect(l.color, StoryText.colors[4]);
      expect(l.background, StoryTextBackground.solid);
      expect(l.align, TextAlign.left);
      expect(l.y, greaterThan(0.45));
      expect(l.x, greaterThan(0.5));

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
