import 'dart:convert';

import 'package:clinica_oftalmologica_mobile/features/valoraciones/pages/valoraciones_page.dart';
import 'package:clinica_oftalmologica_mobile/features/valoraciones/services/valoracion_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  Map<String, dynamic> resumenDemo() => {
    'empresa_codigo': 'VISION-CLARA',
    'empresa_nombre': 'Centro Oftalmológico Visión Clara',
    'escala_minima': 1,
    'escala_maxima': 5,
    'pendientes': [
      {
        'id': 1,
        'consulta_clinica_id': 20,
        'fecha_consulta': '2026-11-22T14:00:00Z',
        'motivo_consulta': 'Molestia en ojo',
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
        'mensaje': 'Se emitió la receta de tu revisión con Dr(a). Carlos Mendoza.',
        'leida': false,
        'atendida': false,
        'fecha_creacion': '2026-11-22T14:15:00Z',
      },
    ],
    'atenciones': [
      {
        'consulta_clinica_id': 20,
        'fecha_consulta': '2026-11-22T14:00:00Z',
        'motivo_consulta': 'Molestia en ojo',
        'tiene_receta': true,
        'oftalmologo': {
          'id': 1,
          'nombres': 'Carlos',
          'apellidos': 'Mendoza',
          'especialidad': 'Retina',
          'nombre_completo': 'Carlos Mendoza',
        },
        'notificacion': {
          'id': 1,
          'consulta_clinica_id': 20,
          'fecha_consulta': '2026-11-22T14:00:00Z',
          'motivo_consulta': 'Molestia en ojo',
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
          'mensaje': 'Se emitió la receta de tu revisión con Dr(a). Carlos Mendoza.',
          'leida': false,
          'atendida': false,
          'fecha_creacion': '2026-11-22T14:15:00Z',
        },
        'valoracion': null,
        'puede_actualizar': false,
      },
      {
        'consulta_clinica_id': 18,
        'fecha_consulta': '2026-11-10T10:00:00Z',
        'motivo_consulta': 'Control anual',
        'tiene_receta': false,
        'oftalmologo': {
          'id': 2,
          'nombres': 'Elena',
          'apellidos': 'Vargas',
          'especialidad': 'Córnea',
          'nombre_completo': 'Elena Vargas',
        },
        'notificacion': null,
        'valoracion': {
          'id': 5,
          'paciente_id': 100,
          'consulta_clinica_id': 18,
          'oftalmologo_id': 2,
          'puntuacion': 5,
          'etiqueta_puntuacion': 'Excelente',
          'comentario': 'Muy atenta y clara',
          'fecha_creacion': '2026-11-10T11:00:00Z',
          'fecha_actualizacion': '2026-11-10T11:00:00Z',
        },
        'puede_actualizar': true,
      },
    ],
    'valoraciones': [],
  };

  group('ValoracionesPage (CU40)', () {
    testWidgets(
      'muestra KPI resumen, pendientes y permite cambiar a Mis valoraciones',
      (tester) async {
        int? pendientesReportados;
        final service = ValoracionService(
          leerToken: () async => 'jwt-valido',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(resumenDemo()),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ValoracionesPage(
              valoracionService: service,
              onPendientesActualizados: (n) => pendientesReportados = n,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(pendientesReportados, 1);
        expect(find.byKey(const Key('tarjeta_resumen_valoraciones')), findsOneWidget);
        expect(find.text('5.0'), findsOneWidget);
        expect(find.text('Dr(a). Carlos Mendoza'), findsOneWidget);
        expect(find.byKey(const Key('btn_valorar_consulta_20')), findsOneWidget);

        // Cambiar a la pestaña Mis valoraciones
        await tester.tap(
          find.byKey(const Key('tab_valoraciones_registradas')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Dr(a). Elena Vargas'), findsOneWidget);
        expect(find.text('“Muy atenta y clara”'), findsOneWidget);
        expect(find.byKey(const Key('btn_actualizar_valoracion_5')), findsOneWidget);
      },
    );

    testWidgets('muestra error con botón Reintentar y recupera datos', (
      tester,
    ) async {
      var llamadas = 0;
      final service = ValoracionService(
        leerToken: () async => 'jwt-valido',
        client: MockClient((_) async {
          llamadas++;
          if (llamadas == 1) {
            return http.Response(
              jsonEncode({'detail': 'Servicio temporalmente no disponible'}),
              503,
            );
          }
          return http.Response(
            jsonEncode({
              'empresa_codigo': 'VISION-CLARA',
              'empresa_nombre': 'Visión Clara',
              'pendientes': [],
              'atenciones': [],
              'valoraciones': [],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      await tester.pumpWidget(
        MaterialApp(home: ValoracionesPage(valoracionService: service)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Servicio temporalmente no disponible'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('btn_reintentar_lista_valoraciones')),
      );
      await tester.pumpAndSettle();

      expect(llamadas, 2);
      expect(
        find.text('¡Estás al día con tus valoraciones!'),
        findsOneWidget,
      );
    });
  });
}
