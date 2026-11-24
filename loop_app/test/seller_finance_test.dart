import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/models/app_user.dart';
import 'package:loop_app/models/loop_transaction.dart';
import 'package:loop_app/models/seller_info.dart';
import 'package:loop_app/screens/seller_finance_screens.dart';
import 'package:loop_app/screens/seller_verification_screen.dart';

void main() {
  test('isplata stiže za 2 radna dana (vikend se preskače)', () {
    // Četvrtak → ponedjeljak.
    expect(
      payoutArrival(DateTime(2026, 10, 29, 10)),
      DateTime(2026, 11, 2, 10),
    );
    // Ponedjeljak → srijeda.
    expect(payoutArrival(DateTime(2026, 11, 2, 10)), DateTime(2026, 11, 4, 10));
    LoopTransaction payout(DateTime at) => LoopTransaction(
      id: 'p',
      type: TransactionType.payout,
      userId: 'u',
      deviceId: '',
      deviceName: 'Isplata',
      price: 10,
      fee: 0,
      amount: 10,
      buyerLabel: '',
      sellerLabel: 'u',
      createdAt: at,
    );
    final sent = DateTime(2026, 11, 2, 10);
    expect(payoutInTransit(payout(sent), DateTime(2026, 11, 3)), isTrue);
    expect(payoutInTransit(payout(sent), DateTime(2026, 11, 5)), isFalse);
  });

  test('verifikacija prodavača: koraci iz podataka, zadnji se otključava', () {
    final now = DateTime(2026, 11, 1);
    var user = AppUser(
      id: 'u',
      email: 'u@x.hr',
      name: 'U',
      credits: 0,
      createdAt: now,
    );
    var steps = sellerVerificationSteps(user);
    expect(steps.last.id, 'access');
    expect(steps.last.status, VerificationStatus.locked);
    expect(
      steps.where((s) => s.status == VerificationStatus.complete),
      isEmpty,
    );
    expect(isVerifiedSeller(user), isFalse);

    user = user.copyWith(
      emailVerified: true,
      paymentCard: 'Visa •••• 4242',
      address: 'Ilica 1, Zagreb',
      seller: SellerInfo(
        legalName: 'Ana Anić',
        oib: '12345678903',
        address: 'Ilica 1, Zagreb',
        iban: 'HR2512345671111111111',
        updatedAt: now,
      ),
    );
    steps = sellerVerificationSteps(user);
    expect(steps.every((s) => s.status == VerificationStatus.complete), isTrue);
    expect(isVerifiedSeller(user), isTrue);
  });
}
