import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/widgets/vision_live_controls.dart';

Widget app(Widget child) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 300, child: child)),
  ),
);
Future<void> slide(WidgetTester tester, {double fraction = 1}) async {
  await tester.drag(
    find.byKey(const ValueKey('vision-slide-thumb')),
    Offset(244 * fraction, 0),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'taps, vertical swipes and unfinished horizontal gestures never submit a bid',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        app(
          VisionBidSlider(
            label: 'Povuci',
            confirmationKey: 10,
            onConfirm: () async {
              calls++;
            },
          ),
        ),
      );
      await tester.tap(find.byType(VisionBidSlider));
      await slide(tester, fraction: .4);
      await tester.pumpAndSettle();
      await tester.drag(
        find.byKey(const ValueKey('vision-slide-thumb')),
        const Offset(0, -140),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      await slide(tester);
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );
  testWidgets('a new price cancels the active gesture before any request', (
    tester,
  ) async {
    var amount = 10, calls = 0;
    late StateSetter update;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return VisionBidSlider(
              label: 'Ponuda $amount',
              confirmationKey: amount,
              onConfirm: () async {
                calls++;
              },
            );
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('vision-slide-thumb'))),
    );
    await gesture.moveBy(const Offset(140, 0));
    await tester.pump();
    update(() => amount = 20);
    await tester.pump();
    await gesture.moveBy(const Offset(150, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(calls, 0);
    await slide(tester);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets('one pending confirmation blocks repeated gestures', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<void>();
    await tester.pumpWidget(
      app(
        VisionBidSlider(
          label: 'Povuci',
          confirmationKey: 10,
          onConfirm: () {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await slide(tester);
    expect(calls, 1);
    await slide(tester);
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('keyboard activation can confirm without a pointer swipe', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        VisionBidSlider(
          label: 'Povuci',
          confirmationKey: 10,
          onConfirm: () async {
            calls++;
          },
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
  testWidgets(
    'up opens shop, down closes it, catalog scroll preserves the room',
    (tester) async {
      final key = GlobalKey<VisionLiveShopOverlayState>();
      final stage = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VisionLiveShopOverlay(
              key: key,
              drawerBuilder: (_, _) => ListView(
                children: [
                  for (var i = 0; i < 25; i++)
                    ListTile(title: Text('Predmet $i')),
                ],
              ),
              child: Column(
                key: stage,
                children: [
                  const Spacer(),
                  VisionShopHandle(
                    key: const ValueKey('open-shop'),
                    label: 'Shop',
                    onOpen: () => key.currentState!.open(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final original = stage.currentContext;
      await tester.drag(
        find.byKey(const ValueKey('open-shop')),
        const Offset(0, -160),
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.isOpen, isTrue);
      await tester.drag(find.text('Predmet 3'), const Offset(0, -140));
      await tester.pumpAndSettle();
      expect(key.currentState!.isOpen, isTrue);
      await tester.drag(
        find.byKey(const ValueKey('live-shop-dismiss')),
        const Offset(0, 160),
      );
      await tester.pumpAndSettle();
      expect(key.currentState!.isOpen, isFalse);
      expect(stage.currentContext, same(original));
      key.currentState!.open();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(key.currentState!.isOpen, isFalse);
      expect(stage.currentContext, same(original));
      expect(tester.takeException(), isNull);
    },
  );
}
