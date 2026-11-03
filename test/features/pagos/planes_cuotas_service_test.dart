import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/models/pago_models.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/models/planes_cuotas_models.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/pagos_service.dart';
import 'package:clinica_oftalmologica_mobile/features/pagos/services/planes_cuotas_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

PlanesCuotasService _servicio(MockClient client) => PlanesCuotasService(
  client: client,
  leerToken: () async => 'token-de-prueba',
);

Map<String, dynamic> _resumenJson({int id = 12}) => {
  'id': id,
  'paciente_id': 7,
  'consulta_clinica_id': 9,
  'monto_total': '1200.00',
  'monto_pagado': '400.00',
  'saldo_pendiente': 800,
  'moneda': 'BOB',
  'cantidad_cuotas': 3,
  'cuotas_pagadas': 1,
  'fecha_creacion': '2026-10-01T12:00:00',
  'estado': 'ACTIVO',
  'tiene_cuotas_vencidas': false,
};

Map<String, dynamic> _paginaJson() => {
  'items': [_resumenJson()],
  'total': 1,
  'page': 1,
  'page_size': 50,
  'total_pages': 1,
};

Map<String, dynamic> _planJson() => {
  'id': 12,
  'paciente_id': 7,
  'consulta_clinica_id': 9,
  'monto_total': '1200.00',
  'moneda': 'BOB',
  'cantidad_cuotas': 2,
  'fecha_creacion': '2026-10-01T12:00:00',
  'estado': 'ACTIVO',
  'observaciones': null,
  'creado_por': 2,
  'saldo_pendiente': '800.00',
  'monto_pagado': '400.00',
  'servicios': [
    {
      'servicio_realizado_id': 5,
      'nombre_servicio': 'Consulta General',
      'monto_financiado': '1200.00',
      'activo': true,
    },
  ],
  'cuotas': [
    {
      'id': 2,
      'numero_cuota': 2,
      'monto_programado': '400.00',
      'fecha_vencimiento': '2026-12-31',
      'estado': 'PENDIENTE',
      'pagos': [],
    },
    {
      'id': 1,
      'numero_cuota': 1,
      'monto_programado': '400.00',
      'fecha_vencimiento': '2026-11-30',
      'estado': 'PAGADA',
      'pagos': [],
    },
  ],
};

void main() {
  group('listarMisPlanes', () {
    test('usa page/page_size, envía el JWT y mapea los planes', () async {
      String? auth;
      final client = MockClient((request) async {
        auth = request.headers['Authorization'];
        expect(request.url.path, '/pagos/mis-planes');
        expect(request.url.queryParameters['page'], '1');
        expect(request.url.queryParameters['page_size'], '50');
        expect(request.url.queryParameters.containsKey('estado'), isFalse);
        return _json(_paginaJson(), 200);
      });

      final planes = await _servicio(client).listarMisPlanes();

      expect(auth, 'Bearer token-de-prueba');
      expect(planes, hasLength(1));
      expect(planes.single.id, 12);
      expect(planes.single.saldoPendiente, 800);
      expect(planes.single.estado, EstadoPlanPago.activo);
    });

    test('agrega el filtro de estado cuando se solicita', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['estado'], 'ACTIVO');
        return _json(_paginaJson(), 200);
      });

      final planes = await _servicio(
        client,
      ).listarMisPlanes(estado: 'activo');

      expect(planes, hasLength(1));
    });

    test('mapea una página vacía', () async {
      final client = MockClient(
        (r) async => _json({
          'items': const <Object>[],
          'total': 0,
          'page': 1,
          'page_size': 50,
          'total_pages': 0,
        }, 200),
      );

      expect(await _servicio(client).listarMisPlanes(), isEmpty);
    });

    test('sin token lanza PagosException 401', () async {
      final client = MockClient((r) async => _json(_paginaJson(), 200));
      final servicio = PlanesCuotasService(
        client: client,
        leerToken: () async => null,
      );

      await expectLater(
        servicio.listarMisPlanes(),
        throwsA(
          isA<PagosException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });

    test('propaga el mensaje del backend ante un error 500', () async {
      final client = MockClient(
        (r) async => _json({'detail': 'Error interno del servidor'}, 500),
      );

      await expectLater(
        _servicio(client).listarMisPlanes(),
        throwsA(
          isA<PagosException>()
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', 'Error interno del servidor'),
        ),
      );
    });
  });

  group('consultarMiPlan', () {
    test('usa la ruta del plan y ordena las cuotas', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/pagos/mis-planes/12');
        expect(request.headers['Authorization'], 'Bearer token-de-prueba');
        return _json(_planJson(), 200);
      });

      final plan = await _servicio(client).consultarMiPlan(12);

      expect(plan.id, 12);
      expect(plan.cuotas.map((c) => c.numeroCuota), [1, 2]);
      expect(plan.cuotasPagadas, 1);
      expect(plan.cuotas.first.estado, EstadoCuotaPlan.pagada);
      expect(plan.cuotas.last.esPagableEn(plan.estado), isTrue);
      expect(plan.servicios.single.servicioRealizadoId, 5);
    });

    test('404 devuelve un mensaje claro de plan no encontrado', () async {
      final client = MockClient(
        (r) async => _json({'detail': 'Plan de pago no encontrado'}, 404),
      );

      await expectLater(
        _servicio(client).consultarMiPlan(99),
        throwsA(
          isA<PagosException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Plan de pago no encontrado'),
        ),
      );
    });

    test('respuesta sin JSON válido lanza PagosException', () async {
      final client = MockClient(
        (r) async => http.Response('sin-json', 200, headers: _jsonHeaders),
      );

      await expectLater(
        _servicio(client).consultarMiPlan(12),
        throwsA(isA<PagosException>()),
      );
    });
  });

  group('crearIntencionCuota', () {
    test('hace POST a la ruta real del backend y parsea la intención', () async {
      String? metodo;
      String? cuerpo;
      final client = MockClient((request) async {
        metodo = request.method;
        cuerpo = request.body;
        expect(request.url.path, '/pagos/cuotas/2/stripe/intencion');
        expect(request.headers['Content-Type'], 'application/json');
        return _json({
          'pago_id': 99,
          'cuota_id': 2,
          'plan_pago_id': 12,
          'payment_intent_id': 'pi_123',
          'client_secret': 'pi_123_secret_abc',
          'monto': '400.00',
          'moneda': 'BOB',
          'estado_pago': 'PENDIENTE',
        }, 201);
      });

      final intencion = await _servicio(client).crearIntencionCuota(2);

      expect(metodo, 'POST');
      expect(cuerpo, '{}');
      expect(intencion.pagoId, 99);
      expect(intencion.cuotaId, 2);
      expect(intencion.clientSecret, 'pi_123_secret_abc');
      expect(intencion.monto, 400);
    });

    test('409 expone el detalle del backend sin reintentar', () async {
      var llamadas = 0;
      final client = MockClient((r) async {
        llamadas++;
        return _json({'detail': 'La cuota no esta disponible para cobro'}, 409);
      });

      await expectLater(
        _servicio(client).crearIntencionCuota(2),
        throwsA(
          isA<PagosException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having(
                (e) => e.message,
                'message',
                'La cuota no esta disponible para cobro',
              ),
        ),
      );
      expect(llamadas, 1);
    });
  });

  group('consultarEstadoPago', () {
    test('reutiliza el endpoint de estado de CU31', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/pagos/stripe/pagos/99/estado');
        return _json({
          'pago_id': 99,
          'consulta_clinica_id': 9,
          'estado_pago': 'APROBADO',
          'monto': '400.00',
          'moneda': 'BOB',
          'payment_intent_id': 'pi_123',
        }, 200);
      });

      final estado = await _servicio(client).consultarEstadoPago(99);

      expect(estado.pagoId, 99);
      expect(estado.aprobado, isTrue);
      expect(estado.monto, 400);
      expect(estado.moneda, 'BOB');
    });
  });

  group('listarIntentos', () {
    test('consulta los intentos de la cuota y los mapea', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/pagos/cuotas/2/intentos');
        return _json({
          'cuota_id': 2,
          'estado_cuota': 'PENDIENTE',
          'intentos': [
            {
              'pago_id': 99,
              'metodo_pago': 'TARJETA',
              'estado': 'PENDIENTE',
              'monto': '400.00',
              'fecha_creacion': '2026-11-01T10:00:00',
              'aplicado_a_cuota': false,
            },
          ],
        }, 200);
      });

      final intentos = await _servicio(client).listarIntentos(2);

      expect(intentos.cuotaId, 2);
      expect(intentos.estadoCuota, EstadoCuotaPlan.pendiente);
      expect(intentos.intentos, hasLength(1));
      expect(intentos.intentos.single.estado, EstadoPagoApi.pendiente);
      expect(intentos.intentos.single.aplicadoACuota, isFalse);
    });

    test('404 de una cuota ajena devuelve el detalle del backend', () async {
      final client = MockClient(
        (r) async => _json({'detail': 'Cuota no encontrada'}, 404),
      );

      await expectLater(
        _servicio(client).listarIntentos(8),
        throwsA(
          isA<PagosException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.message, 'message', 'Cuota no encontrada'),
        ),
      );
    });
  });
}
