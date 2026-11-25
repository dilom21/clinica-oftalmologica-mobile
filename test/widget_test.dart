import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/core/session/auth_gate.dart';
import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/login/login_page.dart';

void main() {
  testWidgets(
    'La aplicacion muestra Login cuando no existe una sesion guardada',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            readToken: () async => null,
            onSessionResolved: (_) {},
          ),
        ),
      );

      // Permitir que AuthGate complete la comprobacion.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
    },
  );

  testWidgets('La aplicacion restaura el portal cuando el JWT es valido', (
    WidgetTester tester,
  ) async {
    bool perfilValidado = false;
    bool? sesionResuelta;

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          readToken: () async => 'jwt-prueba',
          readEmpresaCodigo: () async => 'CLINICA-01',
          validatePatient: () async {
            perfilValidado = true;
          },
          authenticatedBuilder: (_) =>
              const Scaffold(body: Center(child: Text('PORTAL_RESTAURADO'))),
          onSessionResolved: (autenticada) {
            sesionResuelta = autenticada;
          },
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(perfilValidado, isTrue);
    expect(sesionResuelta, isTrue);
    expect(find.text('PORTAL_RESTAURADO'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });
}
