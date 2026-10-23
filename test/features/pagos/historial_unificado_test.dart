import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/authentication_security/pages/login/login_page.dart';
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
    'content-disposition': 'attachment; filename="comprobante_pago.pdf"',
  },
);

/// Canal real de `flutter_secure_storage`.
const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// Sustituye la plataforma de `flutter_secure_storage` por un mapa en memoria.
///
/// El cierre de sesión (401) y el Login usan `TokenStorage`; con este mock no
/// se depende del plugin nativo.
void _mockSecureStorage() {
  final Map<String, String> datos = <String, String>{};

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorageChannel, (call) async {
        switch (call.method) {
          case 'read':
            return datos[call.arguments['key'] as String];
          case 'write':
            datos[call.arguments['key'] as String] =
                call.arguments['value'] as String;
            return null;
          case 'delete':
            datos.remove(call.arguments['key'] as String);
            return null;
          case 'deleteAll':
            datos.clear();
            return null;
          case 'containsKey':
            return datos.containsKey(call.arguments['key'] as String);
          case 'readAll':
            return Map<String, String>.from(datos);
          default:
            return null;
        }
      });
}

/// Pago tal como lo devuelve `GET /pagos/mis-pagos` (contrato real).
Map<String, dynamic> _pago({
  required int id,
  String metodo = 'EFECTIVO',
  String estado = 'APROBADO',
  String? pasarela,
  String monto = '60.00',
  String fecha = '2026-10-07T08:15:00',
  String? fechaPago = '2026-10-07T08:16:00',
  int? consultaId = 4,
  String servicio = 'Consulta General Oftalmológica',
}) => {
  'pago_id': id,
  'consulta_clinica_id': consultaId,
  'fecha_creacion': fecha,
  'fecha_hora_pago': fechaPago,
  'monto': monto,
  'moneda': 'BOB',
  'metodo_pago': metodo,
  'estado_pago': estado,
  'pasarela': pasarela,
  'servicios': [
    {
      'servicio_realizado_id': id * 10,
      'nombre_servicio': servicio,
      'monto_aplicado': monto,
    },
  ],
};

/// Backend simulado del módulo Pagos: registra cada petición de la app.
class _ApiPagos {
  _ApiPagos({List<Map<String, dynamic>>? pagos, this.historialStatus = 200})
    : pagos = pagos ?? <Map<String, dynamic>>[];

  /// Pagos que devolverá `GET /pagos/mis-pagos`.
  List<Map<String, dynamic>> pagos;

  /// Estado HTTP de `GET /pagos/mis-pagos`.
  final int historialStatus;

  /// Respuesta alternativa del historial (red, demoras, etc.).
  Future<http.Response> Function()? historialRespuesta;

  /// Rutas consultadas, en orden.
  final List<String> rutas = <String>[];

  /// Métodos HTTP usados (el refresco solo debe usar GET).
  final List<String> metodos = <String>[];

  int get consultas => rutas.where((r) => r == '/pagos/mis-consultas').length;

  int get historial => rutas.where((r) => r == '/pagos/mis-pagos').length;

  int get comprobantes => rutas.where((r) => r.endsWith('/comprobante')).length;

  bool get creoIntenciones =>
      rutas.any((r) => r.contains('/pagos/stripe/intencion'));

  late final PagosService servicio = PagosService(
    client: MockClient((request) async {
      rutas.add(request.url.path);
      metodos.add(request.method);

      if (request.url.path == '/pagos/mis-consultas') {
        return _json(const <Object>[], 200);
      }

      if (request.url.path == '/pagos/mis-pagos') {
        final Future<http.Response> Function()? alternativa =
            historialRespuesta;
        if (alternativa != null) return alternativa();
        if (historialStatus != 200) {
          return _json({'detail': 'Tu sesión expiró'}, historialStatus);
        }
        return _json(pagos, 200);
      }

      if (request.url.path.endsWith('/comprobante')) return _pdf();

      return _json({'detail': 'ruta no esperada'}, 500);
    }),
    leerToken: () async => 'token-tenant',
  );
}

/// Visor de PDF falso: evita el plugin nativo de `printing` en las pruebas.
Widget _visorFalso(
  BuildContext context,
  Uint8List bytes,
  String nombreArchivo,
) => const SizedBox(key: Key('visor-falso'));

Future<void> _pump(
  WidgetTester tester,
  PagosService service, {
  Future<void> Function()? alCerrarSesion,
}) async {
  // Ventana alta: el historial completo debe caber para leer posiciones.
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  _mockSecureStorage();

  await tester.pumpWidget(
    MaterialApp(
      home: PagosPage(
        pagosService: service,
        stripeService: StripePaymentService(publishableKey: 'pk_test_fake'),
        visor: _visorFalso,
        alCerrarSesion: alCerrarSesion,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _irASeccion(WidgetTester tester, String etiqueta) async {
  await tester.tap(find.text(etiqueta));
  await tester.pumpAndSettle();
}

PagosPageState _estado(WidgetTester tester) =>
    tester.state<PagosPageState>(find.byType(PagosPage));

void main() {
  group('métodos y estados del historial', () {
    testWidgets('pago presencial EFECTIVO aprobado muestra su comprobante', (
      tester,
    ) async {
      final api = _ApiPagos(pagos: [_pago(id: 5, metodo: 'EFECTIVO')]);

      await _pump(tester, api.servicio);
      await _irASeccion(tester, 'Historial');

      expect(find.text('Pago #5'), findsOneWidget);
      expect(find.text('Aprobado'), findsOneWidget);
      expect(find.text('Efectivo'), findsOneWidget);
      expect(find.text('Bs 60.00'), findsOneWidget);
      expect(find.text('Ver detalle y comprobante'), findsOneWidget);
      // Sin pasarela: es un pago registrado en recepción.
      expect(find.textContaining('Pasarela'), findsNothing);

      await tester.tap(find.text('Pago #5'));
      await tester.pumpAndSettle();

      expect(find.text('Servicios pagados'), findsOneWidget);
      expect(find.text('Ver comprobante'), findsOneWidget);
      expect(find.text('Consulta General Oftalmológica'), findsOneWidget);
      expect(api.creoIntenciones, isFalse);
    });

    testWidgets('pago QR pendiente no se presenta como confirmado', (
      tester,
    ) async {
      final api = _ApiPagos(
        pagos: [
          _pago(
            id: 6,
            metodo: 'QR',
            estado: 'PENDIENTE',
            fecha: '2026-10-06T10:00:00',
            fechaPago: null,
          ),
        ],
      );

      await _pump(tester, api.servicio);
      await _irASeccion(tester, 'Historial');

      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('QR'), findsOneWidget);
      expect(find.text('Ver detalle'), findsOneWidget);
      expect(find.text('Aprobado'), findsNothing);
      expect(
        find.text('Ver detalle y comprobante'),
        findsNothing,
        reason: 'un pago pendiente no tiene comprobante disponible',
      );

      await tester.tap(find.text('Pago #6'));
      await tester.pumpAndSettle();

      expect(find.text('Servicios del pago'), findsOneWidget);
      expect(find.text('Servicios pagados'), findsNothing);
      expect(find.text('Ver comprobante'), findsNothing);
      expect(find.textContaining('APROBADO en el servidor'), findsOneWidget);
      // Nunca se pide el comprobante de un pago no aprobado.
      expect(api.comprobantes, 0);
    });

    testWidgets('pago QR aprobado habilita el comprobante', (tester) async {
      final api = _ApiPagos(pagos: [_pago(id: 7, metodo: 'QR')]);

      await _pump(tester, api.servicio);
      await _irASeccion(tester, 'Historial');

      expect(find.text('QR'), findsOneWidget);
      expect(find.text('Aprobado'), findsOneWidget);
      expect(find.text('Ver detalle y comprobante'), findsOneWidget);

      await tester.tap(find.text('Pago #7'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Ver comprobante'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ver comprobante'));
      await tester.pumpAndSettle();

      expect(find.text('Comprobante de pago'), findsOneWidget);
      expect(find.byKey(const Key('visor-falso')), findsOneWidget);
      expect(api.comprobantes, 1);
    });

    testWidgets('transferencia pendiente se muestra como pendiente', (
      tester,
    ) async {
      final api = _ApiPagos(
        pagos: [
          _pago(
            id: 8,
            metodo: 'TRANSFERENCIA',
            estado: 'PENDIENTE',
            fecha: '2026-10-06T11:00:00',
            fechaPago: null,
            monto: '150.00',
          ),
        ],
      );

      await _pump(tester, api.servicio);
      await _irASeccion(tester, 'Historial');

      expect(find.text('Transferencia'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Aprobado'), findsNothing);
      expect(find.text('Ver detalle'), findsOneWidget);
    });

    testWidgets('transferencia aprobada habilita el comprobante', (
      tester,
    ) async {
      final api = _ApiPagos(
        pagos: [
          _pago(
            id: 9,
            metodo: 'TRANSFERENCIA',
            fecha: '2026-10-05T09:00:00',
            monto: '150.00',
          ),
        ],
      );

      await _pump(tester, api.servicio);
      await _irASeccion(tester, 'Historial');

      expect(find.text('Transferencia'), findsOneWidget);
      expect(find.text('Aprobado'), findsOneWidget);
      expect(find.text('Ver detalle y comprobante'), findsOneWidget);
      expect(find.textContaining('Pasarela'), findsNothing);
    });

    testWidgets('pago con tarjeta por Stripe identifica su pasarela', (
      tester,
    ) async {
      final api = _ApiPagos(
        pagos: [
          _pago(id: 4, metodo: 'TARJETA', pasarela: 'STRIPE', monto: '210.00'),
        ],
      );

      await _pump(tester, api.servicio);
      await _irASeccion(tester, 'Historial');

      expect(find.text('Tarjeta'), findsOneWidget);
      // `pasarela` es el único dato del backend que distingue Stripe.
      expect(find.text('Pasarela: Stripe'), findsOneWidget);
      expect(find.text('Aprobado'), findsOneWidget);

      await tester.tap(find.text('Pago #4'));
      await tester.pumpAndSettle();
      expect(find.text('Stripe'), findsOneWidget);
      expect(find.text('Ver comprobante'), findsOneWidget);
    });
  });

  group('historial unificado', () {
    testWidgets('mezcla métodos presenciales y Stripe en orden cronológico', (
      tester,
    ) async {
      final api = _ApiPagos(
        pagos: [
          // El backend los entrega desordenados: la app los ordena.
          _pago(
            id: 3,
            metodo: 'TRANSFERENCIA',
            fecha: '2026-10-05T09:00:00',
            monto: '150.00',
          ),
          _pago(
            id: 2,
            metodo: 'TARJETA',
            pasarela: 'STRIPE',
            fecha: '2026-10-04T09:00:00',
            monto: '210.00',
          ),
          _pago(id: 5, metodo: 'EFECTIVO', fecha: '2026-10-07T08:15:00'),
          _pago(
            id: 4,
            metodo: 'QR',
            estado: 'PENDIENTE',
            fecha: '2026-10-06T12:00:00',
            fechaPago: null,
          ),
        ],
      );

      await _pump(tester, api.servicio);
      await _irASeccion(tester, 'Historial');

      expect(find.text('Efectivo'), findsOneWidget);
      expect(find.text('QR'), findsOneWidget);
      expect(find.text('Transferencia'), findsOneWidget);
      expect(find.text('Tarjeta'), findsOneWidget);
      expect(find.text('Aprobado'), findsNWidgets(3));
      expect(find.text('Pendiente'), findsOneWidget);
      expect(find.text('Ver detalle y comprobante'), findsNWidgets(3));
      expect(find.text('Ver detalle'), findsOneWidget);
      // Solo el pago con tarjeta por Stripe informa pasarela.
      expect(find.text('Pasarela: Stripe'), findsOneWidget);

      double y(String texto) => tester.getTopLeft(find.text(texto)).dy;

      expect(y('Pago #5'), lessThan(y('Pago #4')));
      expect(y('Pago #4'), lessThan(y('Pago #3')));
      expect(y('Pago #3'), lessThan(y('Pago #2')));
      expect(api.creoIntenciones, isFalse);
    });

    testWidgets('rechazado, anulado y reembolsado no ofrecen comprobante', (
      tester,
    ) async {
      final api = _ApiPagos(
        pagos: [
          _pago(
            id: 12,
            metodo: 'TARJETA',
            estado: 'RECHAZADO',
            pasarela: 'STRIPE',
            fecha: '2026-10-03T10:00:00',
            fechaPago: null,
          ),
          _pago(
            id: 11,
            metodo: 'EFECTIVO',
            estado: 'ANULADO',
            fecha: '2026-10-02T10:00:00',
            fechaPago: null,
          ),
          _pago(
            id: 10,
            metodo: 'TRANSFERENCIA',
            estado: 'REEMBOLSADO',
            fecha: '2026-10-01T10:00:00',
          ),
        ],
      );

      await _pump(tester, api.servicio);
      await _irASeccion(tester, 'Historial');

      expect(find.text('Rechazado'), findsOneWidget);
      expect(find.text('Anulado'), findsOneWidget);
      expect(find.text('Reembolsado'), findsOneWidget);
      expect(find.text('Aprobado'), findsNothing);
      expect(find.text('Ver detalle y comprobante'), findsNothing);
      expect(find.text('Ver detalle'), findsNWidgets(3));

      await tester.tap(find.text('Pago #12'));
      await tester.pumpAndSettle();

      expect(find.text('Servicios del pago'), findsOneWidget);
      expect(find.text('Ver comprobante'), findsNothing);
      expect(find.textContaining('fue rechazado'), findsOneWidget);
      expect(api.comprobantes, 0);
    });

    group('actualización del historial', () {
      testWidgets(
        'al volver a la pestaña Pagos se actualiza el historial abierto',
        (tester) async {
          final api = _ApiPagos(pagos: [_pago(id: 4)]);

          await _pump(tester, api.servicio);
          await _irASeccion(tester, 'Historial');

          expect(find.text('Pago #4'), findsOneWidget);
          expect(api.historial, 1);

          // Recepción registra un pago mientras el paciente está en otra pestaña.
          api.pagos = [
            _pago(id: 7, fecha: '2026-10-08T09:30:00'),
            _pago(id: 4),
          ];

          await _estado(tester).alMostrarPestana();
          await tester.pumpAndSettle();

          expect(find.text('Pago #7'), findsOneWidget);
          expect(api.historial, 2);
          // Refresco silencioso: no reemplaza la lista por un indicador de carga.
          expect(find.text('Cargando tu historial de pagos...'), findsNothing);
          expect(api.metodos.toSet(), {'GET'});
        },
      );

      testWidgets('al volver a Historial se actualiza tras un pago nuevo', (
        tester,
      ) async {
        final api = _ApiPagos(pagos: [_pago(id: 4)]);

        await _pump(tester, api.servicio);
        await _irASeccion(tester, 'Historial');
        expect(api.historial, 1);

        await _irASeccion(tester, 'Consultas');

        api.pagos = [_pago(id: 8, fecha: '2026-10-09T09:30:00'), _pago(id: 4)];

        // Vuelve a la pestaña Pagos (sigue en Consultas)…
        await _estado(tester).alMostrarPestana();
        await tester.pumpAndSettle();
        expect(
          api.historial,
          1,
          reason: 'el historial se consulta al abrir su sección',
        );

        // …y abre Historial: se consulta de nuevo y muestra el pago nuevo.
        await _irASeccion(tester, 'Historial');
        expect(find.text('Pago #8'), findsOneWidget);
        expect(api.historial, 2);
        expect(api.creoIntenciones, isFalse);
      });

      testWidgets('no duplica la petición del historial en curso', (
        tester,
      ) async {
        final completer = Completer<void>();
        final api = _ApiPagos();
        api.historialRespuesta = () async {
          await completer.future;
          return _json([_pago(id: 1)], 200);
        };

        await _pump(tester, api.servicio);

        await tester.tap(find.text('Historial'));
        await tester.pump();

        final PagosPageState state = _estado(tester);
        await state.alMostrarPestana();
        await state.alMostrarPestana();

        expect(api.historial, 1);
        expect(api.consultas, 1);

        completer.complete();
        await tester.pumpAndSettle();

        expect(api.historial, 1);
        expect(find.text('Pago #1'), findsOneWidget);
      });

      testWidgets('consultar y refrescar nunca crea una intención Stripe', (
        tester,
      ) async {
        final api = _ApiPagos(
          pagos: [_pago(id: 2, metodo: 'TARJETA', pasarela: 'STRIPE')],
        );

        await _pump(tester, api.servicio);
        await _irASeccion(tester, 'Historial');
        await _estado(tester).alMostrarPestana();
        await tester.pumpAndSettle();
        await _irASeccion(tester, 'Consultas');
        await _estado(tester).alMostrarPestana();
        await tester.pumpAndSettle();

        expect(api.creoIntenciones, isFalse);
        expect(api.metodos.toSet(), {'GET'});
        expect(api.rutas.where((r) => r.contains('stripe')), isEmpty);
      });
    });
  });

  group('seguridad y errores', () {
    testWidgets('401 en el historial limpia la sesión y vuelve al Login', (
      tester,
    ) async {
      var sesionBorrada = false;
      final api = _ApiPagos(pagos: [_pago(id: 1)], historialStatus: 401);

      await _pump(
        tester,
        api.servicio,
        alCerrarSesion: () async {
          sesionBorrada = true;
        },
      );
      expect(sesionBorrada, isFalse);

      // No se usa pumpAndSettle: el Login mantiene un indicador de carga que
      // no se detiene en el entorno de pruebas.
      await tester.tap(find.text('Historial'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(sesionBorrada, isTrue);
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('Pago #1'), findsNothing);
    });

    testWidgets('error de red al consultar el historial permite reintentar', (
      tester,
    ) async {
      var fallo = true;
      final api = _ApiPagos();
      api.historialRespuesta = () async {
        if (fallo) {
          fallo = false;
          throw http.ClientException('sin red');
        }
        return _json([_pago(id: 9)], 200);
      };

      await _pump(tester, api.servicio);
      await _irASeccion(tester, 'Historial');

      expect(find.text('No se pudo cargar tu historial'), findsOneWidget);
      expect(find.textContaining('No se pudo conectar'), findsOneWidget);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(find.text('Pago #9'), findsOneWidget);
      expect(api.historial, 2);
      expect(api.creoIntenciones, isFalse);
    });
  });
}
