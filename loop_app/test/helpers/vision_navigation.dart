import 'package:flutter/material.dart';
import 'package:loop_app/config/design_variant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loop_app/l10n/tr.dart';

Future<void> mainTab(WidgetTester tester, String label) async {
  if (kSimpleDesign) {
    final index = switch (label) {
      'Prodavač' || 'Studio' || 'Prodaj' => 2,
      'Moje' || 'Trezor' || 'Kupnje' => 3,
      'Profil' => 4,
      'Istraži' || 'Kategorije' => 1,
      _ => 0,
    };
    Finder target() => find.byKey(ValueKey('simple-nav-$index')).hitTestable();
    for (var i = 0; i < 6; i++) {
      if (target().evaluate().isNotEmpty) break;
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
    await tester.tap(target().first);
    await tester.pumpAndSettle();
    if (label == 'Kategorije') {
      await tester.ensureVisible(
        find.byKey(const ValueKey('explore-tab-categories')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('explore-tab-categories')));
      await tester.pumpAndSettle();
    }
    return;
  }
  final expand = find.byKey(const ValueKey('dock-expand'));
  if (expand.evaluate().isNotEmpty) {
    await tester.tap(expand);
    await tester.pumpAndSettle();
  }
  final destination = switch (label) {
    'Moje' || 'Profil' => 'Trezor',
    'Početna' => 'Pozornica',
    'Prodavač' => 'Studio',
    _ => label,
  };
  Finder target() {
    final item = find
        .ancestor(
          of: find.text(t(destination)),
          matching: find.byType(NavigationDestination),
        )
        .hitTestable();
    return item.evaluate().isNotEmpty
        ? item
        : find.text(t(destination)).hitTestable();
  }

  for (var i = 0; i < 6; i++) {
    final handle = find.byKey(const ValueKey('dock-expand'));
    if (handle.evaluate().isNotEmpty) {
      await tester.tap(handle);
      await tester.pumpAndSettle();
    }
    if (target().evaluate().isNotEmpty) break;
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }
  await tester.tap(target().first);
  await tester.pumpAndSettle();
  if (label == 'Profil') {
    await tester.tap(find.byKey(const ValueKey('vault-account')));
  }
  await tester.pumpAndSettle();
}

Future<void> globalSearch(WidgetTester tester) async {
  if (kSimpleDesign) {
    await tester.tap(find.byKey(const ValueKey('home-search')));
    await tester.pumpAndSettle();
    return;
  }
  await tester.tap(find.byKey(const ValueKey('home-search')));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Pretraži objave i račune').first);
  await tester.pumpAndSettle();
}

Future<void> slideBid(WidgetTester tester, {String key = 'live-bid'}) async {
  final slider = find.byKey(ValueKey(key));
  final thumb = find.descendant(
    of: slider,
    matching: find.byKey(const ValueKey('vision-slide-thumb')),
  );
  final distance = tester.getSize(slider).width - 56;
  await tester.drag(thumb, Offset(distance, 0));
  await tester.pumpAndSettle();
}

Future<void> homeUtilities(WidgetTester tester) async {
  if (find.byKey(const ValueKey('messages-button')).evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('home-search')));
    await tester.pumpAndSettle();
  }
}
