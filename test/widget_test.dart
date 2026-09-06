import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/main.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/login/login_page.dart';

void main() {
  testWidgets('La app arranca mostrando la pantalla de inicio de sesión', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(LoginPage), findsOneWidget);

    // No se conserva el smoke test del contador de Flutter.
    expect(find.text('0'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
