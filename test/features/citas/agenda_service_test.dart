import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/citas/services/agenda_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

Map<String, dynamic> _oftalmologoJson(int id) {
  return {
    'id': id,
    'matricula': 'MAT-$id',
    'nombres': 'Carlos',
    'apellidos': 'Ruiz',
    'especialidad': 'Retina',
  };
}

void main() {
  AgendaService crearServicio(MockClient client) {
    return AgendaService(
      client: client,
      leerToken: () async => 'token-de-prueba',
    );
  }

  group('AgendaService.listarOftalmologos', () {
    test(
      'envía Authorization Bearer con el JWT leído de TokenStorage',
      () async {
        String? autorizacion;
        String? accept;
        final client = MockClient((request) async {
          autorizacion = request.headers['Authorization'];
          accept = request.headers['Accept'];
          return http.Response(
            jsonEncode([_oftalmologoJson(1)]),
            200,
            headers: _jsonHeaders,
          );
        });

        final lista = await crearServicio(client).listarOftalmologos();

        expect(autorizacion, 'Bearer token-de-prueba');
        expect(accept, 'application/json');
        expect(lista, hasLength(1));
        expect(lista.single.nombreCompleto, 'Carlos Ruiz');
      },
    );

    test('mapea una lista vacía como lista sin elementos', () async {
      final client = MockClient((request) async {
        return http.Response('[]', 200, headers: _jsonHeaders);
      });

      final lista = await crearServicio(client).listarOftalmologos();

      expect(lista, isEmpty);
    });

    test(
      'una respuesta 401 lanza AgendaException con statusCode 401',
      () async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'detail': 'Tu sesión expiró. Vuelve a iniciar sesión.',
            }),
            401,
            headers: _jsonHeaders,
          );
        });

        await expectLater(
          crearServicio(client).listarOftalmologos(),
          throwsA(
            isA<AgendaException>()
                .having((e) => e.statusCode, 'statusCode', 401)
                .having((e) => e.message, 'message', contains('sesión')),
          ),
        );
      },
    );

    test('sin token disponible lanza AgendaException 401', () async {
      final client = MockClient((request) async {
        return http.Response('[]', 200, headers: _jsonHeaders);
      });
      final service = AgendaService(
        client: client,
        leerToken: () async => null,
      );

      await expectLater(
        service.listarOftalmologos(),
        throwsA(
          isA<AgendaException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    });
  });

  group('AgendaService.obtenerDisponibilidad', () {
    test(
      'construye los query params oftalmologo_id y fecha (YYYY-MM-DD)',
      () async {
        String? oftalmologoId;
        String? fecha;
        final client = MockClient((request) async {
          expect(request.url.path, '/agenda-citas/disponibilidad');
          oftalmologoId = request.url.queryParameters['oftalmologo_id'];
          fecha = request.url.queryParameters['fecha'];
          return http.Response(
            jsonEncode({
              'oftalmologo': _oftalmologoJson(7),
              'fecha': '2026-09-06',
              'tiene_horario': true,
              'horarios_base': [
                {'hora_inicio': '08:00:00', 'hora_fin': '17:00:00'},
              ],
              'intervalos_disponibles': [
                {'hora_inicio': '08:00:00', 'hora_fin': '08:30:00'},
              ],
            }),
            200,
            headers: _jsonHeaders,
          );
        });

        final resultado = await crearServicio(
          client,
        ).obtenerDisponibilidad(oftalmologoId: 7, fecha: DateTime(2026, 9, 6));

        expect(oftalmologoId, '7');
        expect(fecha, '2026-09-06');
        expect(resultado.oftalmologo.id, 7);
        expect(resultado.fecha, DateTime(2026, 9, 6));
        expect(resultado.intervalosDisponibles, hasLength(1));
      },
    );

    test('prefiere el detail de FastAPI en errores 404', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Oftalmólogo no encontrado o inactivo'}),
          404,
          headers: _jsonHeaders,
        );
      });

      await expectLater(
        crearServicio(client).obtenerDisponibilidad(
          oftalmologoId: 999,
          fecha: DateTime(2026, 9, 6),
        ),
        throwsA(
          isA<AgendaException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having(
                (e) => e.message,
                'message',
                'Oftalmólogo no encontrado o inactivo',
              ),
        ),
      );
    });

    test('los errores de validación 422 usan el msg de cada detalle', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'detail': [
              {
                'type': 'date_from_datetime_parsing',
                'loc': ['query', 'fecha'],
                'msg': 'Value error, fecha no válida',
              },
            ],
          }),
          422,
          headers: _jsonHeaders,
        );
      });

      await expectLater(
        crearServicio(
          client,
        ).obtenerDisponibilidad(oftalmologoId: 7, fecha: DateTime(2026, 9, 6)),
        throwsA(
          isA<AgendaException>().having(
            (e) => e.message,
            'message',
            'fecha no válida',
          ),
        ),
      );
    });
  });
}
