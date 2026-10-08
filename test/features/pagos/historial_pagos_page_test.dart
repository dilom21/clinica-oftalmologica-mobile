import 'dart:convert';
import 'dart:typed_data';

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

http.Response _pdf() => http.Response.bytes(
  utf8.encode('%PDF-1.4 comprobante'),
  200,
  headers: {
    'content-type': 'application/pdf',
    'content-disposition': 'attachment; filename="comprobante_pago_2.pdf"',
  },
);

Map<String, dynamic> _pagoJson({
  required int id,
  int? consultaId = 4,
  String estado = 'APROBADO',
  String fecha = '2026-10-07T08:15:00',
  String? fechaPago = '2026-10-07T08:16:00',
  String monto = '210.00',
}) => {
  'pago_id': id,
  'consulta_clinica_id': consultaId,
  'fecha_creacion': fecha,
  'fecha_hora_pago': fechaPago,
  'monto': monto,
  'moneda': 'BOB',
  'metodo_pago': 'TARJETA',
  'estado_pago': estado,
  'pasarela': 'STRIPE',
  'servicios': [
    {
      'servicio_realizado_id': 5,
      'nombre_servicio': 'Consulta General Oftalmológica',
      'monto_aplicado': '150.00',
    },
    {
      'servicio_realizado_id': 6,
      'nombre_servicio': 'Medición de Lentes',
      'monto_aplicado': '60.00',
    },
  ],
};

/// Visor de PDF falso: evita el plugin nativo de `printing` en las pruebas.
Widget _visorFalso(
  BuildContext context,
  Uint8List bytes,
  String nombreArchivo,
) => const SizedBox(key: Key('visor-falso'));

PagosService _service(Future<http.Response> Function(http.Request) handler) =>
    PagosService(client: MockClient(handler), leerToken: () async => 'token');

Future<void> _pump(WidgetTester tester, PagosService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PagosPage(
        pagosService: service,
        stripeService: StripePaymentService(publishableKey: 'pk_test_fake'),
        visor: _visorFalso,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _abrirHistorial(WidgetTester tester) async {
  await tester.tap(find.text('Historial'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'el historial se consulta al abrir su sección y no crea intenciones',
    (tester) async {
      final rutas = <String>[];
      final service = _service((request) async {
        rutas.add(request.url.path);
        if (request.url.path == '/pagos/mis-consultas') {
          return _json(const <Object>[], 200);
        }
        if (request.url.path == '/pagos/mis-pagos') {
          return _json([_pagoJson(id: 2)], 200);
        }
        return _json({'detail': 'no esperado'}, 500);
      });

      await _pump(tester, service);

      // Abrir la pantalla NO consulta el historial ni crea intenciones.
      expect(rutas, contains('/pagos/mis-consultas'));
      expect(rutas, isNot(contains('/pagos/mis-pagos')));
      expect(rutas, isNot(contains('/pagos/stripe/intencion')));

      await _abrirHistorial(tester);

      expect(rutas, contains('/pagos/mis-pagos'));
      expect(rutas, isNot(contains('/pagos/stripe/intencion')));
      expect(find.text('Pago #2'), findsOneWidget);
      expect(find.text('Bs 210.00'), findsOneWidget);
    },
  );

  testWidgets('historial vacío muestra un mensaje claro', (tester) async {
    final service = _service((request) async => _json(const <Object>[], 200));

    await _pump(tester, service);
    await _abrirHistorial(tester);

    expect(
      find.text('Aún no tienes pagos registrados en tu historial.'),
      findsOneWidget,
    );
  });

  testWidgets('error al cargar el historial permite reintentar', (
    tester,
  ) async {
    var fallo = true;
    final service = _service((request) async {
      if (request.url.path == '/pagos/mis-consultas') {
        return _json(const <Object>[], 200);
      }
      if (fallo) {
        fallo = false;
        return _json({'detail': 'Error interno del servidor'}, 500);
      }
      return _json([_pagoJson(id: 1)], 200);
    });

    await _pump(tester, service);
    await _abrirHistorial(tester);

    expect(find.text('No se pudo cargar tu historial'), findsOneWidget);
    expect(find.text('Error interno del servidor'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Pago #1'), findsOneWidget);
  });

  testWidgets(
    'muestra los estados y habilita el comprobante solo si está aprobado',
    (tester) async {
      final service = _service((request) async {
        if (request.url.path == '/pagos/mis-consultas') {
          return _json(const <Object>[], 200);
        }
        if (request.url.path == '/pagos/mis-pagos') {
          return _json([
            _pagoJson(id: 2, estado: 'APROBADO'),
            _pagoJson(
              id: 1,
              estado: 'PENDIENTE',
              fecha: '2026-10-06T10:00:00',
              fechaPago: null,
            ),
          ], 200);
        }
        if (request.url.path == '/pagos/mis-pagos/2/comprobante') {
          return _pdf();
        }
        return _json({'detail': 'no esperado'}, 500);
      });

      await _pump(tester, service);
      await _abrirHistorial(tester);

      expect(find.text('Aprobado'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Ver detalle y comprobante'), findsOneWidget);
      expect(find.text('Ver detalle'), findsOneWidget);
      // El más reciente primero.
      expect(
        tester.getTopLeft(find.text('Pago #2')).dy,
        lessThan(tester.getTopLeft(find.text('Pago #1')).dy),
      );

      // Detalle del pago APROBADO: habilita el comprobante.
      await tester.tap(find.text('Pago #2'));
      await tester.pumpAndSettle();
      expect(find.text('Servicios pagados'), findsOneWidget);
      expect(find.text('Consulta General Oftalmológica'), findsOneWidget);
      expect(find.text('Ver comprobante'), findsOneWidget);

      // El botón vive al final de un ListView: en el viewport de prueba puede
      // quedar fuera del área visible, así que hay que desplazarlo antes.
      await tester.ensureVisible(find.text('Ver comprobante'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver comprobante'));
      await tester.pumpAndSettle();
      expect(find.text('Comprobante de pago'), findsOneWidget);
      expect(find.byKey(const Key('visor-falso')), findsOneWidget);

      // Regreso: comprobante -> detalle -> historial.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Pago #2'), findsOneWidget);

      // Detalle del pago PENDIENTE: SIN comprobante.
      await tester.ensureVisible(find.text('Pago #1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pago #1'));
      await tester.pumpAndSettle();
      expect(find.text('Ver comprobante'), findsNothing);
      expect(
        find.text(
          'El comprobante estará disponible cuando el pago figure como '
          'APROBADO en el servidor.',
        ),
        findsOneWidget,
      );
    },
  );
}
