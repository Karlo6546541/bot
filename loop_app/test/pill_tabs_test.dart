import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/widgets/pill_tabs.dart';

void main() {
  testWidgets('PillTabBar mijenja karticu dodirom i čuva ključeve', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Naslov'),
              bottom: const PillTabBar(
                tabs: [
                  Tab(key: ValueKey('t-a'), text: 'Prva'),
                  Tab(key: ValueKey('t-b'), text: 'Druga (2)'),
                  Tab(key: ValueKey('t-c'), text: 'Treća'),
                ],
              ),
            ),
            body: const TabBarView(
              children: [
                Text('sadržaj A'),
                Text('sadržaj B'),
                Text('sadržaj C'),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('sadržaj A'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('t-b')));
    await tester.pumpAndSettle();
    expect(find.text('sadržaj B'), findsOneWidget);
    expect(find.text('Druga (2)'), findsOneWidget);
    await tester.tap(find.text('Treća'));
    await tester.pumpAndSettle();
    expect(find.text('sadržaj C'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PillTabBar se pomiče kad ima mnogo kartica i ne prelijeva', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              bottom: PillTabBar(
                scrollable: true,
                tabs: [
                  for (final n in [
                    'Top',
                    'Objave (12)',
                    'Showovi (3)',
                    'Računi (8)',
                    'Kategorije (20)',
                  ])
                    Tab(text: n),
                ],
              ),
            ),
            body: const SizedBox(),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.text('Kategorije (20)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kategorije (20)'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
