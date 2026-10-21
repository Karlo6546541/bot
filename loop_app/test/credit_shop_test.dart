import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/services/credit_shop.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/utils/formatters.dart';

void main() {
  late Directory dir;
  late StorageService storage;
  late CreditShop shop;
  const demo = SeedData.demoUserId;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('loop_shop');
    storage = StorageService();
    await storage.init(path: dir.path);
    shop = CreditShop(storage);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('uplate nemaju bonus', () {
    for (final amount in [100, 250, 700, 1000]) {
      expect(CreditShop.bonusFor(amount), 0);
    }
  });

  test('uplata povećava stanje i bilježi transakciju', () async {
    final tx = await shop.purchase(
      userId: demo,
      credits: 500,
      method: PaymentMethod.paypal,
    );
    expect(storage.userById(demo)!.credits, 1250 + 500);
    expect(tx.type, TransactionType.topUp);
    expect(tx.price, 500);
    expect(tx.amount, 500);
    expect(storage.historyOf(demo).last.credits, 1750);
  });

  test('dnevni limit i granice iznosa', () async {
    await shop.purchase(
      userId: demo,
      credits: 1500,
      method: PaymentMethod.card,
    );
    expect(shop.remainingToday(demo), 500);
    await expectLater(
      shop.purchase(userId: demo, credits: 600, method: PaymentMethod.card),
      throwsA(isA<TradeException>()),
    );
    // Sutradan je limit ponovno pun.
    expect(
      shop.remainingToday(
        demo,
        now: DateTime.now().add(const Duration(days: 2)),
      ),
      CreditShop.dailyLimit,
    );
    await expectLater(
      shop.purchase(userId: demo, credits: 5, method: PaymentMethod.card),
      throwsA(isA<TradeException>()),
    );
  });

  test('hrvatski format iznosa', () {
    expect(formatCredits(1250), '1.250 €');
    expect(formatCredits(294.5), '294,50 €');
    expect(formatCredits(1), '1 €');
    expect(formatCredits(-12.5), '−12,50 €');
    expect(formatEuro(49.9), '49,90 €');
  });
}
