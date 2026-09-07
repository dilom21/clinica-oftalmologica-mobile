import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/citas/pages/citas_page.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/services/agenda_service.dart';

const _jsonHeaders = {'content-type': 'application/json'};

Map<String, dynamic> _oftalmologoJson() {
  return {
    'id': 1,
    'matricula': 'MAT-100',
    'nombres': 'Carlos',
    'apellidos': 'Ruiz',
    'especialidad': 'Oftalmología general',
  };
}

Map<String, dynamic> _disponibilidadJson({
  required bool tieneHorario,
  required List<Map<String, String>> horariosBase,
  required List<Map<String, String>> intervalos,
}) {
  return {
    'oftalmologo': _oftalmologoJson(),
    'fecha': '2026-09-06',
    'tiene_horario': tieneHorario,
    'horarios_base': horariosBase,
    'intervalos_disponibles': intervalos,
  };
}

AgendaService _servicio(Future<http.Response> Function(http.Request) handler) {
  return AgendaService(
    client: MockClient(handler),
    leerToken: () async => 'token-de-prueba',
  );
}

http.Response _json(Object body, int status) {
  return http.Response(jsonEncode(body), status, headers: _jsonHeaders);
}

Future<void> _pumpPage(WidgetTester tester, AgendaService service) async {
  await tester.pumpWidget(MaterialApp(home: CitasPage(agendaService: service)));
  await tester.pumpAndSettle();
}

Future<void> _consultar(WidgetTester tester) async {
  final boton = find.text('Consultar disponibilidad');
  await tester.ensureVisible(boton);
  await tester.pumpAndSettle();
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('intervalos disponibles se renderizan sin botón de reservar', (
    WidgetTester tester,
  ) async {
    final service = _servicio((request) async {
      if (request.url.path == '/agenda-citas/oftalmologos') {
        return _json([_oftalmologoJson()], 200);
      }
      return _json(
        _disponibilidadJson(
          tieneHorario: true,
          horariosBase: [
            {'hora_inicio': '08:00:00', 'hora_fin': '17:00:00'},
          ],
          intervalos: [
            {'hora_inicio': '08:00:00', 'hora_fin': '08:30:00'},
            {'hora_inicio': '09:00:00', 'hora_fin': '10:00:00'},
            {'hora_inicio': '11:30:00', 'hora_fin': '12:00:00'},
          ],
        ),
        200,
      );
    });

    await _pumpPage(tester, service);
    expect(find.text('Carlos Ruiz'), findsWidgets);

    await _consultar(tester);

    expect(find.text('Horario base'), findsOneWidget);
    expect(find.text('08:00 – 17:00'), findsOneWidget);
    expect(find.text('Intervalos disponibles'), findsOneWidget);
    expect(find.text('08:00 – 08:30'), findsOneWidget);
    expect(find.text('09:00 – 10:00'), findsOneWidget);
    expect(find.text('11:30 – 12:00'), findsOneWidget);
    expect(find.text('Disponible'), findsNWidgets(3));

    // CU10 (reservar) no debe existir todavía en esta pantalla.
    expect(find.textContaining('Reservar'), findsNothing);
    expect(find.textContaining('Cancelar cita'), findsNothing);
  });

  testWidgets('tiene_horario=false muestra "Sin horario configurado"', (
    WidgetTester tester,
  ) async {
    final service = _servicio((request) async {
      if (request.url.path == '/agenda-citas/oftalmologos') {
        return _json([_oftalmologoJson()], 200);
      }
      return _json(
        _disponibilidadJson(
          tieneHorario: false,
          horariosBase: const [],
          intervalos: const [],
        ),
        200,
      );
    });

    await _pumpPage(tester, service);
    await _consultar(tester);

    expect(find.text('Sin horario configurado'), findsOneWidget);
    expect(find.text('Horario base'), findsNothing);
    expect(find.text('Intervalos disponibles'), findsNothing);
  });

  testWidgets('lista vacía de intervalos muestra "Sin horarios disponibles"', (
    WidgetTester tester,
  ) async {
    final service = _servicio((request) async {
      if (request.url.path == '/agenda-citas/oftalmologos') {
        return _json([_oftalmologoJson()], 200);
      }
      return _json(
        _disponibilidadJson(
          tieneHorario: true,
          horariosBase: [
            {'hora_inicio': '08:00:00', 'hora_fin': '17:00:00'},
          ],
          intervalos: const [],
        ),
        200,
      );
    });

    await _pumpPage(tester, service);
    await _consultar(tester);

    expect(find.text('Sin horarios disponibles'), findsOneWidget);
    expect(find.text('Intervalos disponibles'), findsNothing);
  });

  testWidgets('lista de oftalmólogos vacía muestra mensaje claro', (
    WidgetTester tester,
  ) async {
    final service = _servicio((request) async {
      return _json(const <Object>[], 200);
    });

    await _pumpPage(tester, service);

    expect(
      find.text(
        'No hay oftalmólogos disponibles para consultar en este momento.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'error al consultar permite reintentar y luego muestra resultado',
    (WidgetTester tester) async {
      var fallo = true;
      final service = _servicio((request) async {
        if (request.url.path == '/agenda-citas/oftalmologos') {
          return _json([_oftalmologoJson()], 200);
        }
        if (fallo) {
          fallo = false;
          return _json({'detail': 'Error interno del servidor'}, 500);
        }
        return _json(
          _disponibilidadJson(
            tieneHorario: true,
            horariosBase: const [],
            intervalos: [
              {'hora_inicio': '08:00:00', 'hora_fin': '09:00:00'},
            ],
          ),
          200,
        );
      });

      await _pumpPage(tester, service);
      await _consultar(tester);

      expect(
        find.text('No se pudo consultar la disponibilidad'),
        findsOneWidget,
      );
      expect(find.text('Error interno del servidor'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);

      final reintentar = find.text('Reintentar');
      await tester.ensureVisible(reintentar);
      await tester.pumpAndSettle();
      await tester.tap(reintentar);
      await tester.pumpAndSettle();

      expect(find.text('Intervalos disponibles'), findsOneWidget);
      expect(find.text('08:00 – 09:00'), findsOneWidget);
    },
  );

  testWidgets(
    'el Paciente solo llama a oftalmologos y disponibilidad, nunca a agenda',
    (WidgetTester tester) async {
      final rutasLlamadas = <String>[];
      final service = _servicio((request) async {
        rutasLlamadas.add(request.url.path);
        if (request.url.path == '/agenda-citas/oftalmologos') {
          return _json([_oftalmologoJson()], 200);
        }
        return _json(
          _disponibilidadJson(
            tieneHorario: true,
            horariosBase: const [],
            intervalos: [
              {'hora_inicio': '08:00:00', 'hora_fin': '08:30:00'},
            ],
          ),
          200,
        );
      });

      await _pumpPage(tester, service);
      await _consultar(tester);

      expect(rutasLlamadas.toSet(), {
        '/agenda-citas/oftalmologos',
        '/agenda-citas/disponibilidad',
      });
      // El endpoint de agenda interna del médico
      // (`/agenda-citas/oftalmologos/{id}/agenda`) nunca debe consumirse.
      expect(rutasLlamadas.where((ruta) => ruta.endsWith('/agenda')), isEmpty);
    },
  );
}
