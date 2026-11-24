import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/pages/chat_agendamiento_page.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/pages/chatbot_page.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/models/agenda_models.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/pages/agendar_cita_view.dart';

import 'soporte_chatbot.dart';

const _profesional = OftalmologoAgenda(
  id: 5,
  matricula: 'MP-5',
  nombres: 'Salet',
  apellidos: 'Ejemplo',
);
final _fecha = DateTime(2026, 11, 27);

DisponibilidadRespuesta _disponibilidad({bool libre = true}) =>
    DisponibilidadRespuesta(
      oftalmologo: _profesional,
      fecha: _fecha,
      tieneHorario: true,
      horariosBase: const [],
      intervalosDisponibles: libre
          ? const [
              IntervaloHorario(horaInicio: '14:00:00', horaFin: '14:30:00'),
            ]
          : const [],
    );

class _Agenda extends AgendaFalsa {
  _Agenda()
    : super(
        oftalmologos: const [_profesional],
        disponibilidad: _disponibilidad(),
      );
  Completer<void>? esperaValidacion;

  @override
  Future<DisponibilidadRespuesta> obtenerDisponibilidad({
    required int oftalmologoId,
    required DateTime fecha,
  }) async {
    final resultado = await super.obtenerDisponibilidad(
      oftalmologoId: oftalmologoId,
      fecha: fecha,
    );
    if (disponibilidadLlamadas == 2) await esperaValidacion?.future;
    return resultado;
  }
}

RespuestaChatbot _respuesta({bool propuesta = true}) => RespuestaChatbot(
  conversacionId: 'conv-1',
  respuesta: propuesta ? 'Propuesta pendiente' : '¡De nada!',
  textoVoz: propuesta ? 'Propuesta pendiente' : '¡De nada!',
  tipo: TipoRespuestaChatbot.texto,
  tarjetas: propuesta
      ? [
          TarjetaPropuestaCita(
            oftalmologoId: 5,
            fecha: _fecha,
            horaInicio: '14:00:00',
            horaFin: '14:30:00',
            profesional: const ProfesionalChat(id: 5, nombre: 'Salet Ejemplo'),
          ),
        ]
      : const [],
);

void main() {
  late ApiChatbotFalsa api;
  late ChatbotController ctrl;
  late _Agenda agenda;
  late PacienteFalso paciente;

  setUp(() {
    api = ApiChatbotFalsa()..respuesta = _respuesta();
    ctrl = ChatbotController(
      api: api,
      leerToken: () async => 'jwt',
      ahora: () => DateTime(2026, 11, 23, 16),
    );
    agenda = _Agenda();
    paciente = PacienteFalso(id: 42);
  });
  tearDown(() => ctrl.dispose());

  Future<MensajeChat> mostrar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final mensaje = (await ctrl.enviar(
      'Cita con Salet Ejemplo el 27 a las 14:00',
    ))!;
    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(
          controller: ctrl,
          agendaService: agenda,
          pacienteService: paciente,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return mensaje;
  }

  Finder getContinuar() =>
      find.widgetWithText(FilledButton, 'Continuar al agendamiento');
  Future<void> abrir(WidgetTester tester) async {
    await tester.ensureVisible(getContinuar());
    await tester.tap(getContinuar());
    await tester.pumpAndSettle();
    expect(find.byType(ChatAgendamientoPage), findsOneWidget);
    expect(find.byType(AgendarCitaView), findsOneWidget);
  }

  testWidgets(
    'cortesía en curso solo suspende el botón, no vuelve histórica la propuesta',
    (tester) async {
      await mostrar(tester);
      final pendiente = Completer<RespuestaChatbot>();
      api.alEnviar = (_, _) => pendiente.future;
      final envio = ctrl.enviar('Okay muchas gracias');
      await tester.pump();
      await tester.pump();
      expect(ctrl.enviando, isTrue);
      expect(tester.widget<FilledButton>(getContinuar()).onPressed, isNull);
      expect(
        find.textContaining('Esta propuesta ya no está vigente'),
        findsNothing,
      );
      pendiente.complete(_respuesta(propuesta: false));
      await envio;
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(getContinuar()).onPressed, isNotNull);
    },
  );

  for (final social in [false, true]) {
    testWidgets(
      'propuesta reciente/social=$social abre preselección real; volver no crea cita',
      (tester) async {
        final mensaje = await mostrar(tester);
        if (social) {
          api.respuesta = _respuesta(propuesta: false);
          await ctrl.enviar(
            'Okay muchas gracias',
            modalidad: ModalidadChat.voz,
          );
          await tester.pumpAndSettle();
        }
        expect(
          tester.widget<FilledButton>(getContinuar()).onPressed,
          isNotNull,
        );
        expect(
          find.textContaining('Esta propuesta ya no está vigente'),
          findsNothing,
        );
        await abrir(tester);
        final pagina = tester.widget<ChatAgendamientoPage>(
          find.byType(ChatAgendamientoPage),
        );
        expect(pagina.preseleccion?.oftalmologoId, 5);
        expect(pagina.preseleccion?.fecha, _fecha);
        expect(pagina.preseleccion?.horaInicio, '14:00:00');
        expect(agenda.disponibilidadLlamadas, 1);
        expect(agenda.ultimoOftalmologoId, 5);
        expect(agenda.ultimaFecha, _fecha);
        expect(agenda.crearLlamadas, 0);
        expect(paciente.llamadas, 0);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(agenda.crearLlamadas, 0);
        expect(ctrl.propuestaVigente(mensaje.id, 0), isTrue);
      },
    );
  }

  testWidgets(
    'sustitución deshabilita solo la propuesta anterior y callback antiguo no navega',
    (tester) async {
      await mostrar(tester);
      final callbackAntiguo = tester
          .widget<FilledButton>(getContinuar())
          .onPressed!;
      await ctrl.enviar('Haz otra propuesta');
      await tester.pumpAndSettle();
      final botones = tester.widgetList<FilledButton>(getContinuar()).toList();
      expect(botones, hasLength(2));
      expect(botones.first.onPressed, isNull);
      expect(botones.last.onPressed, isNotNull);
      callbackAntiguo();
      await tester.pumpAndSettle();
      expect(find.byType(ChatAgendamientoPage), findsNothing);
      expect(agenda.crearLlamadas, 0);
    },
  );

  testWidgets(
    'confirmar revalida disponibilidad, registra una vez e invalida la propuesta',
    (tester) async {
      final mensaje = await mostrar(tester);
      await abrir(tester);
      final confirmar = find.widgetWithText(FilledButton, 'Confirmar cita');
      await tester.ensureVisible(confirmar);
      await tester.tap(confirmar);
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(agenda.crearLlamadas, 1);
      expect(
        agenda.disponibilidadLlamadas,
        3,
        reason: 'entrada, justo antes del POST y refresco tras registro',
      );
      expect(agenda.citasCreadas.single.pacienteId, 42);
      expect(agenda.citasCreadas.single.oftalmologoId, 5);
      expect(agenda.citasCreadas.single.fecha, _fecha);
      expect(agenda.citasCreadas.single.horaInicio, '14:00:00');
      expect(ctrl.propuestaVigente(mensaje.id, 0), isFalse);
      // Con servicios síncronos el segundo toque puede ver ya la selección
      // consumida y mostrar el aviso (nunca hace otro POST).
      if (find.byType(AlertDialog).evaluate().isNotEmpty) {
        await tester.tap(find.text('Entendido'));
        await tester.pumpAndSettle();
      }
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ChatbotPage), findsOneWidget);
      expect(ctrl.mensajes.any((m) => m.id == mensaje.id), isTrue);
      api.respuesta = _respuesta(propuesta: false);
      await ctrl.enviar('Gracias');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(getContinuar()).onPressed, isNull);
    },
  );

  testWidgets(
    'horario ocupado durante el formulario bloquea el POST en confirmación',
    (tester) async {
      await mostrar(tester);
      await abrir(tester);
      agenda.disponibilidad = _disponibilidad(libre: false);
      final confirmar = find.widgetWithText(FilledButton, 'Confirmar cita');
      await tester.ensureVisible(confirmar);
      await tester.tap(confirmar);
      await tester.pumpAndSettle();
      expect(agenda.disponibilidadLlamadas, 2);
      expect(agenda.crearLlamadas, 0);
      expect(
        find.textContaining('El horario seleccionado ya no está disponible'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'cambio de contexto mientras se valida disponibilidad impide el POST',
    (tester) async {
      await mostrar(tester);
      await abrir(tester);
      agenda.esperaValidacion = Completer<void>();
      final confirmar = find.widgetWithText(FilledButton, 'Confirmar cita');
      await tester.ensureVisible(confirmar);
      await tester.tap(confirmar);
      await tester.pump();
      expect(agenda.disponibilidadLlamadas, 2);
      api.respuesta = _respuesta(propuesta: false);
      await ctrl.enviar('Cambia de profesional y de fecha');
      agenda.esperaValidacion!.complete();
      await tester.pumpAndSettle();
      expect(agenda.crearLlamadas, 0);
      expect(
        find.textContaining('La propuesta ya no está vigente'),
        findsOneWidget,
      );
    },
  );
}
