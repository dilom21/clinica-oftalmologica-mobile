import 'dart:convert';

import 'package:clinica_oftalmologica_mobile/features/valoraciones/models/valoracion_models.dart';
import 'package:clinica_oftalmologica_mobile/features/valoraciones/services/valoracion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ValoracionService (CU40)', () {
    test('lanza 401 si no existe token guardado', () async {
      final service = ValoracionService(
        client: MockClient((_) async => http.Response('{}', 200)),
        leerToken: () async => null,
      );

      await expectLater(
        service.obtenerResumen(),
        throwsA(
          isA<ValoracionException>().having((e) => e.statusCode, 'status', 401),
        ),
      );
    });

    test('obtiene resumen con pendientes y valoraciones existentes', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/seguridad/valoraciones/resumen');
        expect(request.headers['Authorization'], 'Bearer jwt-tenant-vision');

        return http.Response(
          jsonEncode({
            'empresa_codigo': 'VISION-CLARA',
            'empresa_nombre': 'Centro Oftalmológico Visión Clara',
            'escala_minima': 1,
            'escala_maxima': 5,
            'pendientes': [
              {
                'id': 7,
                'consulta_clinica_id': 12,
                'fecha_consulta': '2026-11-22T15:00:00Z',
                'motivo_consulta': 'Molestia en el ojo',
                'tiene_receta': true,
                'oftalmologo': {
                  'id': 1,
                  'nombres': 'Carlos',
                  'apellidos': 'Mendoza',
                  'especialidad': 'Retina',
                  'nombre_completo': 'Carlos Mendoza',
                },
                'motivo_disparo': 'RECETA_EMITIDA',
                'titulo': 'Tu receta está lista — ¡Valora tu atención!',
                'mensaje': 'Califica la atención del Dr. Carlos Mendoza.',
                'leida': false,
                'atendida': false,
                'fecha_creacion': '2026-11-22T15:10:00Z',
                'empresa_codigo': 'VISION-CLARA',
                'empresa_nombre': 'Centro Oftalmológico Visión Clara',
              },
            ],
            'atenciones': [],
            'valoraciones': [],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = ValoracionService(
        client: client,
        leerToken: () async => 'jwt-tenant-vision',
      );

      final resumen = await service.obtenerResumen();
      expect(resumen.empresaCodigo, 'VISION-CLARA');
      expect(resumen.pendientes, hasLength(1));
      expect(resumen.pendientes.first.tieneReceta, isTrue);
      expect(resumen.pendientes.first.oftalmologo.nombreCompleto, 'Carlos Mendoza');
    });

    test('registra nueva valoración y actualiza existente sin duplicar', () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;

        if (request.method == 'POST') {
          expect(payload['consulta_clinica_id'], 12);
          expect(payload['puntuacion'], 5);
          expect(payload['comentario'], 'Muy buena atención');
          return http.Response(
            jsonEncode({
              'id': 99,
              'paciente_id': 100,
              'consulta_clinica_id': 12,
              'oftalmologo_id': 1,
              'puntuacion': 5,
              'etiqueta_puntuacion': 'Excelente',
              'comentario': 'Muy buena atención',
              'fecha_creacion': '2026-11-22T15:20:00Z',
              'fecha_actualizacion': '2026-11-22T15:20:00Z',
              'mensaje': '¡Gracias! Tu valoración fue registrada correctamente.',
            }),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        expect(request.method, 'PUT');
        expect(request.url.path, '/seguridad/valoraciones/99');
        expect(payload['puntuacion'], 4);
        expect(payload['comentario'], isNull);
        return http.Response(
          jsonEncode({
            'id': 99,
            'paciente_id': 100,
            'consulta_clinica_id': 12,
            'oftalmologo_id': 1,
            'puntuacion': 4,
            'etiqueta_puntuacion': 'Buena',
            'comentario': null,
            'fecha_creacion': '2026-11-22T15:20:00Z',
            'fecha_actualizacion': '2026-11-22T15:25:00Z',
            'mensaje': 'Tu valoración fue actualizada correctamente.',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = ValoracionService(
        client: client,
        leerToken: () async => 'jwt-ok',
      );

      final creada = await service.registrarValoracion(
        consultaClinicaId: 12,
        puntuacion: 5,
        comentario: '  Muy buena atención  ',
      );
      expect(creada.id, 99);
      expect(creada.puntuacion, 5);

      final actualizada = await service.actualizarValoracion(
        valoracionId: 99,
        puntuacion: 4,
        comentario: '   ',
      );
      expect(actualizada.id, 99);
      expect(actualizada.puntuacion, 4);
      expect(actualizada.comentario, isNull);
      expect(requests, [
        'POST /seguridad/valoraciones',
        'PUT /seguridad/valoraciones/99',
      ]);
    });
  });
}
