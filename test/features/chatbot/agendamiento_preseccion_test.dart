import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/core/session/sesion_clinica.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/models/agenda_models.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/models/cita_models.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/models/preseleccion_cita.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/pages/agendar_cita_view.dart';

import 'soporte_chatbot.dart';

const ClinicaSesion _clinica = ClinicaSesion(
  codigo: 'CLINICA',
  nombre: 'Clínica Ficticia',
);

const OftalmologoAgenda _profesional = OftalmologoAgenda(
  id: 5,
  matricula: 'MP-5',
  nombres: 'Profesional',
  apellidos: 'Ficticio',
  especialidad: 'Oftalmología general',
);

DisponibilidadRespuesta _disponibilidad({
  List<IntervaloHorario> intervalos = const <IntervaloHorario>[
    IntervaloHorario(horaInicio: '08:00:00', horaFin: '08:30:00'),
    IntervaloHorario(horaInicio: '08:30:00', horaFin: '09:00:00'),
    IntervaloHorario(horaInicio: '09:00:00', horaFin: '09:30:00'),
  ],
}) {
  return DisponibilidadRespuesta(
    oftalmologo: _profesional,
    fecha: DateTime(2026, 12, 15),
    tieneHorario: true,
    horariosBase: const <IntervaloHorario>[],
    intervalosDisponibles: intervalos,
  );
}

Widget _app({
  required AgendaFalsa agenda,
  required PacienteFalso paciente,
  PreseleccionCita? preseleccion,
  void Function(Cita)? alCrear,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AgendarCitaView(
        agendaService: agenda,
        pacienteService: paciente,
        clinica: _clinica,
        preseleccion: preseleccion,
        onCitaCreada: alCrear,
        onSesionInvalida: () async {},
      ),
    ),
  );
}

void main() {
  final PreseleccionCita propuesta = PreseleccionCita(
    oftalmologoId: 5,
    fecha: DateTime(2026, 12, 15),
    horaInicio: '08:30:00',
  );

  testWidgets('preselección consulta disponibilidad fresca y no registra', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final agenda = AgendaFalsa(
      oftalmologos: const <OftalmologoAgenda>[_profesional],
      disponibilidad: _disponibilidad(),
    );
    final paciente = PacienteFalso();

    await tester.pumpWidget(
      _app(agenda: agenda, paciente: paciente, preseleccion: propuesta),
    );
    await tester.pumpAndSettle();

    expect(agenda.disponibilidadLlamadas, 1);
    expect(agenda.ultimoOftalmologoId, 5);
    expect(agenda.ultimaFecha, DateTime(2026, 12, 15));
    expect(agenda.crearLlamadas, 0, reason: 'no registra automáticamente');
    expect(paciente.llamadas, 0, reason: 'solo resuelve al confirmar');
    expect(find.text('Resumen de tu cita'), findsOneWidget);
    expect(find.text('08:30 – 09:00'), findsWidgets);

    final FilledButton confirmar = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar cita'),
    );
    expect(confirmar.onPressed, isNotNull);
  });

  testWidgets('horario ocupado después de la propuesta se informa', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final agenda = AgendaFalsa(
      oftalmologos: const <OftalmologoAgenda>[_profesional],
      disponibilidad: _disponibilidad(
        intervalos: const <IntervaloHorario>[
          IntervaloHorario(horaInicio: '10:00:00', horaFin: '10:30:00'),
        ],
      ),
    );

    await tester.pumpWidget(
      _app(agenda: agenda, paciente: PacienteFalso(), preseleccion: propuesta),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('El horario propuesto ya no está disponible'),
      findsOneWidget,
    );
    expect(find.text('Resumen de tu cita'), findsNothing);
    final FilledButton confirmar = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar cita'),
    );
    expect(confirmar.onPressed, isNull);
  });

  testWidgets('profesional propuesto inexistente se informa sin inventar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final agenda = AgendaFalsa(
      oftalmologos: const <OftalmologoAgenda>[
        OftalmologoAgenda(
          id: 99,
          matricula: 'MP-99',
          nombres: 'Otro',
          apellidos: 'Profesional',
        ),
      ],
    );

    await tester.pumpWidget(
      _app(agenda: agenda, paciente: PacienteFalso(), preseleccion: propuesta),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('El profesional propuesto ya no está disponible'),
      findsOneWidget,
    );
    expect(agenda.disponibilidadLlamadas, 0);
    final FilledButton confirmar = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar cita'),
    );
    expect(confirmar.onPressed, isNull);
  });

  testWidgets('confirmación explícita usa paciente real y evita duplicados', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final agenda = AgendaFalsa(
      oftalmologos: const <OftalmologoAgenda>[_profesional],
      disponibilidad: _disponibilidad(),
    );
    final paciente = PacienteFalso(id: 42);
    var creadas = 0;

    await tester.pumpWidget(
      _app(
        agenda: agenda,
        paciente: paciente,
        preseleccion: propuesta,
        alCrear: (_) => creadas++,
      ),
    );
    await tester.pumpAndSettle();

    expect(agenda.crearLlamadas, 0);
    final Finder boton = find.widgetWithText(FilledButton, 'Confirmar cita');

    await tester.tap(boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();

    expect(agenda.crearLlamadas, 1);
    expect(creadas, 1);
    expect(paciente.llamadas, 1);
    final CitaCreate cuerpo = agenda.citasCreadas.single;
    expect(cuerpo.pacienteId, 42);
    expect(cuerpo.oftalmologoId, 5);
    expect(cuerpo.fecha, DateTime(2026, 12, 15));
    expect(cuerpo.horaInicio, '08:30:00');
    expect(find.text('¡Cita registrada!'), findsOneWidget);
  });

  testWidgets('selección manual y resumen funcionan sin preselección', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final agenda = AgendaFalsa(
      oftalmologos: const <OftalmologoAgenda>[_profesional],
      disponibilidad: _disponibilidad(),
    );

    await tester.pumpWidget(_app(agenda: agenda, paciente: PacienteFalso()));
    await tester.pumpAndSettle();

    expect(agenda.disponibilidadLlamadas, 0);
    await tester.tap(find.text('Consultar disponibilidad'));
    await tester.pumpAndSettle();
    expect(agenda.disponibilidadLlamadas, 1);

    await tester.tap(find.text('09:00 – 09:30').first);
    await tester.pumpAndSettle();
    expect(find.text('Resumen de tu cita'), findsOneWidget);
    final FilledButton confirmar = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Confirmar cita'),
    );
    expect(confirmar.onPressed, isNotNull);
  });
}
