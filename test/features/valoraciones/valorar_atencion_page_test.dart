import 'dart:convert';

import 'package:clinica_oftalmologica_mobile/features/valoraciones/models/valoracion_models.dart';
import 'package:clinica_oftalmologica_mobile/features/valoraciones/pages/valorar_atencion_page.dart';
import 'package:clinica_oftalmologica_mobile/features/valoraciones/services/valoracion_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const oftalmologo = OftalmologoValoracion(
    id: 1,
    nombres: 'Carlos',
    apellidos: 'Mendoza',
    especialidad: 'Oftalmología General',
    nombreCompleto: 'Carlos Mendoza',
  );

  group('ValorarAtencionPage (CU40)', () {
    testWidgets(
      'valida puntuación obligatoria, solicita confirmación y permite reintentar tras error',
      (tester) async {
        var intentos = 0;
        final service = ValoracionService(
          leerToken: () async => 'jwt-valido',
          client: MockClient((request) async {
            intentos++;
            if (intentos == 1) {
              return http.Response(
                jsonEncode({'detail': 'Error temporal del servidor'}),
                500,
              );
            }
            return http.Response(
              jsonEncode({
                'id': 42,
                'paciente_id': 100,
                'consulta_clinica_id': 10,
                'oftalmologo_id': 1,
                'puntuacion': 5,
                'etiqueta_puntuacion': 'Excelente',
                'comentario': 'Muy buena atención',
                'fecha_creacion': '2026-11-22T15:00:00Z',
                'fecha_actualizacion': '2026-11-22T15:00:00Z',
                'mensaje': '¡Gracias! Tu valoración fue registrada correctamente.',
              }),
              201,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );

        ValoracionClinica? resultado;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    resultado = await Navigator.of(context)
                        .push<ValoracionClinica>(
                          MaterialPageRoute<ValoracionClinica>(
                            builder: (_) => ValorarAtencionPage(
                              consultaClinicaId: 10,
                              oftalmologo: oftalmologo,
                              fechaConsulta: DateTime(2026, 11, 22, 10, 30),
                              motivoConsulta: 'Molestia en el ojo',
                              tieneReceta: true,
                              empresaNombre: 'Visión Clara',
                              valoracionService: service,
                            ),
                          ),
                        );
                  },
                  child: const Text('Abrir'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();

        // 1. Intentar guardar sin elegir estrellas -> error de validación
        await tester.ensureVisible(find.byKey(const Key('btn_guardar_valoracion')));
        await tester.tap(find.byKey(const Key('btn_guardar_valoracion')));
        await tester.pump();
        expect(find.textContaining('entre 1 y 5 estrellas'), findsOneWidget);

        // 2. Elegir 5 estrellas y escribir comentario opcional
        await tester.ensureVisible(find.byKey(const Key('estrella_5')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('estrella_5')));
        await tester.pump();
        await tester.ensureVisible(
          find.byKey(const Key('campo_comentario_valoracion')),
        );
        await tester.enterText(
          find.byKey(const Key('campo_comentario_valoracion')),
          'Muy buena atención',
        );

        // 3. Presionar Guardar -> debe mostrar diálogo de confirmación
        await tester.ensureVisible(find.byKey(const Key('btn_guardar_valoracion')));
        await tester.tap(find.byKey(const Key('btn_guardar_valoracion')));
        await tester.pumpAndSettle();
        expect(find.text('¿Confirmar valoración?'), findsOneWidget);

        // 4. Confirmar -> primer intento falla (500) y muestra Reintentar
        await tester.tap(
          find.byKey(const Key('btn_confirmar_dialogo_valoracion')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Error temporal del servidor'), findsOneWidget);
        expect(find.byKey(const Key('btn_reintentar_valoracion')), findsOneWidget);

        // 5. Reintentar -> segundo intento exitoso cierra la pantalla con resultado
        await tester.ensureVisible(
          find.byKey(const Key('btn_reintentar_valoracion')),
        );
        await tester.tap(find.byKey(const Key('btn_reintentar_valoracion')));
        await tester.pumpAndSettle();

        expect(intentos, 2);
        expect(resultado, isNotNull);
        expect(resultado!.id, 42);
        expect(resultado!.puntuacion, 5);
      },
    );

    testWidgets(
      'precarga datos existentes en modo actualización y envía PUT',
      (tester) async {
        String? metodoUsado;
        final service = ValoracionService(
          leerToken: () async => 'jwt-valido',
          client: MockClient((request) async {
            metodoUsado = request.method;
            return http.Response(
              jsonEncode({
                'id': 77,
                'paciente_id': 100,
                'consulta_clinica_id': 10,
                'oftalmologo_id': 1,
                'puntuacion': 4,
                'etiqueta_puntuacion': 'Buena',
                'comentario': 'Comentario actualizado',
                'fecha_creacion': '2026-11-22T15:00:00Z',
                'fecha_actualizacion': '2026-11-22T16:00:00Z',
                'mensaje': 'Tu valoración fue actualizada correctamente.',
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );

        final existente = ValoracionClinica(
          id: 77,
          pacienteId: 100,
          consultaClinicaId: 10,
          oftalmologoId: 1,
          puntuacion: 3,
          etiquetaPuntuacion: 'Regular',
          comentario: 'Inicial',
          fechaCreacion: DateTime(2026, 11, 22, 15, 0),
          fechaActualizacion: DateTime(2026, 11, 22, 15, 0),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ValorarAtencionPage(
              consultaClinicaId: 10,
              oftalmologo: oftalmologo,
              fechaConsulta: DateTime(2026, 11, 22, 10, 30),
              valoracionExistente: existente,
              valoracionService: service,
            ),
          ),
        );

        expect(find.text('Actualizar valoración'), findsWidgets);
        expect(find.text('Inicial'), findsOneWidget);

        await tester.tap(find.byKey(const Key('estrella_4')));
        await tester.enterText(
          find.byKey(const Key('campo_comentario_valoracion')),
          'Comentario actualizado',
        );
        await tester.ensureVisible(find.byKey(const Key('btn_guardar_valoracion')));
        await tester.tap(find.byKey(const Key('btn_guardar_valoracion')));
        await tester.pumpAndSettle();

        expect(find.text('¿Confirmar actualización?'), findsOneWidget);
        await tester.tap(
          find.byKey(const Key('btn_confirmar_dialogo_valoracion')),
        );
        await tester.pumpAndSettle();

        expect(metodoUsado, 'PUT');
      },
    );
  });
}
