import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/config/features.dart';
import 'package:loop_app/theme/app_theme.dart';
import 'package:loop_app/widgets/adaptive_shell.dart';
import 'package:loop_app/widgets/wallet_ticket.dart';

void main() {
  Widget shell({double textScale = 1}) => MaterialApp(
    theme: buildLoopTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: AdaptiveShell(
        destinations: const [
          ShellDestination(
            'Pozornica',
            Icons.play_circle_outline,
            Icons.play_circle,
          ),
          ShellDestination('Studio', Icons.sensors, Icons.sensors),
          ShellDestination('Trezor', Icons.wallet_outlined, Icons.wallet),
        ],
        selectedIndex: 0,
        onSelect: (_) {},
        body: ListView.builder(
          itemCount: 60,
          itemBuilder: (_, i) =>
              SizedBox(height: 80, child: Text('Predmet $i')),
        ),
      ),
    ),
  );

  testWidgets('floating destinations stay full while scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell());
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    final width = tester
        .getSize(find.byKey(const ValueKey('floating-dock')))
        .width;
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).bottomNavigationBar,
      isNull,
    );
    // Traka se više ne smanjuje pri skrolanju.
    final gesture = await tester.startGesture(const Offset(180, 400));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('dock-expand')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('floating-dock'))).width,
      width,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  }, skip: !kLiveEnabled);

  testWidgets('island stays usable at 320px with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(shell(textScale: 1.5));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  }, skip: !kLiveEnabled);

  testWidgets(
    'unpaid, refunded and unknown orders never show a paid delivery step',
    (tester) async {
      for (final status in [
        'awaiting_payment',
        'refunded',
        'cancelled',
        'unknown',
      ]) {
        final stage = CinematicTracking.stageForOrder(status);
        expect(stage, -1);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CinematicTracking(stage: stage, animate: false),
            ),
          ),
        );
        expect(
          find.byKey(const ValueKey('tracking-dot-0-active')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('tracking-dot-0-pending')),
          findsOneWidget,
        );
      }
      for (final (status, stage) in [
        ('paid', 0),
        ('shipped', 1),
        ('delivered', 2),
      ]) {
        expect(CinematicTracking.stageForOrder(status), stage);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CinematicTracking(stage: stage, animate: false),
            ),
          ),
        );
        expect(
          find.byKey(ValueKey('tracking-dot-$stage-active')),
          findsOneWidget,
        );
        if (stage < 2) {
          expect(
            find.byKey(ValueKey('tracking-dot-${stage + 1}-pending')),
            findsOneWidget,
          );
        }
      }
    },
  );

  testWidgets(
    'ticket has full-width artwork, compact receipt and accessible actions',
    (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 350,
              child: WalletTicket(
                title: 'Akvarel',
                status: 'Čeka slanje',
                date: DateTime(2026, 11, 3),
                price: '42 €',
                seller: 'Ana',
                onTap: () => opened++,
                footer: const CinematicTracking(stage: 0, animate: false),
              ),
            ),
          ),
        ),
      );
      final picture = find.byKey(const ValueKey('wallet-artwork'));
      expect(tester.getSize(picture).width, 350);
      expect(find.text('42 €'), findsOneWidget);
      expect(find.textContaining('Cijena:'), findsNothing);
      expect(find.textContaining('Kupljeno:'), findsNothing);
      await tester.tap(find.text('Akvarel'));
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('reduced motion disables the tracking pulse', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(body: CinematicTracking(stage: 0)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byKey(const ValueKey('tracking-dot-0-active')), findsOneWidget);
  });
}
