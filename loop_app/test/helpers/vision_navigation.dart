import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> mainTab(WidgetTester tester, String label) async {
  final visible = find.text(label).hitTestable();
  if (visible.evaluate().isNotEmpty) {
    await tester.tap(visible.last);
  } else if (label == 'Moje') {
    await tester.tap(find.byKey(const ValueKey('home-accounts')));
  } else if (label == 'Početna') {
    final logo = find.byKey(const ValueKey('logo-home'));
    if (logo.evaluate().isNotEmpty) await tester.tap(logo);
  } else {
    await tester.tap(find.byKey(const ValueKey('home-filters')));
    await tester.pumpAndSettle();
    final item = find.byKey(
      ValueKey(label == 'Profil' ? 'home-profile' : 'home-cat-categories'),
    );
    await tester.ensureVisible(item);
    await tester.tap(item);
  }
  await tester.pumpAndSettle();
}

Future<void> globalSearch(WidgetTester tester) async {
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
