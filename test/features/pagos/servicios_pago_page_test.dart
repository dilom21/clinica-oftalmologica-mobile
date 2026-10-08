import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/models/pago_models.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/pages/comprobante_pago_page.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/pages/servicios_pago_page.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/pagos_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/stripe_payment_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/widgets/pago_resumen_bar.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

ConsultaPago _consulta() => const ConsultaPago(
  consultaId: 4,
  fechaConsulta: null,
  oftalmologo: 'Carlos Ruiz',
  cantidadServicios: 3,
  cantidadPendientes: 2,
  totalPendiente: 210,
);

List<Map<String, dynamic>> _serviciosJson() => [
  {
    'servicio_realizado_id': 5,
    'servicio_id': 1,
    'nombre_servicio': 'Consulta General Oftalmológica',
    'fecha_realizacion': '2026-09-01T10:30:00',
    'precio_aplicado': '150.00',
    'estado_pago': 'PENDIENTE',
  },
  {
    'servicio_realizado_id': 6,
    'servicio_id': 2,
    'nombre_servicio': 'Medición de Lentes (Refracción)',
    'precio_aplicado': 60.0,
    'estado_pago': 'PENDIENTE',
  },
  {
    'servicio_realizado_id': 3,
    'servicio_id': 3,
    'nombre_servicio': 'Consulta previa pagada',
    'precio_aplicado': 100,
    'estado_pago': 'PAGADO',
  },
];

Map<String, dynamic> _intencionJson() => {
  'pago_id': 99,
  'consulta_clinica_id': 4,
  'payment_intent_id': 'pi_123',
  'client_secret': 'pi_123_secret_abc',
  'monto': 210,
  'moneda': 'BOB',
  'estado_pago': 'PENDIENTE',
};

Map<String, dynamic> _estadoJson(String estado) => {
  'pago_id': 99,
  'consulta_clinica_id': 4,
  'estado_pago': estado,
  'monto': 210,
  'moneda': 'BOB',
  'payment_intent_id': 'pi_123',
};

/// Respuesta PDF simulada del endpoint de comprobante.
http.Response _pdfResponse() => http.Response.bytes(
  utf8.encode('%PDF-1.4 comprobante de pago'),
  200,
  headers: {
    'content-type': 'application/pdf',
    'content-disposition': 'attachment; filename="comprobante_pago_99.pdf"',
  },
);

/// Visor de PDF falso: evita el plugin nativo de `printing` en las pruebas.
Widget _visorFalso(
  BuildContext context,
  Uint8List bytes,
  String nombreArchivo,
) => const SizedBox(key: Key('visor-falso'));

/// Fake de Stripe que evita abrir el SDK nativo en las pruebas.
class _StripeFake extends StripePaymentService {
  _StripeFake(this._resultado) : super(publishableKey: 'pk_test_fake');

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

PagosService _service(Future<http.Response> Function(http.Request) handler) =>
    PagosService(client: MockClient(handler), leerToken: () async => 'token');

Future<void> _pump(
  WidgetTester tester,
  PagosService service,
  StripePaymentService stripe, {
  int maxVerificaciones = 5,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ServiciosPagoPage(
        consulta: _consulta(),
        pagosService: service,
        stripeService: stripe,
        maxVerificaciones: maxVerificaciones,
        esperaVerificacion: Duration.zero,
        visorComprobante: _visorFalso,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _seleccionarTodos(WidgetTester tester) async {
  final boton = find.text('Seleccionar todos');
  await tester.ensureVisible(boton);
  await tester.pumpAndSettle();
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

Future<void> _pagar(WidgetTester tester) async {
  final boton = find.text('Pagar con tarjeta');
  await tester.ensureVisible(boton);
  await tester.pumpAndSettle();
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

/// Encuentra el total mostrado en la barra de resumen (no los precios).
Finder _total(String valor) => find.descendant(
  of: find.byType(PagoResumenBar),
  matching: find.text('Bs $valor'),
);

void main() {
  testWidgets('muestra servicios, deshabilita los pagados y calcula el total', (
    tester,
  ) async {
    final service = _service((request) async {
      if (request.url.path == '/pagos/mis-consultas/4/servicios') {
        return _json(_serviciosJson(), 200);
      }
      return _json({'detail': 'no esperado'}, 500);
    });

    await _pump(
      tester,
      service,
      _StripeFake(const StripePagoResultado(ResultadoPaymentSheet.completado)),
    );

    expect(find.text('Consulta General Oftalmológica'), findsOneWidget);
    expect(find.text('Medición de Lentes (Refracción)'), findsOneWidget);
    expect(find.text('Pagado'), findsOneWidget);
    expect(find.text('Pendiente'), findsNWidgets(2));

    final checkboxes = tester
        .widgetList<Checkbox>(find.byType(Checkbox))
        .toList();
    expect(checkboxes, hasLength(3));
    expect(checkboxes.where((c) => c.onChanged == null), hasLength(1));

    expect(_total('0.00'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Pagar con tarjeta'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    expect(_total('150.00'), findsOneWidget);

    await _seleccionarTodos(tester);
    expect(_total('210.00'), findsOneWidget);
  });

  testWidgets(
    'flujo de pago: intención, Stripe PaymentSheet y confirmación del backend',
    (tester) async {
      final rutas = <String>[];
      Map<String, dynamic>? cuerpoIntencion;
      final service = _service((request) async {
        rutas.add(request.url.path);
        if (request.url.path == '/pagos/mis-consultas/4/servicios') {
          return _json(_serviciosJson(), 200);
        }
        if (request.url.path == '/pagos/stripe/intencion') {
          cuerpoIntencion = jsonDecode(request.body) as Map<String, dynamic>;
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
      await _pump(tester, service, stripe);

      await _seleccionarTodos(tester);
      await _pagar(tester);

      expect(cuerpoIntencion, {
        'servicio_realizado_ids': [5, 6],
      });
      expect(stripe.llamadas, 1);
      expect(stripe.ultimoClientSecret, 'pi_123_secret_abc');
      expect(rutas.contains('/pagos/stripe/pagos/99/estado'), isTrue);
      expect(find.text('Pago aprobado'), findsOneWidget);
    },
  );

  testWidgets('un HTTP 409 no reintenta y no abre el PaymentSheet', (
    tester,
  ) async {
    var postIntenciones = 0;
    final service = _service((request) async {
      if (request.url.path == '/pagos/mis-consultas/4/servicios') {
        return _json(_serviciosJson(), 200);
      }
      if (request.url.path == '/pagos/stripe/intencion') {
        postIntenciones++;
        return _json({
          'detail': 'Existen servicios asociados a otro intento Stripe activo',
        }, 409);
      }
      return _json(_estadoJson('PENDIENTE'), 200);
    });

    final stripe = _StripeFake(
      const StripePagoResultado(ResultadoPaymentSheet.completado),
    );
    await _pump(tester, service, stripe);

    await _seleccionarTodos(tester);
    await _pagar(tester);

    expect(postIntenciones, 1);
    expect(stripe.llamadas, 0);
    expect(find.text('Pago en curso'), findsOneWidget);
  });

  testWidgets('cancelación muestra aviso y ofrece verificar sin aprobar', (
    tester,
  ) async {
    final service = _service((request) async {
      if (request.url.path == '/pagos/mis-consultas/4/servicios') {
        return _json(_serviciosJson(), 200);
      }
      if (request.url.path == '/pagos/stripe/intencion') {
        return _json(_intencionJson(), 201);
      }
      return _json(_estadoJson('PENDIENTE'), 200);
    });

    final stripe = _StripeFake(
      const StripePagoResultado(ResultadoPaymentSheet.cancelado),
    );
    await _pump(tester, service, stripe);

    await _seleccionarTodos(tester);
    await _pagar(tester);

    expect(find.text('Pago cancelado'), findsOneWidget);
    expect(find.text('Pago aprobado'), findsNothing);

    await tester.tap(find.text('Entendido'));
    await tester.pumpAndSettle();

    expect(find.text('Verificar estado'), findsOneWidget);
  });

  testWidgets('si el backend sigue PENDIENTE limita los reintentos', (
    tester,
  ) async {
    var consultasEstado = 0;
    final service = _service((request) async {
      if (request.url.path == '/pagos/mis-consultas/4/servicios') {
        return _json(_serviciosJson(), 200);
      }
      if (request.url.path == '/pagos/stripe/intencion') {
        return _json(_intencionJson(), 201);
      }
      consultasEstado++;
      return _json(_estadoJson('PENDIENTE'), 200);
    });

    final stripe = _StripeFake(
      const StripePagoResultado(ResultadoPaymentSheet.completado),
    );
    await _pump(tester, service, stripe, maxVerificaciones: 3);

    await _seleccionarTodos(tester);
    await _pagar(tester);

    expect(consultasEstado, 3);
    expect(find.text('Pago en verificación'), findsWidgets);
  });

  testWidgets('tras un pago APROBADO ofrece "Ver comprobante" y lo abre', (
    tester,
  ) async {
    final rutas = <String>[];
    final service = _service((request) async {
      rutas.add(request.url.path);
      if (request.url.path == '/pagos/mis-consultas/4/servicios') {
        return _json(_serviciosJson(), 200);
      }
      if (request.url.path == '/pagos/stripe/intencion') {
        return _json(_intencionJson(), 201);
      }
      if (request.url.path == '/pagos/stripe/pagos/99/estado') {
        return _json(_estadoJson('APROBADO'), 200);
      }
      if (request.url.path == '/pagos/mis-pagos/99/comprobante') {
        expect(request.headers['Authorization'], 'Bearer token');
        return _pdfResponse();
      }
      return _json({'detail': 'no esperado'}, 500);
    });

    final stripe = _StripeFake(
      const StripePagoResultado(ResultadoPaymentSheet.completado),
    );
    await _pump(tester, service, stripe);

    await _seleccionarTodos(tester);
    await _pagar(tester);

    // El botón solo aparece tras la confirmación APROBADA del backend.
    expect(find.text('Pago aprobado'), findsOneWidget);
    expect(find.textContaining('Pago realizado correctamente'), findsOneWidget);
    expect(find.text('Ver comprobante'), findsOneWidget);

    await tester.tap(find.text('Ver comprobante'));
    await tester.pumpAndSettle();

    // Se abre la pantalla dedicada y se descarga el PDF autenticado.
    expect(find.byType(ComprobantePagoPage), findsOneWidget);
    expect(find.byKey(const Key('visor-falso')), findsOneWidget);
    expect(rutas.contains('/pagos/mis-pagos/99/comprobante'), isTrue);
  });
}
