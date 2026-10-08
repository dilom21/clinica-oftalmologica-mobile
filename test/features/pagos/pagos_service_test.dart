import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/pagos/services/pagos_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

PagosService _servicio(MockClient client) =>
    PagosService(client: client, leerToken: () async => 'token-de-prueba');

void main() {
  group('listarMisConsultas', () {
    test('envía Authorization Bearer y mapea las consultas', () async {
      String? auth;
      final client = MockClient((request) async {
        auth = request.headers['Authorization'];
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
        ], 200);
      });

      final lista = await _servicio(client).listarMisConsultas();

      expect(auth, 'Bearer token-de-prueba');
      expect(lista, hasLength(1));
      expect(lista.single.consultaId, 4);
      expect(lista.single.totalPendiente, 210.0);
      expect(lista.single.oftalmologo, 'Carlos Ruiz');
    });

    test('mapea una lista vacía', () async {
      final client = MockClient(
        (r) async => http.Response('[]', 200, headers: _jsonHeaders),
      );
      expect(await _servicio(client).listarMisConsultas(), isEmpty);
    });

    test('401 lanza PagosException con statusCode 401', () async {
      final client = MockClient(
        (r) async => _json({
          'detail': 'Tu sesión expiró. Vuelve a iniciar sesión.',
        }, 401),
      );

      await expectLater(
        _servicio(client).listarMisConsultas(),
        throwsA(
          isA<PagosException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('sesión')),
        ),
      );
    });

    test('sin token lanza PagosException 401', () async {
      final client = MockClient((r) async => _json(const <Object>[], 200));
      final service = PagosService(client: client, leerToken: () async => null);

      await expectLater(
        service.listarMisConsultas(),
        throwsA(
          isA<PagosException>().having((e) => e.statusCode, 'statusCode', 401),
        ),
      );
    });
  });

  group('listarServiciosDeConsulta', () {
    test('usa la ruta con consulta_id y mapea los estados', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/pagos/mis-consultas/4/servicios');
        return _json([
          {
            'servicio_realizado_id': 5,
            'servicio_id': 1,
            'nombre_servicio': 'Consulta General',
            'precio_aplicado': '150.00',
            'estado_pago': 'PENDIENTE',
          },
          {
            'servicio_realizado_id': 3,
            'servicio_id': 3,
            'nombre_servicio': 'Pagado',
            'precio_aplicado': 100,
            'estado_pago': 'PAGADO',
          },
        ], 200);
      });

      final servicios = await _servicio(client).listarServiciosDeConsulta(4);

      expect(servicios, hasLength(2));
      expect(servicios.first.estaPendiente, isTrue);
      expect(servicios.last.estaPagado, isTrue);
    });
  });

  group('crearIntencion', () {
    test('POST con servicio_realizado_ids y parsea la intención', () async {
      String? metodo;
      String? body;
      final client = MockClient((request) async {
        metodo = request.method;
        body = request.body;
        expect(request.url.path, '/pagos/stripe/intencion');
        return _json({
          'pago_id': 99,
          'consulta_clinica_id': 4,
          'payment_intent_id': 'pi_123',
          'client_secret': 'pi_123_secret_abc',
          'monto': '210.00',
          'moneda': 'BOB',
          'estado_pago': 'PENDIENTE',
        }, 201);
      });

      final intencion = await _servicio(client).crearIntencion([5, 6]);

      expect(metodo, 'POST');
      expect(jsonDecode(body!), {
        'servicio_realizado_ids': [5, 6],
      });
      expect(intencion.pagoId, 99);
      expect(intencion.clientSecret, 'pi_123_secret_abc');
      expect(intencion.monto, 210.0);
    });

    test('409 lanza PagosException 409 sin reintentar', () async {
      var llamadas = 0;
      final client = MockClient((r) async {
        llamadas++;
        return _json({
          'detail': 'Existen servicios asociados a otro intento Stripe activo',
        }, 409);
      });

      await expectLater(
        _servicio(client).crearIntencion([5]),
        throwsA(
          isA<PagosException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('intento')),
        ),
      );
      expect(llamadas, 1);
    });
  });

  group('consultarEstado', () {
    test('usa la ruta del pago y mapea el estado', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/pagos/stripe/pagos/99/estado');
        return _json({
          'pago_id': 99,
          'consulta_clinica_id': 4,
          'estado_pago': 'APROBADO',
          'monto': '210.00',
          'moneda': 'BOB',
          'payment_intent_id': 'pi_123',
        }, 200);
      });

      final estado = await _servicio(client).consultarEstado(99);

      expect(estado.aprobado, isTrue);
      expect(estado.pagoId, 99);
    });

    test('404 usa el detail del backend', () async {
      final client = MockClient(
        (r) async => _json({'detail': 'Pago Stripe no encontrado'}, 404),
      );

      await expectLater(
        _servicio(client).consultarEstado(1),
        throwsA(
          isA<PagosException>().having(
            (e) => e.message,
            'message',
            'Pago Stripe no encontrado',
          ),
        ),
      );
    });
  });

  group('listarMisPagos', () {
    test('envía Bearer, ordena por fecha desc y mapea los pagos', () async {
      String? auth;
      final client = MockClient((request) async {
        auth = request.headers['Authorization'];
        expect(request.url.path, '/pagos/mis-pagos');
        return _json([
          {
            'pago_id': 1,
            'consulta_clinica_id': 3,
            'fecha_creacion': '2026-10-01T10:00:00',
            'fecha_hora_pago': '2026-10-01T10:05:00',
            'monto': '210.00',
            'moneda': 'BOB',
            'metodo_pago': 'TARJETA',
            'estado_pago': 'APROBADO',
            'pasarela': 'STRIPE',
            'servicios': [
              {
                'servicio_realizado_id': 5,
                'nombre_servicio': 'Consulta General',
                'monto_aplicado': '150.00',
              },
            ],
          },
          {
            'pago_id': 2,
            'consulta_clinica_id': 4,
            'fecha_creacion': '2026-10-02T10:00:00',
            'fecha_hora_pago': null,
            'monto': '60.00',
            'moneda': 'BOB',
            'metodo_pago': 'TARJETA',
            'estado_pago': 'PENDIENTE',
            'pasarela': null,
            'servicios': [],
          },
        ], 200);
      });

      final pagos = await _servicio(client).listarMisPagos();

      expect(auth, 'Bearer token-de-prueba');
      expect(pagos, hasLength(2));
      // El más reciente primero (aunque el backend los envíe desordenados).
      expect(pagos.first.pagoId, 2);
      expect(pagos.last.pagoId, 1);
      expect(pagos.last.monto, 210.0);
      expect(pagos.last.servicios.single.nombreServicio, 'Consulta General');
    });

    test('mapea una lista vacía', () async {
      final client = MockClient(
        (r) async => http.Response('[]', 200, headers: _jsonHeaders),
      );
      expect(await _servicio(client).listarMisPagos(), isEmpty);
    });
  });

  group('descargarComprobante', () {
    test('descarga el PDF autenticado y usa el nombre del backend', () async {
      String? accept;
      String? auth;
      final client = MockClient((request) async {
        accept = request.headers['Accept'];
        auth = request.headers['Authorization'];
        expect(request.url.path, '/pagos/mis-pagos/2/comprobante');
        return http.Response.bytes(
          utf8.encode('%PDF-1.4 contenido'),
          200,
          headers: {
            'content-type': 'application/pdf',
            'content-disposition':
                'attachment; filename="comprobante_pago_2.pdf"',
          },
        );
      });

      final comprobante = await _servicio(client).descargarComprobante(2);

      expect(auth, 'Bearer token-de-prueba');
      expect(accept, 'application/pdf');
      expect(comprobante.esPdf, isTrue);
      expect(comprobante.nombreArchivo, 'comprobante_pago_2.pdf');
      expect(comprobante.contentType, contains('pdf'));
      expect(comprobante.tamanoBytes, greaterThan(4));
    });

    test('detecta un 200 que no es PDF', () async {
      final client = MockClient(
        (r) async => http.Response('no soy un pdf', 200, headers: _jsonHeaders),
      );

      await expectLater(
        _servicio(client).descargarComprobante(2),
        throwsA(
          isA<PagosException>().having(
            (e) => e.message,
            'message',
            contains('PDF'),
          ),
        ),
      );
    });

    test('404 informa que el comprobante no está disponible', () async {
      final client = MockClient(
        (r) async => _json({'detail': 'Comprobante no disponible'}, 404),
      );

      await expectLater(
        _servicio(client).descargarComprobante(9),
        throwsA(
          isA<PagosException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e.message,
                'message',
                'El comprobante no está disponible para este pago.',
              ),
        ),
      );
    });

    test('409 usa el detalle del backend (pago aún no aprobado)', () async {
      final client = MockClient(
        (r) async => _json({
          'detail':
              'El comprobante solo esta disponible para pagos APROBADOS '
              '(estado actual: PENDIENTE)',
        }, 409),
      );

      await expectLater(
        _servicio(client).descargarComprobante(2),
        throwsA(
          isA<PagosException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.message, 'message', contains('APROBADOS')),
        ),
      );
    });

    test('409 sin detalle usa un mensaje por defecto', () async {
      final client = MockClient((r) async => http.Response('', 409));

      await expectLater(
        _servicio(client).descargarComprobante(2),
        throwsA(
          isA<PagosException>().having(
            (e) => e.message,
            'message',
            'El comprobante solo está disponible para pagos aprobados.',
          ),
        ),
      );
    });

    test('error de conexión se informa al paciente', () async {
      final client = MockClient(
        (r) async => throw http.ClientException('sin red'),
      );

      await expectLater(
        _servicio(client).descargarComprobante(2),
        throwsA(
          isA<PagosException>().having(
            (e) => e.message,
            'message',
            contains('No se pudo conectar'),
          ),
        ),
      );
    });
  });
}
