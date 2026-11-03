import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/pages/plan_detalle_page.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/planes_cuotas_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/stripe_payment_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

PlanesCuotasService _service(
  Future<http.Response> Function(http.Request) handler,
) => PlanesCuotasService(
  client: MockClient(handler),
  leerToken: () async => 'token',
);

Map<String, dynamic> _planJson({String estado = 'ACTIVO'}) => {
  'id': 12,
  'paciente_id': 7,
  'consulta_clinica_id': 9,
  'monto_total': '1200.00',
  'moneda': 'BOB',
  'cantidad_cuotas': 3,
  'fecha_creacion': '2026-10-01T12:00:00',
  'estado': estado,
  'observaciones': null,
  'creado_por': 2,
  'saldo_pendiente': '800.00',
  'monto_pagado': '400.00',
  'servicios': [
    {
      'servicio_realizado_id': 5,
      'nombre_servicio': 'Consulta General Oftalmológica',
      'monto_financiado': '1200.00',
      'activo': true,
    },
  ],
  'cuotas': [
    {
      'id': 1,
      'numero_cuota': 1,
      'monto_programado': '400.00',
      'fecha_vencimiento': '2026-10-31',
      'estado': 'PAGADA',
      'pagos': [
        {
          'pago_id': 90,
          'metodo_pago': 'TARJETA',
          'estado': 'APROBADO',
          'monto': '400.00',
          'fecha_creacion': '2026-10-31T18:00:00',
          'aplicado_a_cuota': true,
        },
      ],
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
      'estado': 'VENCIDA',
      'pagos': const [],
    },
  ],
};

Future<void> _pump(WidgetTester tester, PlanesCuotasService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PlanDetallePage(
        planId: 12,
        planesService: service,
        stripeService: StripePaymentService(publishableKey: 'pk_test_fake'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra el resumen del financiamiento y las cuotas', (
    tester,
  ) async {
    final service = _service((request) async {
      expect(request.url.path, '/pagos/mis-planes/12');
      return _json(_planJson(), 200);
    });

    await _pump(tester, service);

    expect(find.text('Detalle del plan'), findsOneWidget);
    expect(find.text('Plan de pago #12'), findsOneWidget);
    expect(find.text('Resumen del financiamiento'), findsOneWidget);
    expect(find.text('Total del plan'), findsOneWidget);
    expect(find.text('Saldo pendiente'), findsOneWidget);
    expect(
      find.text('Consulta clínica #9 · 3 cuotas programadas'),
      findsOneWidget,
    );
    expect(find.text('1 de 3 cuotas pagadas'), findsOneWidget);

    expect(find.text('Cuota 1'), findsOneWidget);
    expect(find.text('Cuota 2'), findsOneWidget);
    expect(find.text('Cuota 3'), findsOneWidget);
    expect(find.text('Pagada'), findsOneWidget);
    expect(find.text('Pendiente'), findsOneWidget);
    expect(find.text('Vencida'), findsOneWidget);
  });

  testWidgets('solo ofrece pagar cuotas cobrables', (tester) async {
    final service = _service((request) async => _json(_planJson(), 200));

    await _pump(tester, service);

    expect(find.byKey(const Key('pagar-cuota-1')), findsNothing);
    expect(find.byKey(const Key('pagar-cuota-2')), findsOneWidget);
    expect(find.byKey(const Key('pagar-cuota-3')), findsOneWidget);
  });

  testWidgets('muestra los servicios incluidos que devuelve el backend', (
    tester,
  ) async {
    final service = _service((request) async => _json(_planJson(), 200));

    await _pump(tester, service);

    expect(find.text('Servicios incluidos'), findsOneWidget);
    expect(find.text('Consulta General Oftalmológica'), findsOneWidget);
  });

  testWidgets('un plan cancelado no permite pagar cuotas', (tester) async {
    final service = _service(
      (request) async => _json(_planJson(estado: 'CANCELADO'), 200),
    );

    await _pump(tester, service);

    expect(
      find.text('Este plan no admite nuevos pagos de cuotas.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pagar-cuota-2')), findsNothing);
  });

  testWidgets('error del backend permite reintentar', (tester) async {
    var fallo = true;
    final service = _service((request) async {
      if (fallo) {
        fallo = false;
        return _json({'detail': 'Plan de pago no encontrado'}, 404);
      }
      return _json(_planJson(), 200);
    });

    await _pump(tester, service);

    expect(find.text('No se pudo cargar el plan'), findsOneWidget);
    expect(find.text('Plan de pago no encontrado'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Resumen del financiamiento'), findsOneWidget);
  });

  testWidgets('consulta los intentos de la cuota en el backend', (
    tester,
  ) async {
    final rutas = <String>[];
    final service = _service((request) async {
      rutas.add(request.url.path);
      if (request.url.path == '/pagos/cuotas/1/intentos') {
        return _json({
          'cuota_id': 1,
          'estado_cuota': 'PAGADA',
          'intentos': [
            {
              'pago_id': 90,
              'metodo_pago': 'TARJETA',
              'estado': 'APROBADO',
              'monto': '400.00',
              'fecha_creacion': '2026-10-31T18:00:00',
              'aplicado_a_cuota': true,
            },
          ],
        }, 200);
      }
      return _json(_planJson(), 200);
    });

    await _pump(tester, service);

    final boton = find.byKey(const Key('ver-intentos-1'));
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(find.text('Intentos de la cuota 1'), findsOneWidget);
    expect(find.text('Tarjeta'), findsWidgets);
    expect(rutas.contains('/pagos/cuotas/1/intentos'), isTrue);
  });

  testWidgets('al pagar una cuota abre el resumen de pago', (tester) async {
    final service = _service((request) async => _json(_planJson(), 200));

    await _pump(tester, service);

    final boton = find.byKey(const Key('pagar-cuota-2'));
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(find.text('Importe a pagar'), findsOneWidget);
    expect(find.text('Continuar con Stripe'), findsOneWidget);
  });
}
