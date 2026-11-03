import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/models/planes_cuotas_models.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/pages/pagar_cuota_page.dart';
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

Map<String, dynamic> _planJson() => {
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

Map<String, dynamic> _intencionJson() => {
  'pago_id': 99,
  'cuota_id': 2,
  'plan_pago_id': 12,
  'payment_intent_id': 'pi_123',
  'client_secret': 'pi_123_secret_abc',
  'monto': '400.00',
  'moneda': 'BOB',
  'estado_pago': 'PENDIENTE',
};

Map<String, dynamic> _estadoJson(String estado) => {
  'pago_id': 99,
  'consulta_clinica_id': 9,
  'estado_pago': estado,
  'monto': '400.00',
  'moneda': 'BOB',
  'payment_intent_id': 'pi_123',
};

/// Fake de Stripe que evita abrir el SDK nativo en las pruebas.
class _StripeFake extends StripePaymentService {
  _StripeFake(this._resultado, {String key = 'pk_test_fake'})
    : super(publishableKey: key);

  final StripePagoResultado _resultado;
  int llamadas = 0;
  String? ultimoClientSecret;

  @override
  Future<void> inicializar() async {}

  @override
  Future<StripePagoResultado> presentar({
    required String clientSecret,
    String merchantDisplayName = 'test',
  }) async {
    llamadas++;
    ultimoClientSecret = clientSecret;
    return _resultado;
  }
}

/// Anfitrión que empuja la pantalla de pago para poder verificar el cierre.
class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.pagina});

  final Widget pagina;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<bool>(builder: (_) => pagina),
            ),
            child: const Text('abrir pago'),
          ),
        ),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required PlanesCuotasService service,
  required StripePaymentService stripe,
  int maxVerificaciones = 5,
}) async {
  final PlanPago plan = PlanPago.fromJson(_planJson());
  final CuotaPlan cuota = plan.cuotas.firstWhere((c) => c.numeroCuota == 2);

  await tester.pumpWidget(
    MaterialApp(
      home: _Anfitrion(
        pagina: PagarCuotaPage(
          plan: plan,
          cuota: cuota,
          planesService: service,
          stripeService: stripe,
          maxVerificaciones: maxVerificaciones,
          esperaVerificacion: const Duration(seconds: 0),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('abrir pago'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('muestra el resumen previo con el importe exacto', (tester) async {
    final service = _service((request) async {
      return _json({'detail': 'no esperado'}, 500);
    });

    await _pump(
      tester,
      service: service,
      stripe: _StripeFake(
        const StripePagoResultado(ResultadoPaymentSheet.cancelado),
      ),
    );

    expect(find.text('Pagar cuota'), findsOneWidget);
    expect(
      find.text('Plan #12 · Cuota 2 de 3'),
      findsOneWidget,
    );
    expect(find.text('Importe a pagar'), findsOneWidget);
    expect(find.text('Bs 400.00'), findsWidgets);
    expect(find.text('Resumen de operación'), findsOneWidget);
    expect(find.text('Plan de pago'), findsOneWidget);
    expect(find.text('#12'), findsOneWidget);
    expect(find.text('Número de cuota'), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);
    expect(find.text('Vencimiento'), findsOneWidget);
    expect(find.text('30/11/2026'), findsOneWidget);
    expect(find.text('Total a pagar'), findsOneWidget);
    expect(find.text('Continuar con Stripe'), findsOneWidget);
  });

  testWidgets('cancelar el PaymentSheet no aprueba el pago', (tester) async {
    final rutas = <String>[];
    final service = _service((request) async {
      rutas.add(request.url.path);
      if (request.url.path == '/pagos/cuotas/2/stripe/intencion') {
        return _json(_intencionJson(), 201);
      }
      return _json(_estadoJson('APROBADO'), 200);
    });
    final stripe = _StripeFake(
      const StripePagoResultado(ResultadoPaymentSheet.cancelado),
    );

    await _pump(tester, service: service, stripe: stripe);

    await tester.tap(find.text('Continuar con Stripe'));
    await tester.pumpAndSettle();

    expect(find.text('Pago cancelado'), findsOneWidget);
    expect(find.text('Pago aprobado'), findsNothing);
    expect(stripe.llamadas, 1);
    expect(stripe.ultimoClientSecret, 'pi_123_secret_abc');
    // No se consulta el estado: no hubo cobro que verificar.
    expect(rutas.contains('/pagos/stripe/pagos/99/estado'), isFalse);
  });

  testWidgets('no reintenta automáticamente cuando el backend responde 409', (
    tester,
  ) async {
    var llamadas = 0;
    final service = _service((request) async {
      llamadas++;
      return _json({'detail': 'La cuota no esta disponible para cobro'}, 409);
    });
    final stripe = _StripeFake(
      const StripePagoResultado(ResultadoPaymentSheet.completado),
    );

    await _pump(tester, service: service, stripe: stripe);

    await tester.tap(find.text('Continuar con Stripe'));
    await tester.pumpAndSettle();

    expect(find.text('Cuota no disponible'), findsOneWidget);
    expect(
      find.text('La cuota no esta disponible para cobro'),
      findsOneWidget,
    );
    expect(llamadas, 1);
    expect(stripe.llamadas, 0);
  });

  testWidgets('solo marca aprobado cuando el backend lo confirma', (
    tester,
  ) async {
    final rutas = <String>[];
    final service = _service((request) async {
      rutas.add(request.url.path);
      if (request.url.path == '/pagos/cuotas/2/stripe/intencion') {
        return _json(_intencionJson(), 201);
      }
      if (request.url.path == '/pagos/stripe/pagos/99/estado') {
        return _json(_estadoJson('APROBADO'), 200);
      }
      return _json({'detail': 'no esperado'}, 500);
    });
    final stripe = _StripeFake(
      const StripePagoResultado(ResultadoPaymentSheet.completado),
    );

    await _pump(tester, service: service, stripe: stripe);

    await tester.tap(find.text('Continuar con Stripe'));
    await tester.pumpAndSettle();

    expect(find.text('Pago aprobado'), findsOneWidget);
    expect(find.textContaining('fue confirmado en el servidor'), findsOneWidget);
    expect(rutas.contains('/pagos/stripe/pagos/99/estado'), isTrue);

    // Al cerrar el aviso se vuelve al detalle del plan.
    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    expect(find.text('Importe a pagar'), findsNothing);
    expect(find.text('abrir pago'), findsOneWidget);
  });

  testWidgets('si el backend sigue PENDIENTE limita las verificaciones', (
    tester,
  ) async {
    var consultasEstado = 0;
    final service = _service((request) async {
      if (request.url.path == '/pagos/cuotas/2/stripe/intencion') {
        return _json(_intencionJson(), 201);
      }
      consultasEstado++;
      return _json(_estadoJson('PENDIENTE'), 200);
    });
    final stripe = _StripeFake(
      const StripePagoResultado(ResultadoPaymentSheet.completado),
    );

    await _pump(
      tester,
      service: service,
      stripe: stripe,
      maxVerificaciones: 3,
    );

    await tester.tap(find.text('Continuar con Stripe'));
    await tester.pumpAndSettle();

    expect(consultasEstado, 3);
    expect(find.text('Pago en verificación'), findsWidgets);
    expect(find.text('Pago aprobado'), findsNothing);
  });

  testWidgets('sin clave publicable no abre Stripe', (tester) async {
    var peticiones = 0;
    final service = _service((request) async {
      peticiones++;
      return _json(_intencionJson(), 201);
    });
    final stripe = _StripeFake(
      const StripePagoResultado(ResultadoPaymentSheet.completado),
      key: '',
    );

    await _pump(tester, service: service, stripe: stripe);

    await tester.tap(find.text('Continuar con Stripe'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Configura la clave publicable de Stripe para pagar con tarjeta.',
      ),
      findsOneWidget,
    );
    expect(stripe.llamadas, 0);
    expect(peticiones, 0);
  });
}
