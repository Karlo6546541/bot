import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:loop_app/models/live_show.dart';
import 'package:loop_app/providers/app_state.dart';
import 'package:loop_app/screens/show_filters.dart';
import 'package:loop_app/services/storage_service.dart';

void main() {
  testWidgets('filter-sheet: izbornik lijevo, odabir i primjena', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final storage = StorageService();
    await storage.init(inMemory: true);
    final state = AppState.fromStorage(storage);
    ShowFilters? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () async => result = await showShowFilterSheet(
                  ctx,
                  initial: const ShowFilters(),
                  items: const [],
                  state: state,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('filter-section-sort')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('sort-high')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-section-format')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('format-auction')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-section-rating')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('rating-45')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter-apply')));
    await tester.pumpAndSettle();
    expect(result?.sort, ShowSort.viewersHigh);
    expect(result?.formats, {LotMode.auction});
    expect(result?.minRating, 4.5);
    expect(result?.activeCount, 3);
    expect(const ShowFilters().isDefault, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await Hive.close();
  });
}
