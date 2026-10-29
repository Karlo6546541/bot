import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:loop_app/screens/cloud_commerce_screen.dart';

void main() {
  testWidgets('anonymous online lobby keeps login and navigation usable on narrow screens', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Flutter test HTTP isolation returns 400: unavailable services are expected.
    final client = SupabaseClient('https://test.invalid', 'test-public-key');
    await tester.pumpWidget(MaterialApp(home: CloudCommerceScreen(client: client)));
    expect(find.text('Prijava'), findsOneWidget);
    expect(find.text('Uživo'), findsOneWidget);
    expect(find.text('Katalog'), findsOneWidget);
    expect(find.text('Narudžbe'), findsOneWidget);
    expect(find.text('Plati preko Stripea (test)'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await client.dispose();
    expect(tester.takeException(), isNull);
  });
}
