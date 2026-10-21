import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/services/account_service.dart';
import 'package:loop_app/services/auth_backend.dart';
import 'package:loop_app/services/seed_data.dart';
import 'package:loop_app/services/storage_service.dart';
import 'package:loop_app/services/trade_service.dart';
import 'package:loop_app/services/username_rules.dart';

void main() {
  late StorageService storage;
  late AccountService accounts;

  setUp(() async {
    storage = StorageService();
    await storage.init(inMemory: true);
    accounts = AccountService(storage, LocalAuthBackend(storage));
  });

  tearDown(() async {
    await Hive.close();
  });

  AppUser signedIn(SignInResult r) => (r as SignedIn).user;

  group('pravila korisničkog imena', () {
    test('format', () {
      expect(UsernameRules.validate('karlo_99'), isNull);
      expect(UsernameRules.validate('Ana.Kolekcija'), isNull); // mala slova
      expect(UsernameRules.validate('ab'), isNotNull); // prekratko
      expect(UsernameRules.validate('a' * 21), isNotNull); // predugo
      expect(UsernameRules.validate('9karlo'), isNotNull); // počinje brojem
      expect(UsernameRules.validate('kar lo'), isNotNull); // razmak
      expect(UsernameRules.validate('karlo.'), isNotNull);
      expect(UsernameRules.validate('kar..lo'), isNotNull);
      expect(UsernameRules.validate('šime'), isNotNull); // dijakritici
      expect(UsernameRules.validate('admin'), isNotNull); // rezervirano
      expect(UsernameRules.validate('xfuckx'), isNotNull); // neprimjereno
      expect(UsernameRules.normalize(' @Karlo '), 'karlo');
    });

    test('zauzeto bez obzira na velika slova; prijedlozi su slobodni', () {
      final users = storage.users;
      expect(UsernameRules.isTaken('DEMO', users), isTrue);
      expect(UsernameRules.isTaken('nitko_ovo', users), isFalse);
      final s = UsernameRules.suggestions('demo', users);
      expect(s, isNotEmpty);
      for (final name in s) {
        expect(UsernameRules.validate(name), isNull);
        expect(UsernameRules.isTaken(name, users), isFalse);
      }
    });

    test('osnova iz e-maila i imena', () {
      expect(UsernameRules.baseFrom('Karlo Šimić'), 'karlo.simic');
      expect(UsernameRules.baseFrom('9ab@a.com'), 'loop_aber');
      expect(
        UsernameRules.validate(UsernameRules.firstFree('demo', storage.users)),
        isNull,
      );
      expect(UsernameRules.firstFree('demo', storage.users), isNot('demo'));
      // Neprimjerena osnova ne zaglavi u petlji.
      expect(UsernameRules.firstFree('shit@x.com', storage.users), 'loopuser');
    });
  });

  test('demo računi imaju korisničko ime i lozinku "demo"', () async {
    final user = signedIn(await accounts.login('demo@loop.com', 'demo'));
    expect(user.id, SeedData.demoUserId);
    expect(user.username, 'demo');
    // Prijava korisničkim imenom (lokalno).
    expect(signedIn(await accounts.login('@Demo', 'demo')).id, user.id);
    await expectLater(
      accounts.login('demo@loop.com', 'kriva'),
      throwsA(isA<TradeException>()),
    );
  });

  test('registracija: jedinstveno ime, lozinka, ponovna prijava', () async {
    final user = signedIn(
      await accounts.register(
        email: 'Karlo@Loop.com',
        password: 'tajna123',
        username: 'Karlo_99',
      ),
    );
    expect(user.username, 'karlo_99');
    expect(user.email, 'karlo@loop.com');
    expect(user.credits, TradeService.welcomeCredits);
    expect(user.emailVerified, isFalse);

    // Isti e-mail ili isto ime (drugačija slova) ne prolaze.
    await expectLater(
      accounts.register(
        email: 'karlo@loop.com',
        password: 'tajna123',
        username: 'drugi',
      ),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      accounts.register(
        email: 'drugi@loop.com',
        password: 'tajna123',
        username: 'KARLO_99',
      ),
      throwsA(
        isA<UsernameTakenException>().having(
          (e) => e.suggestions,
          'prijedlozi',
          isNotEmpty,
        ),
      ),
    );
    // Prekratka lozinka i loš e-mail.
    await expectLater(
      accounts.register(email: 'x@y.hr', password: '123', username: 'xyz'),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      accounts.register(
        email: 'nije-mail',
        password: '123456',
        username: 'xyz',
      ),
      throwsA(isA<TradeException>()),
    );

    expect(
      signedIn(await accounts.login('karlo@loop.com', 'tajna123')).id,
      user.id,
    );
    await expectLater(
      accounts.login('karlo@loop.com', 'kriva'),
      throwsA(isA<TradeException>()),
    );
    await expectLater(
      accounts.login('nema@loop.com', 'tajna123'),
      throwsA(isA<TradeException>()),
    );
  });

  test('lozinka nije u javnom profilu', () async {
    final user = signedIn(
      await accounts.register(
        email: 'a@b.hr',
        password: 'tajna123',
        username: 'abc',
      ),
    );
    final map = storage.userById(user.id)!.toMap().toString();
    expect(map.contains('tajna123'), isFalse);
    expect(storage.exportAll().toString().contains('hash'), isFalse);
  });

  test('kod za poziv: oboje dobivaju bonus', () async {
    final before = storage.userById(SeedData.testUserId)!.credits;
    final user = signedIn(
      await accounts.register(
        email: 'novi@loop.com',
        password: 'tajna123',
        username: 'novi',
        referral: '@test',
      ),
    );
    expect(
      user.credits,
      TradeService.welcomeCredits + AccountService.referralBonus,
    );
    expect(user.referredBy, SeedData.testUserId);
    expect(
      storage.userById(SeedData.testUserId)!.credits,
      before + AccountService.referralBonus,
    );
    await expectLater(
      accounts.register(
        email: 'treci@loop.com',
        password: 'tajna123',
        username: 'treci',
        referral: 'ne_postoji',
      ),
      throwsA(isA<TradeException>()),
    );
  });

  test('promjena imena: jednom u 30 dana, staro ostaje zaključano', () async {
    final now = DateTime(2026, 10, 1);
    final u = await accounts.changeUsername(
      SeedData.testUserId,
      'tester',
      now: now,
    );
    expect(u.username, 'tester');
    expect(u.formerUsername, 'test');
    // Staro ime je zaključano za druge.
    expect(UsernameRules.isTaken('test', storage.users, now: now), isTrue);
    expect(
      UsernameRules.isTaken(
        'test',
        storage.users,
        now: now.add(const Duration(days: 31)),
      ),
      isFalse,
    );
    await expectLater(
      accounts.changeUsername(
        SeedData.testUserId,
        'tester2',
        now: now.add(const Duration(days: 5)),
      ),
      throwsA(isA<TradeException>()),
    );
    final later = await accounts.changeUsername(
      SeedData.testUserId,
      'tester2',
      now: now.add(const Duration(days: 31)),
    );
    expect(later.username, 'tester2');
  });

  test('profil: opis najviše 160 znakova, lozinka se mijenja', () async {
    await expectLater(
      accounts.updateProfile(
        SeedData.demoUserId,
        name: 'Demo',
        bio: 'x' * 161,
        city: 'Zagreb',
      ),
      throwsA(isA<TradeException>()),
    );
    final u = await accounts.updateProfile(
      SeedData.demoUserId,
      name: 'Demo',
      bio: 'Skupljam ploče',
      city: 'Zagreb',
    );
    expect(u.city, 'Zagreb');

    await expectLater(
      accounts.changePassword(
        email: 'demo@loop.com',
        oldPassword: 'kriva',
        newPassword: 'novaLozinka',
      ),
      throwsA(isA<TradeException>()),
    );
    await accounts.changePassword(
      email: 'demo@loop.com',
      oldPassword: 'demo',
      newPassword: 'novaLozinka',
    );
    await expectLater(
      accounts.login('demo@loop.com', 'demo'),
      throwsA(isA<TradeException>()),
    );
    expect(
      signedIn(await accounts.login('demo@loop.com', 'novaLozinka')).id,
      SeedData.demoUserId,
    );
    // Lokalni "zaboravljena lozinka".
    await accounts.resetPasswordLocally('demo@loop.com', 'trecaLozinka');
    expect(
      signedIn(await accounts.login('demo@loop.com', 'trecaLozinka')).id,
      SeedData.demoUserId,
    );
  });

  test('prijava koja treba korisničko ime (npr. Google)', () async {
    const identity = AuthIdentity(
      uid: 'google-1',
      email: 'g@gmail.com',
      provider: 'google',
      verified: true,
      name: 'Gordana',
    );
    final r = await accounts.completeSignIn(identity);
    expect(r, isA<NeedsUsername>());
    expect(accounts.pendingIdentity?.uid, 'google-1');
    final user = await accounts.createProfile(identity, 'gordana');
    expect(user.emailVerified, isTrue);
    expect(user.authProvider, 'google');
    expect(user.name, 'Gordana');
    expect(accounts.pendingIdentity, isNull);
    // Ponovna prijava pronalazi profil.
    expect(signedIn(await accounts.completeSignIn(identity)).id, 'google-1');
  });

  test('stari računi bez korisničkog imena dobivaju slobodno ime', () async {
    await storage.putUser(
      AppUser(
        id: 'old',
        email: 'demo2@loop.com',
        name: 'Stari',
        credits: 10,
        createdAt: DateTime(2025),
      ),
    );
    await storage.ensureAccounts();
    final old = storage.userById('old')!;
    expect(UsernameRules.validate(old.username), isNull);
    expect(old.username, 'demo2');
  });
}
