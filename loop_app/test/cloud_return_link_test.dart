import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/services/deep_link.dart';

void main() {
  tearDown(PendingLink.clear);
  test(
    'Stripe return is retained until the home router can open online orders',
    () {
      PendingLink.readFromUrl(
        Uri.parse('https://karlo6546541.github.io/bot/?cloud=orders'),
      );
      expect(PendingLink.cloud, 'orders');
      expect(PendingLink.isPending, isTrue);
      PendingLink.clear();
      expect(PendingLink.cloud, isNull);
      expect(PendingLink.isPending, isFalse);
    },
  );
  test('live room is retained across guest login', () {
    PendingLink.readFromUrl(
      Uri.parse('https://karlo6546541.github.io/bot/?cloud=live&room=room-123'),
    );
    expect(PendingLink.cloud, 'live');
    expect(PendingLink.cloudRoom, 'room-123');
    PendingLink.clear();
    expect(PendingLink.cloudRoom, isNull);
  });
  test('unknown online destinations do not become pending navigation', () {
    PendingLink.readFromUrl(
      Uri.parse('https://karlo6546541.github.io/bot/?cloud=unknown'),
    );
    expect(PendingLink.isPending, isFalse);
  });
}
