import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_notification.dart';
import 'package:loop_app/models/device.dart';
import 'package:loop_app/models/report.dart';
import 'package:loop_app/models/seller_info.dart';
import 'package:loop_app/services/community_service.dart';
import 'package:loop_app/services/dac7.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';

/// Pravni dio: podaci prodavatelja, DAC7, Omnibus (cijena 30 dana,
/// provjerene ocjene), DSA (obrazloženje i žalba).
void main() {
  const demo = SeedData.demoUserId;
  const tester = SeedData.testUserId;

  group('podaci prodavatelja', () {
    test('OIB i IBAN: kontrolni zbroj', () {
      expect(SellerInfo.validOib('12345678903'), isTrue);
      expect(SellerInfo.validOib('12345678904'), isFalse);
      expect(SellerInfo.validOib('1234'), isFalse);
      expect(SellerInfo.validIban('HR25 2340 0091 1111 1111 1'), isTrue);
      expect(SellerInfo.validIban('HR1210010051863000160'), isTrue);
      expect(SellerInfo.validIban('HR2623400091111111111'), isFalse);
      expect(SellerInfo.validIban('HR251'), isFalse);
    });

    test('prodavatelj je fizička osoba i mora biti punoljetan', () {
      String? check(DateTime? birth) => SellerInfo.validate(
        legalName: 'Ivo Ivić',
        oib: '12345678903',
        address: 'Ilica 1, Zagreb',
        iban: 'HR2523400091111111111',
        birthDate: birth,
        now: DateTime(2026, 10, 22),
      );
      expect(check(null), isNotNull);
      expect(check(DateTime(2010, 1, 1)), isNotNull);
      expect(check(DateTime(2000, 1, 1)), isNull);
      final info = SellerInfo(
        legalName: 'Ivo Ivić',
        oib: '12345678903',
        address: 'Ilica 1',
        iban: 'HR2523400091111111111',
        birthDate: DateTime(2000, 1, 1),
        updatedAt: DateTime(2026),
      );
      // Stari zapis "trgovca" se čita kao fizička osoba (polja se ignoriraju).
      final back = SellerInfo.fromMap({
        ...info.toMap(),
        'type': 'trader',
        'registry': 'OR 1',
      });
      expect(back.legalName, 'Ivo Ivić');
      expect(back.birthDate, DateTime(2000, 1, 1));
      expect(back.toMap().containsKey('type'), isFalse);
      expect(back.maskedIban, 'HR25 •••• 1111');
      expect(back.isBusiness, isFalse);
    });

    test('trgovac (obrt/tvrtka): naziv, kontakt, PDV broj', () {
      String? check({
        String company = 'Retro Kutak j.d.o.o.',
        String vat = '',
        String email = 'info@retrokutak.hr',
        String phone = '+385 91 123 4567',
      }) => SellerInfo.validate(
        kind: SellerKind.business,
        companyName: company,
        legalName: 'Ivo Ivić',
        oib: '12345678903',
        address: 'Ilica 1, Zagreb',
        iban: 'HR2523400091111111111',
        vatId: vat,
        contactEmail: email,
        contactPhone: phone,
      );
      // Trgovcu ne treba datum rođenja.
      expect(check(), isNull);
      expect(check(company: ''), isNotNull);
      expect(check(email: 'nije-mail'), isNotNull);
      expect(check(phone: '12'), isNotNull);
      expect(check(vat: 'HR12345678903'), isNull);
      expect(check(vat: '12345678903'), isNotNull);
      final info = SellerInfo(
        kind: SellerKind.business,
        companyName: 'Retro Kutak j.d.o.o.',
        legalForm: LegalForm.jdoo,
        legalName: 'Ivo Ivić',
        oib: '12345678903',
        address: 'Ilica 1',
        iban: 'HR2523400091111111111',
        vatId: 'HR12345678903',
        contactEmail: 'info@retrokutak.hr',
        contactPhone: '+385 91 123 4567',
        updatedAt: DateTime(2026),
      );
      final back = SellerInfo.fromMap(info.toMap());
      expect(back.isBusiness, isTrue);
      expect(back.tradeName, 'Retro Kutak j.d.o.o.');
      expect(back.legalForm, LegalForm.jdoo);
      expect(back.vatId, 'HR12345678903');
      expect(back.contactEmail, 'info@retrokutak.hr');
    });
  });

  group('platforma', () {
    late StorageService storage;
    late TradeService trade;
    late CommunityService community;

    setUp(() async {
      storage = StorageService();
      await storage.init(inMemory: true);
      trade = TradeService(storage);
      community = CommunityService(storage);
    });
    tearDown(() => Hive.close());

    Future<Device> addItem(double price) => trade.addDevice(
      userId: demo,
      name: 'Lampa',
      model: 'X',
      condition: DeviceCondition.good,
      price: price,
      category: DeviceCategory.values.firstWhere(
        (c) => c.section != ItemSection.digital,
      ),
      quantity: 50,
    );

    test('DAC7: 30+ prodaja ili više od 2.000 € → prijava', () async {
      final d = await addItem(10);
      for (var i = 0; i < 30; i++) {
        await trade.buy(userId: tester, deviceId: d.id);
      }
      final year = DateTime.now().year;
      final sellers = Dac7.sellers(storage.users, storage.transactions, year);
      final mine = sellers.singleWhere((s) => s.user.id == demo);
      expect(mine.sales, 30);
      expect(mine.amount, 300);
      expect(mine.reportable, isTrue);
      final csv = Dac7.csv(sellers, year);
      expect(
        csv.split('\n').first,
        startsWith('godina;korisnik;ime_prezime;oib'),
      );
      expect(csv, contains('12345678903'));
      // Manje od 30 prodaja i ispod 2.000 € — ne prijavljuje se.
      expect(
        Dac7.sellers(storage.users, storage.transactions, year - 1),
        isEmpty,
      );
    });

    test('popust prikazuje najnižu cijenu u zadnjih 30 dana', () async {
      final now = DateTime.now();
      var d = await addItem(100);
      d = await trade.list(userId: demo, deviceId: d.id, price: 80);
      d = await trade.list(userId: demo, deviceId: d.id, price: 120);
      expect(d.basePrice, 120);
      expect(d.lowestPrice30(now.add(const Duration(minutes: 1))), 80);
      // Nakon 31 dan vrijedi samo cijena koja je tada bila na snazi.
      expect(d.lowestPrice30(now.add(const Duration(days: 31))), 120);
      expect(Device.fromMap(d.toMap()).priceLog.length, d.priceLog.length);
    });

    test('ocjena trgovine je "provjerena" samo nakon kupnje', () async {
      final unverified = await community.rateShop(
        raterId: tester,
        sellerId: demo,
        stars: 4,
      );
      expect(unverified.verified, isFalse);
      final d = await addItem(10);
      await trade.buy(userId: tester, deviceId: d.id);
      final verified = await community.rateShop(
        raterId: tester,
        sellerId: demo,
        stars: 5,
      );
      expect(verified.verified, isTrue);
    });

    test('uklanjanje oglasa: obrazloženje vlasniku i žalba', () async {
      final d = await addItem(10);
      await trade.list(userId: demo, deviceId: d.id, price: 10);
      final r = await community.report(
        reporterId: tester,
        targetType: 'device',
        targetId: d.id,
        reason: ReportReason.prohibited,
      );
      await community.notifyRemoval(r.id);
      final n = storage.notifications.singleWhere(
        (n) => n.userId == demo && n.kind == NotificationKind.contentRemoved,
      );
      expect(n.targetId, r.id);
      expect(n.text, contains('Zabranjen predmet'));

      await expectLater(
        community.appeal(userId: demo, reportId: r.id, text: 'kratko'),
        throwsA(isA<TradeException>()),
      );
      final appeal = await community.appeal(
        userId: demo,
        reportId: r.id,
        text: 'Predmet je dopušten, imam račun.',
      );
      expect(appeal.isAppeal, isTrue);
      expect(appeal.targetId, r.id);
      await expectLater(
        community.appeal(
          userId: demo,
          reportId: r.id,
          text: 'Još jednom ista žalba.',
        ),
        throwsA(isA<TradeException>()),
      );
    });
  });
}
