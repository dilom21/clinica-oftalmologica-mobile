import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/pages/pagos_page.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/pagos_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/stripe_payment_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

PagosService _service(Future<http.Response> Function(http.Request) handler) =>
    PagosService(client: MockClient(handler), leerToken: () async => 'token');

Future<void> _pump(WidgetTester tester, PagosService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PagosPage(
        pagosService: service,
        // Con clave fake el aviso de configuración no se muestra.
        stripeService: StripePaymentService(publishableKey: 'pk_test_fake'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista las consultas con su resumen de pago', (tester) async {
    final service = _service((request) async {
      expect(request.url.path, '/pagos/mis-consultas');
      return _json([
        {
          'consulta_id': 4,
          'fecha_consulta': '2026-09-01T10:30:00',
          'oftalmologo': {'id': 2, 'nombres': 'Carlos', 'apellidos': 'Ruiz'},
          'cantidad_servicios': 2,
          'cantidad_pendientes': 2,
          'total_pendiente': '210.00',
        },
        {
          'consulta_id': 3,
          'fecha_consulta': '2026-08-01T09:00:00',
          'oftalmologo': null,
          'cantidad_servicios': 2,
          'cantidad_pendientes': 0,
          'total_pendiente': 0,
        },
      ], 200);
    });

    await _pump(tester, service);

    expect(find.text('Pagos'), findsOneWidget);
    expect(find.text('Consulta del 01/09/2026'), findsOneWidget);
    expect(find.text('Consulta del 01/08/2026'), findsOneWidget);
    expect(find.text('Carlos Ruiz'), findsOneWidget);
    expect(find.text('Bs 210.00'), findsOneWidget);
    expect(find.text('Pago pendiente'), findsOneWidget);
    expect(find.text('Al día'), findsOneWidget);
  });

  testWidgets('lista vacía muestra un mensaje claro', (tester) async {
    final service = _service((request) async => _json(const <Object>[], 200));

    await _pump(tester, service);

    expect(
      find.text('No tienes consultas con información de pago por el momento.'),
      findsOneWidget,
    );
  });

  testWidgets('error de conexión permite reintentar', (tester) async {
    var fallo = true;
    final service = _service((request) async {
      if (fallo) {
        fallo = false;
        return _json({'detail': 'Error interno del servidor'}, 500);
      }
      return _json([
        {
          'consulta_id': 4,
          'fecha_consulta': '2026-09-01T10:30:00',
          'cantidad_servicios': 2,
          'cantidad_pendientes': 2,
          'total_pendiente': '210.00',
        },
      ], 200);
    });

    await _pump(tester, service);

    expect(find.text('No se pudieron cargar tus pagos'), findsOneWidget);
    expect(find.text('Error interno del servidor'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Consulta del 01/09/2026'), findsOneWidget);
  });
}
