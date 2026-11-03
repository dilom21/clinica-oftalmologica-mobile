import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/services/planes_cuotas_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/stripe_payment_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/widgets/mis_planes_seccion.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

PlanesCuotasService _service(
  Future<http.Response> Function(http.Request) handler,
) => PlanesCuotasService(
  client: MockClient(handler),
  leerToken: () async => 'token',
);

Map<String, dynamic> _planResumen({
  int id = 12,
  int cuotasPagadas = 1,
  bool vencidas = false,
  String estado = 'ACTIVO',
}) => {
  'id': id,
  'paciente_id': 7,
  'consulta_clinica_id': 9,
  'monto_total': '1200.00',
  'monto_pagado': '400.00',
  'saldo_pendiente': '800.00',
  'moneda': 'BOB',
  'cantidad_cuotas': 3,
  'cuotas_pagadas': cuotasPagadas,
  'fecha_creacion': '2026-10-01T12:00:00',
  'estado': estado,
  'tiene_cuotas_vencidas': vencidas,
};

Map<String, dynamic> _pagina(List<Map<String, dynamic>> items) => {
  'items': items,
  'total': items.length,
  'page': 1,
  'page_size': 50,
  'total_pages': 1,
};

Map<String, dynamic> _planDetalle() => {
  'id': 12,
  'paciente_id': 7,
  'consulta_clinica_id': 9,
  'monto_total': '1200.00',
  'moneda': 'BOB',
  'cantidad_cuotas': 3,
  'fecha_creacion': '2026-10-01T12:00:00',
  'estado': 'ACTIVO',
  'observaciones': null,
  'creado_por': 2,
  'saldo_pendiente': '800.00',
  'monto_pagado': '400.00',
  'servicios': const [],
  'cuotas': [
    {
      'id': 1,
      'numero_cuota': 1,
      'monto_programado': '400.00',
      'fecha_vencimiento': '2026-10-31',
      'estado': 'PAGADA',
      'pagos': const [],
    },
    {
      'id': 2,
      'numero_cuota': 2,
      'monto_programado': '400.00',
      'fecha_vencimiento': '2026-11-30',
      'estado': 'PENDIENTE',
      'pagos': const [],
    },
    {
      'id': 3,
      'numero_cuota': 3,
      'monto_programado': '400.00',
      'fecha_vencimiento': '2026-12-31',
      'estado': 'PENDIENTE',
      'pagos': const [],
    },
  ],
};

Future<void> _pump(
  WidgetTester tester,
  PlanesCuotasService service,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MisPlanesSeccion(
            planesService: service,
            stripeService: StripePaymentService(publishableKey: 'pk_test_fake'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lista los planes con montos, avance y estado', (tester) async {
    final service = _service((request) async {
      expect(request.url.path, '/pagos/mis-planes');
      return _json(_pagina([_planResumen()]), 200);
    });

    await _pump(tester, service);

    expect(find.text('Mis planes de pago'), findsOneWidget);
    expect(find.text('Plan de pago #12'), findsOneWidget);
    expect(find.text('Activo'), findsOneWidget);
    expect(find.text('Bs 800.00'), findsOneWidget);
    expect(find.text('Bs 1200.00'), findsOneWidget);
    expect(find.text('Bs 400.00'), findsOneWidget);
    expect(find.text('1 de 3 cuotas pagadas'), findsOneWidget);
    expect(find.text('33 %'), findsOneWidget);
    expect(find.text('Ver plan y cuotas'), findsOneWidget);
    expect(find.byKey(const Key('plan-progreso-12')), findsOneWidget);
  });

  testWidgets('muestra el aviso de cuotas vencidas', (tester) async {
    final service = _service(
      (request) async =>
          _json(_pagina([_planResumen(vencidas: true)]), 200),
    );

    await _pump(tester, service);

    expect(find.text('Tienes cuotas vencidas en este plan.'), findsOneWidget);
  });

  testWidgets('lista vacía muestra un mensaje claro', (tester) async {
    final service = _service(
      (request) async => _json(_pagina(const []), 200),
    );

    await _pump(tester, service);

    expect(
      find.text('No tienes planes de pago registrados por el momento.'),
      findsOneWidget,
    );
  });

  testWidgets('error de carga permite reintentar', (tester) async {
    var fallo = true;
    final service = _service((request) async {
      if (fallo) {
        fallo = false;
        return _json({'detail': 'Error interno del servidor'}, 500);
      }
      return _json(_pagina([_planResumen()]), 200);
    });

    await _pump(tester, service);

    expect(find.text('No se pudieron cargar tus planes'), findsOneWidget);
    expect(find.text('Error interno del servidor'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Plan de pago #12'), findsOneWidget);
  });

  testWidgets('al tocar la tarjeta abre el detalle del plan', (tester) async {
    final service = _service((request) async {
      if (request.url.path == '/pagos/mis-planes') {
        return _json(_pagina([_planResumen()]), 200);
      }
      if (request.url.path == '/pagos/mis-planes/12') {
        return _json(_planDetalle(), 200);
      }
      return _json({'detail': 'no esperado'}, 500);
    });

    await _pump(tester, service);

    await tester.tap(find.byKey(const Key('plan-card-12')));
    await tester.pumpAndSettle();

    expect(find.text('Detalle del plan'), findsOneWidget);
    expect(find.text('Mis cuotas'), findsOneWidget);
  });
}
