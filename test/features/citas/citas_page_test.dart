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

/// Abre la vista "Mis citas" del contenedor de la pestaña Citas.
Future<void> _abrirMisCitas(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('citas-vista-mis-citas')));
  await tester.pumpAndSettle();
}

/// `CitaResponse` real de FastAPI (`GET /agenda-citas/citas`).
Map<String, dynamic> _citaJson({
  int id = 7,
  String fecha = '2099-05-20',
  String horaInicio = '09:00:00',
  String horaFin = '09:30:00',
  String estado = 'PROGRAMADA',
  String? motivo,
}) {
  return {
    'id': id,
    'paciente_id': 42,
    'oftalmologo_id': 1,
    'fecha': fecha,
    'hora_inicio': horaInicio,
    'hora_fin': horaFin,
    'estado': estado,
    'motivo': motivo,
    'observaciones': null,
    'fecha_registro': '2099-05-01T10:00:00',
    'fecha_actualizacion': null,
  };
}

/// `VistaCitas` activa según el selector: la opción activa no tiene `onTap`.
bool _vistaActiva(WidgetTester tester, String clave) {
  final InkWell opcion = tester.widget<InkWell>(find.byKey(Key(clave)));
  return opcion.onTap == null;
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
    // Los intervalos libres se proyectan en turnos reales de 30 minutos.
    expect(find.text('08:00 – 08:30'), findsOneWidget);
    expect(find.text('09:00 – 09:30'), findsOneWidget);
    expect(find.text('09:30 – 10:00'), findsOneWidget);
    expect(find.text('11:30 – 12:00'), findsOneWidget);
    // El intervalo de 60 minutos del backend no se ofrece como turno único.
    expect(find.text('09:00 – 10:00'), findsNothing);

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
      expect(find.text('08:00 – 08:30'), findsOneWidget);
      expect(find.text('08:30 – 09:00'), findsOneWidget);
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

  testWidgets('al elegir un turno aparece el resumen antes de confirmar', (
    WidgetTester tester,
  ) async {
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
            {'hora_inicio': '09:00:00', 'hora_fin': '09:30:00'},
          ],
        ),
        200,
      );
    });

    await _pumpPage(tester, service);
    await _consultar(tester);

    final turno = find.text('09:00 – 09:30');
    await tester.ensureVisible(turno);
    await tester.pumpAndSettle();
    await tester.tap(turno);
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Confirmar cita'),
      280,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Resumen de tu cita'), findsOneWidget);
    expect(find.text('Horario'), findsOneWidget);

    final FilledButton confirmar = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar cita'),
    );
    expect(confirmar.onPressed, isNotNull);

    // Nada se envía al backend hasta que el paciente confirme.
    expect(rutasLlamadas, isNot(contains('/agenda-citas/citas')));
  });

  testWidgets('la pestaña Mis citas lista las citas reales del paciente', (
    WidgetTester tester,
  ) async {
    final rutasLlamadas = <String>[];
    final service = _servicio((request) async {
      rutasLlamadas.add(request.url.path);
      if (request.url.path == '/agenda-citas/citas') {
        return _json([_citaJson(motivo: 'Control visual anual')], 200);
      }
      return _json([_oftalmologoJson()], 200);
    });

    await _pumpPage(tester, service);

    // Carga diferida: el historial no se pide al abrir la pestaña.
    expect(rutasLlamadas, isNot(contains('/agenda-citas/citas')));
    expect(_vistaActiva(tester, 'citas-vista-agendar'), isTrue);

    await _abrirMisCitas(tester);

    expect(_vistaActiva(tester, 'citas-vista-mis-citas'), isTrue);
    expect(
      rutasLlamadas.where((String ruta) => ruta == '/agenda-citas/citas'),
      hasLength(1),
    );
    expect(find.text('Próximas citas'), findsOneWidget);
    expect(find.text('09:00 – 09:30'), findsOneWidget);
    expect(find.text('Programada'), findsOneWidget);
    expect(find.text('Control visual anual'), findsOneWidget);
    // El nombre del médico proviene de `GET /agenda-citas/oftalmologos`.
    expect(find.text('Carlos Ruiz'), findsWidgets);
  });

  testWidgets('sin citas registradas se ofrece agendar una nueva', (
    WidgetTester tester,
  ) async {
    final service = _servicio((request) async {
      if (request.url.path == '/agenda-citas/citas') {
        return _json(const <Object>[], 200);
      }
      return _json(const <Object>[], 200);
    });

    await _pumpPage(tester, service);
    await _abrirMisCitas(tester);

    expect(find.text('Aún no tienes citas registradas'), findsOneWidget);

    final agendar = find.text('Agendar cita');
    await tester.ensureVisible(agendar);
    await tester.pumpAndSettle();
    await tester.tap(agendar);
    await tester.pumpAndSettle();

    expect(_vistaActiva(tester, 'citas-vista-agendar'), isTrue);
  });

  testWidgets('un 401 al listar citas avisa al contenedor de la sesión', (
    WidgetTester tester,
  ) async {
    var sesionesInvalidas = 0;
    final service = _servicio((request) async {
      if (request.url.path == '/agenda-citas/citas') {
        return _json({'detail': 'No autenticado'}, 401);
      }
      return _json([_oftalmologoJson()], 200);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: CitasPage(
          agendaService: service,
          onSesionInvalida: () async => sesionesInvalidas++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // El 401 deja la vista esperando la navegación del contenedor, así que no
    // se usa `pumpAndSettle` (el indicador de carga seguiría animándose).
    await tester.tap(find.byKey(const Key('citas-vista-mis-citas')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(sesionesInvalidas, 1);
  });
}
