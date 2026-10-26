import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/informacion_clinica/pages/informacion_clinica_page.dart';
import 'package:clinica_oftalmologica_mobile/features/informacion_clinica/services/informacion_clinica_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

http.Response _json(Object body, int status) =>
    http.Response(jsonEncode(body), status, headers: _jsonHeaders);

InformacionClinicaService _servicio(Object body, {int status = 200}) {
  return InformacionClinicaService(
    client: MockClient((request) async => _json(body, status)),
    leerToken: () async => 'token-de-prueba',
  );
}

Future<void> _pump(
  WidgetTester tester,
  InformacionClinicaService servicio, {
  Future<void> Function()? alCerrarSesion,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: InformacionClinicaPage(
        servicio: servicio,
        alCerrarSesion: alCerrarSesion,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump();
  }
}

void main() {
  testWidgets('muestra antecedentes, controles y abre el detalle', (
    tester,
  ) async {
    await _pump(
      tester,
      _servicio({
        'historial_id': 10,
        'fecha_apertura': '2026-09-01T14:00:00Z',
        'observaciones_generales': 'Usa lentes desde 2018',
        'antecedentes': [
          {
            'id': 1,
            'tipo': 'ALERGIA',
            'descripcion': 'Penicilina',
            'fecha_registro': '2026-09-01T14:00:00Z',
          },
        ],
        'consultas': [
          {
            'id': 100,
            'fecha_consulta': '2026-10-01T19:00:00Z',
            'motivo_consulta': 'Control de glaucoma',
            'anamnesis': 'Presión ocular elevada',
            'observaciones': null,
            'oftalmologo': {
              'id': 1,
              'nombres': 'Salet',
              'apellidos': 'Ejemplo',
              'especialidad': 'Glaucoma',
            },
            'diagnosticos': [
              {
                'id': 1,
                'nombre': 'Glaucoma',
                'descripcion': 'Ojo derecho',
                'fecha_diagnostico': '2026-10-01T20:00:00Z',
              },
            ],
            'tratamientos': [],
            'indicaciones': [],
            'recetas': [
              {
                'id': 1,
                'fecha_emision': '2026-10-01T20:20:00Z',
                'observaciones': null,
                'detalles': [
                  {
                    'id': 1,
                    'medicamento': 'Timolol',
                    'presentacion': 'Colirio',
                    'dosis': null,
                    'frecuencia': null,
                    'duracion': null,
                    'indicaciones': null,
                  },
                ],
              },
            ],
            'examenes': [],
          },
        ],
        'controles': [
          {
            'id': 1,
            'fecha_programada': '2026-11-01',
            'motivo': 'Control de presión',
            'observaciones': null,
            'estado': 'PROGRAMADO',
            'oftalmologo': {
              'id': 1,
              'nombres': 'Salet',
              'apellidos': 'Ejemplo',
              'especialidad': null,
            },
          },
        ],
      }),
    );

    expect(find.text('Penicilina'), findsOneWidget);
    expect(find.text('Alergia'), findsOneWidget);
    expect(find.text('Control de presión'), findsOneWidget);
    expect(find.text('Control de glaucoma'), findsOneWidget);
    expect(find.text('Usa lentes desde 2018'), findsOneWidget);

    await tester.tap(find.text('Control de glaucoma'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('consulta-clinica-detalle')), findsOneWidget);
    expect(find.text('Glaucoma'), findsWidgets);
    expect(find.text('Timolol'), findsOneWidget);
    expect(find.text('Presión ocular elevada'), findsOneWidget);
  });

  testWidgets('sin registros muestra el estado vacío', (tester) async {
    await _pump(
      tester,
      _servicio({
        'historial_id': null,
        'fecha_apertura': null,
        'observaciones_generales': null,
        'antecedentes': [],
        'consultas': [],
        'controles': [],
      }),
    );

    expect(find.byKey(const Key('informacion-clinica-vacia')), findsOneWidget);
    expect(find.textContaining('no hay información clínica'), findsOneWidget);
  });

  testWidgets('un 401 cierra la sesión y no muestra el error de red', (
    tester,
  ) async {
    var cerro = false;
    await _pump(
      tester,
      _servicio({'detail': 'Tu sesión expiró. Vuelve a iniciar sesión.'}, status: 401),
      alCerrarSesion: () async {
        cerro = true;
      },
      settle: false,
    );

    expect(cerro, isTrue);
    expect(find.byKey(const Key('informacion-clinica-error')), findsNothing);
  });
}
