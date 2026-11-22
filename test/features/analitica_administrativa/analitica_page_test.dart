import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:clinica_oftalmologica_mobile/features/analitica_administrativa/pages/analitica_administrativa_page.dart';
import 'package:clinica_oftalmologica_mobile/features/analitica_administrativa/services/analitica_service.dart';

void main() {
  testWidgets('muestra reportes, pronóstico y ML sin curva histórica', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = MockClient((request) async {
      final path = request.url.path;
      Object body;
      if (path.endsWith('/catalogo')) {
        body = <String, dynamic>{
          'version': '2D.1',
          'politica_privacidad': <String, dynamic>{
            'umbral_k': 5,
            'estados': <String>[
              'OK',
              'ZERO',
              'SUPPRESSED',
              'PARTIAL',
              'NOT_COVERED',
            ],
          },
          'indicadores': <Object>[
            <String, dynamic>{
              'key': 'citas_creadas',
              'etiqueta': 'Citas creadas',
              'disponible': true,
              'limitaciones': <String>[],
            },
          ],
        };
      } else if (path.endsWith('/kpis')) {
        body = <String, dynamic>{
          'fecha_desde': '2026-01-01',
          'fecha_hasta': '2026-01-31',
          'zona_horaria': 'America/La_Paz',
          'indicadores': <Object>[
            <String, dynamic>{
              'indicador': 'citas_creadas',
              'etiqueta': 'Citas creadas',
              'valor': null,
              'estado_dato': 'SUPPRESSED',
              'calificador': null,
              'advertencias': <String>[],
            },
          ],
          'distribucion_estados': <Object>[],
          'advertencias': <String>[],
        };
      } else if (path.contains('/series/')) {
        body = <String, dynamic>{
          'indicador': 'citas_creadas',
          'etiqueta': 'Citas creadas',
          'granularidad': 'dia',
          'fecha_desde': '2026-01-01',
          'fecha_hasta': '2026-01-31',
          'zona_horaria': 'America/La_Paz',
          'puntos': <Object>[],
          'advertencias': <String>[],
        };
      } else {
        body = <String, dynamic>{
          'indicador': 'citas_creadas',
          'actual': <String, dynamic>{
            'valor': null,
            'estado_dato': 'SUPPRESSED',
          },
          'anterior': <String, dynamic>{'valor': 0, 'estado_dato': 'ZERO'},
          'variacion_absoluta': null,
          'variacion_porcentual': null,
          'periodo_actual': <String>['2026-01-01', '2026-01-31'],
          'periodo_anterior': <String>['2025-12-01', '2025-12-31'],
          'advertencias': <String>[],
        };
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: AnaliticaAdministrativaPage(
          service: AnaliticaService(
            client: client,
            leerToken: () async => 'admin-jwt',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Citas creadas'), findsWidgets);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('SUPPRESSED'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
