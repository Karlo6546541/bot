import 'seed_data.dart';

/// Testni (demo) računi iz početnih podataka. Njihove objave, lajvove i
/// ocjene nisu stvarni društveni dokaz pa se u sučelju jasno označavaju.
bool isDemoAccount(String? userId) =>
    userId != null &&
    const {
      SeedData.demoUserId,
      SeedData.testUserId,
      SeedData.anaUserId,
      SeedData.markoUserId,
    }.contains(userId);
