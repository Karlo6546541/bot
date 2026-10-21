import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/models/swap_offer.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/services/auction_service.dart';
import 'package:loop_app/services/chat_service.dart';
import 'package:loop_app/services/community_service.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/swap_service.dart';
import 'package:loop_app/services/trade_service.dart';

void main() {
  late StorageService storage;
  late TradeService trade;
  late ChatService chat;
  late SwapService swaps;
  const iphone = 'seed-9'; // demo, objavljen u Marketu
  late String testItem;

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    trade = TradeService(storage);
    chat = ChatService(storage);
    swaps = SwapService(storage);
    await trade.list(userId: SeedData.demoUserId, deviceId: iphone, price: 300);
    testItem = (await trade.addDevice(
      userId: SeedData.testUserId,
      name: 'Nintendo Switch',
      model: 'OLED',
      condition: DeviceCondition.excellent,
      price: 250,
      category: DeviceCategory.console,
    )).id;
  });

  tearDown(() async {
    await Hive.close();
  });

  Future<AppState> stateOf(String userId) async {
    await storage.saveSession(userId: userId);
    return AppState.fromStorage(storage);
  }

  group('poruke', () {
    test('razgovor, nepročitano, jedna obavijest dok se ne pročita', () async {
      await chat.send(
        senderId: SeedData.testUserId,
        receiverId: SeedData.demoUserId,
        text: 'Je li još dostupan?',
        deviceId: iphone,
      );
      await chat.send(
        senderId: SeedData.testUserId,
        receiverId: SeedData.demoUserId,
        text: 'Može li 280?',
      );
      final demo = await stateOf(SeedData.demoUserId);
      expect(demo.conversations.single.otherId, SeedData.testUserId);
      expect(demo.unreadMessages, 2);
      expect(
        storage.notifications
            .where((n) => n.kind == NotificationKind.newMessage)
            .length,
        1,
      );
      await chat.markRead(SeedData.demoUserId, SeedData.testUserId);
      expect((await stateOf(SeedData.demoUserId)).unreadMessages, 0);
      expect(storage.notifications.every((n) => n.read), isTrue);

      // Odgovor ide u isti razgovor.
      await chat.send(
        senderId: SeedData.demoUserId,
        receiverId: SeedData.testUserId,
        text: 'Može!',
      );
      expect(
        (await stateOf(SeedData.testUserId)).chatWith(SeedData.demoUserId),
        hasLength(3),
      );
    });

    test('prazna, preduga, sebi i blokiranima — ne', () async {
      Future<void> send(String from, String to, String text) =>
          chat.send(senderId: from, receiverId: to, text: text);
      for (final f in [
        () => send(SeedData.testUserId, SeedData.demoUserId, '   '),
        () => send(SeedData.testUserId, SeedData.demoUserId, 'x' * 501),
        () => send(SeedData.testUserId, SeedData.testUserId, 'hej'),
      ]) {
        await expectLater(f(), throwsA(isA<TradeException>()));
      }
      await CommunityService(
        storage,
      ).toggleBlock(SeedData.demoUserId, SeedData.testUserId);
      await expectLater(
        send(SeedData.testUserId, SeedData.demoUserId, 'hej'),
        throwsA(isA<TradeException>()),
      );
    });
  });

  group('zamjena', () {
    test('ponuda → prihvaćanje: vlasnici, nadoplata, dostave', () async {
      final testBefore = storage.userById(SeedData.testUserId)!.credits;
      final demoBefore = storage.userById(SeedData.demoUserId)!.credits;
      final o = await swaps.offer(
        fromId: SeedData.testUserId,
        wantedDeviceId: iphone,
        offeredDeviceId: testItem,
        extraCredits: 100,
        message: 'Moj + 100?',
      );
      expect(
        (await stateOf(SeedData.demoUserId)).incomingOffers.single.id,
        o.id,
      );
      // Duplikat iste ponude nije dopušten.
      await expectLater(
        swaps.offer(
          fromId: SeedData.testUserId,
          wantedDeviceId: iphone,
          offeredDeviceId: testItem,
        ),
        throwsA(isA<TradeException>()),
      );
      // Samo vlasnik prihvaća.
      await expectLater(
        swaps.accept(SeedData.testUserId, o.id),
        throwsA(isA<TradeException>()),
      );

      final done = await swaps.accept(SeedData.demoUserId, o.id);
      expect(done.status, SwapStatus.accepted);
      expect(storage.deviceById(iphone)!.ownerId, SeedData.testUserId);
      expect(storage.deviceById(iphone)!.isListed, isFalse);
      expect(storage.deviceById(testItem)!.ownerId, SeedData.demoUserId);
      expect(storage.userById(SeedData.testUserId)!.credits, testBefore - 100);
      expect(storage.userById(SeedData.demoUserId)!.credits, demoBefore + 95);
      expect(
        storage.transactions.where((t) => t.type == TransactionType.swap),
        hasLength(2),
      );
      // Oboje biraju dostavu i mogu se poslije ocijeniti.
      final d = storage.deliveries;
      expect(d, hasLength(2));
      expect(d.every((x) => x.awaitingChoice && !x.fromAuction), isTrue);
      expect(
        storage.notifications.map((n) => n.kind),
        containsAll([
          NotificationKind.swapOffer,
          NotificationKind.swapAccepted,
        ]),
      );
    });

    test('odbijanje i povlačenje', () async {
      final o = await swaps.offer(
        fromId: SeedData.testUserId,
        wantedDeviceId: iphone,
        offeredDeviceId: testItem,
      );
      await swaps.decline(SeedData.demoUserId, o.id);
      expect(storage.offerById(o.id)!.status, SwapStatus.declined);
      final o2 = await swaps.offer(
        fromId: SeedData.testUserId,
        wantedDeviceId: iphone,
        offeredDeviceId: testItem,
      );
      await swaps.withdraw(SeedData.testUserId, o2.id);
      expect(storage.offerById(o2.id)!.status, SwapStatus.cancelled);
      await expectLater(
        swaps.accept(SeedData.demoUserId, o2.id),
        throwsA(isA<TradeException>()),
      );
    });

    test('pravila: tuđi objavljeni predmet, svoj ponuđeni, krediti', () async {
      for (final f in [
        // Predmet platforme (nije objavljen od korisnika).
        () => swaps.offer(
          fromId: SeedData.testUserId,
          wantedDeviceId: 'seed-1',
          offeredDeviceId: testItem,
        ),
        // Ne nudi tuđi predmet.
        () => swaps.offer(
          fromId: SeedData.testUserId,
          wantedDeviceId: iphone,
          offeredDeviceId: iphone,
        ),
        // Previše kredita.
        () => swaps.offer(
          fromId: SeedData.testUserId,
          wantedDeviceId: iphone,
          offeredDeviceId: testItem,
          extraCredits: 99999,
        ),
      ]) {
        await expectLater(f(), throwsA(isA<TradeException>()));
      }
    });

    test('prodan predmet: zamjena više nije moguća', () async {
      final o = await swaps.offer(
        fromId: SeedData.testUserId,
        wantedDeviceId: iphone,
        offeredDeviceId: testItem,
      );
      // Marko u međuvremenu kupi iPhone.
      await trade.buy(userId: SeedData.markoUserId, deviceId: iphone);
      await expectLater(
        swaps.accept(SeedData.demoUserId, o.id),
        throwsA(isA<TradeException>()),
      );
      expect(storage.offerById(o.id)!.status, SwapStatus.failed);
    });

    test('ponuđeni predmet na aukciji — ne', () async {
      final item = storage.deviceById(testItem)!;
      if (item.price >= 100) {
        await AuctionService(storage).create(
          userId: SeedData.testUserId,
          deviceId: testItem,
          startPrice: 50,
          duration: const Duration(hours: 1),
        );
        await expectLater(
          swaps.offer(
            fromId: SeedData.testUserId,
            wantedDeviceId: iphone,
            offeredDeviceId: testItem,
          ),
          throwsA(isA<TradeException>()),
        );
      }
    });
  });
}
