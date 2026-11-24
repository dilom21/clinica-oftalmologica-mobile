import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/core/session/sesion_clinica.dart';
import 'package:clinica_oftalmologica_mobile/features/catalogo/models/servicio_catalogo.dart';
import 'package:clinica_oftalmologica_mobile/features/catalogo/pages/catalogo_page.dart';
import 'package:clinica_oftalmologica_mobile/features/catalogo/services/catalogo_service.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/pages/chat_agendamiento_page.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/pages/chatbot_page.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/chatbot_service.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/models/agenda_models.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/pages/agendar_cita_view.dart';

import 'soporte_chatbot.dart';

const ClinicaSesion _clinica = ClinicaSesion(
  codigo: 'CLINICA',
  nombre: 'Clínica Ficticia',
);

RespuestaChatbot _todasLasTarjetas() {
  return RespuestaChatbot(
    conversacionId: 'conv-1',
    respuesta:
        'Encontré servicios, profesionales y horarios. También tienes una '
        'propuesta pendiente de confirmación.',
    textoVoz:
        'Encontré servicios, profesionales y horarios. También tienes una '
        'propuesta pendiente de confirmación.',
    tipo: TipoRespuestaChatbot.datos,
    tarjetas: <TarjetaChatbot>[
      TarjetaServicios(
        servicios: <ServicioChat>[
          const ServicioChat(
            id: 1,
            nombre: 'Consulta general',
            descripcion: 'Evaluación visual completa',
            precio: '100.50',
            duracionMinutos: 30,
          ),
          const ServicioChat(
            id: 2,
            nombre: 'Servicio sin precio',
            precio: null,
            duracionMinutos: null,
          ),
        ],
        busqueda: 'consulta',
        offset: 0,
        hayMas: null,
      ),
      TarjetaProfesionales(
        profesionales: <ProfesionalChat>[
          const ProfesionalChat(
            id: 5,
            nombre: 'Profesional Ficticio',
            especialidad: 'Oftalmología general',
          ),
        ],
        hayMas: false,
        offset: 0,
      ),
      TarjetaDisponibilidad(
        oftalmologoId: 5,
        fecha: DateTime(2026, 12, 15),
        intervalos: <IntervaloChat>[
          const IntervaloChat(horaInicio: '08:00:00', horaFin: '08:30:00'),
          const IntervaloChat(horaInicio: '08:30:00', horaFin: '09:00:00'),
          const IntervaloChat(horaInicio: '09:00:00', horaFin: '09:30:00'),
        ],
        profesional: const ProfesionalChat(
          id: 5,
          nombre: 'Profesional Ficticio',
        ),
        franja: FranjaChat.manana,
      ),
      TarjetaPropuestaCita(
        oftalmologoId: 5,
        fecha: DateTime(2026, 12, 15),
        horaInicio: '08:30:00',
        horaFin: '09:00:00',
        profesional: const ProfesionalChat(
          id: 5,
          nombre: 'Profesional Ficticio',
        ),
      ),
      TarjetaCitasPropias(
        citas: <CitaPropiaChat>[
          CitaPropiaChat(
            id: 20,
            oftalmologoId: 5,
            fecha: DateTime(2026, 12, 20),
            horaInicio: '10:00:00',
            horaFin: '10:30:00',
            estado: 'PROGRAMADA',
          ),
        ],
        hayMas: true,
      ),
      const TarjetaClinica(
        nombre: 'Clínica Ficticia',
        telefono: '70000000',
        correo: 'contacto@example.com',
        direccion: 'Calle Ficticia 123',
      ),
      const TarjetaNavegacion(destino: DestinoChat.catalogo),
    ],
  );
}

AgendaFalsa _agenda() {
  return AgendaFalsa(
    oftalmologos: const <OftalmologoAgenda>[
      OftalmologoAgenda(
        id: 5,
        matricula: 'MP-5',
        nombres: 'Profesional',
        apellidos: 'Ficticio',
        especialidad: 'Oftalmología general',
      ),
    ],
    disponibilidad: DisponibilidadRespuesta(
      oftalmologo: const OftalmologoAgenda(
        id: 5,
        matricula: 'MP-5',
        nombres: 'Profesional',
        apellidos: 'Ficticio',
      ),
      fecha: DateTime(2026, 12, 15),
      tieneHorario: true,
      horariosBase: const <IntervaloHorario>[],
      intervalosDisponibles: const <IntervaloHorario>[
        IntervaloHorario(horaInicio: '08:00:00', horaFin: '08:30:00'),
        IntervaloHorario(horaInicio: '08:30:00', horaFin: '09:00:00'),
      ],
    ),
  );
}

class _CatalogoFalso extends CatalogoService {
  @override
  Future<List<ServicioCatalogo>> listar({
    String busqueda = '',
    int offset = 0,
    int limite = 20,
  }) async {
    return const <ServicioCatalogo>[];
  }
}

void main() {
  testWidgets('bienvenida, sugerencias y compositor', (tester) async {
    tester.view.physicalSize = const Size(1000, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = ApiChatbotFalsa();
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(controller: ctrl, clinica: _clinica),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Soy tu asistente virtual'), findsOneWidget);
    expect(find.text('Clínica Ficticia'), findsOneWidget);
    expect(find.text('Quiero agendar una cita'), findsOneWidget);
    expect(find.text('Consultar mis citas'), findsOneWidget);
    expect(find.text('Servicios y precios'), findsOneWidget);
    expect(find.text('Consultar disponibilidad'), findsOneWidget);
    expect(find.text('Información de la clínica'), findsOneWidget);
    expect(find.byKey(const Key('chatbot-compositor')), findsOneWidget);
    expect(find.textContaining('Asistente administrativo'), findsWidgets);
    expect(api.crearLlamadas, 0, reason: 'no crea conversación al abrir');
  });

  testWidgets('sugerencia envía consulta real y renderiza siete tarjetas', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = ApiChatbotFalsa();
    api.respuesta = _todasLasTarjetas();
    final agenda = _agenda();
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(
          controller: ctrl,
          clinica: _clinica,
          agendaService: agenda,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Servicios y precios'));
    await tester.pumpAndSettle();

    expect(api.enviarLlamadas, 1);
    expect(
      api.envios.single['mensaje'],
      'Quiero ver los servicios y precios disponibles.',
    );
    expect(find.text('SERVICIOS'), findsOneWidget);
    expect(find.text('Consulta general'), findsOneWidget);
    expect(find.text('Bs 100.50'), findsOneWidget);
    expect(find.text('Precio por consultar'), findsOneWidget);
    expect(find.text('PROFESIONALES'), findsOneWidget);
    expect(find.text('Profesional Ficticio'), findsWidgets);
    expect(find.text('HORARIOS DISPONIBLES'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('PROPUESTA DE CITA'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('PROPUESTA DE CITA'), findsOneWidget);
    expect(find.text('Pendiente de confirmación'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('TUS CITAS'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('TUS CITAS'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('INFORMACIÓN DE LA CLÍNICA'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('INFORMACIÓN DE LA CLÍNICA'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('ACCIÓN DISPONIBLE'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('ACCIÓN DISPONIBLE'), findsOneWidget);

    // El nombre del profesional se resolvió con CU09.
    await tester.pumpAndSettle();
    expect(agenda.oftalmologosLlamadas, greaterThanOrEqualTo(1));
  });

  testWidgets('horario seleccionado envía contexto y conserva UUID', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = ApiChatbotFalsa();
    api.respuesta = RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Horarios',
      textoVoz: 'Horarios',
      tipo: TipoRespuestaChatbot.datos,
      tarjetas: <TarjetaChatbot>[
        TarjetaDisponibilidad(
          oftalmologoId: 5,
          fecha: DateTime(2026, 12, 15),
          intervalos: <IntervaloChat>[
            const IntervaloChat(horaInicio: '08:30:00', horaFin: '09:00:00'),
          ],
          profesional: const ProfesionalChat(
            id: 5,
            nombre: 'Profesional Ficticio',
          ),
        ),
      ],
    );
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(controller: ctrl, clinica: _clinica),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar disponibilidad'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('08:30'));
    await tester.pumpAndSettle();

    expect(api.enviarLlamadas, 2);
    expect(api.envios.last['conversacion_id'], 'conv-1');
    expect(api.envios.last['mensaje'], contains('Profesional Ficticio'));
    expect(api.envios.last['mensaje'], contains('15 de diciembre de 2026'));
    expect(api.envios.last['mensaje'], contains('08:30'));
  });

  testWidgets('propuesta abre CU10 sin registrar automáticamente', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 3400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = ApiChatbotFalsa();
    api.respuesta = RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Propuesta',
      textoVoz: 'Propuesta',
      tipo: TipoRespuestaChatbot.datos,
      tarjetas: <TarjetaChatbot>[
        TarjetaPropuestaCita(
          oftalmologoId: 5,
          fecha: DateTime(2026, 12, 15),
          horaInicio: '08:30:00',
          horaFin: '09:00:00',
          profesional: const ProfesionalChat(
            id: 5,
            nombre: 'Profesional Ficticio',
          ),
        ),
      ],
    );
    final agenda = _agenda();
    final paciente = PacienteFalso();
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(
          controller: ctrl,
          clinica: _clinica,
          agendaService: agenda,
          pacienteService: paciente,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quiero agendar una cita'));
    await tester.pumpAndSettle();

    expect(find.text('Continuar al agendamiento'), findsOneWidget);
    expect(agenda.crearLlamadas, 0, reason: 'la propuesta no reserva');

    await tester.tap(find.text('Continuar al agendamiento'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatAgendamientoPage), findsOneWidget);
    expect(find.byType(AgendarCitaView), findsOneWidget);
    expect(agenda.disponibilidadLlamadas, 1);
    expect(agenda.crearLlamadas, 0);
    expect(paciente.llamadas, 0);
  });

  testWidgets('error 503 se muestra y permite reintento explícito', (
    tester,
  ) async {
    final api = ApiChatbotFalsa();
    api.errorEnviar = const ChatbotException(
      'El asistente no está disponible.',
      statusCode: 503,
    );
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(controller: ctrl, clinica: _clinica),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('chatbot-compositor')), 'Hola');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chatbot-enviar')));
    await tester.pumpAndSettle();

    expect(find.text('El asistente no está disponible.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(api.enviarLlamadas, 1);

    api.errorEnviar = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(api.enviarLlamadas, 2);
    expect(find.text('Respuesta de prueba'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('401 invoca el cierre de sesión existente', (tester) async {
    final api = ApiChatbotFalsa();
    api.errorEnviar = const ChatbotException(
      'Sesión expirada',
      statusCode: 401,
    );
    var cierres = 0;
    final ctrl = ChatbotController(
      api: api,
      leerToken: () async => 'jwt',
      alSesionInvalida: () async => cierres++,
    );
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(
          controller: ctrl,
          clinica: _clinica,
          onSesionInvalida: () async => cierres++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chatbot-compositor')), 'Hola');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chatbot-enviar')));
    await tester.pumpAndSettle();

    expect(cierres, 1);
    expect(ctrl.mensajes, isEmpty);
  });

  testWidgets('compositor vacío no envía y respeta el límite', (tester) async {
    final api = ApiChatbotFalsa();
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(controller: ctrl, clinica: _clinica),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chatbot-enviar')));
    await tester.pump();
    expect(api.enviarLlamadas, 0);

    final TextField campo = tester.widget<TextField>(
      find.byKey(const Key('chatbot-compositor')),
    );
    expect(campo.maxLength, 1000);
    expect(campo.maxLines, 5);
  });

  testWidgets('nueva conversación confirma, limpia y usa DELETE', (
    tester,
  ) async {
    final api = ApiChatbotFalsa();
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(controller: ctrl, clinica: _clinica),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chatbot-compositor')), 'Hola');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chatbot-enviar')));
    await tester.pumpAndSettle();
    expect(find.text('Respuesta de prueba'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chatbot-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nueva conversación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Empezar de nuevo'));
    await tester.pumpAndSettle();

    expect(ctrl.mensajes, isEmpty);
    expect(api.idsBorrados, <String>['conv-1']);
    expect(find.text('Soy tu asistente virtual'), findsOneWidget);
  });

  testWidgets('muestra indicador de carga mientras espera la respuesta', (
    tester,
  ) async {
    final api = ApiChatbotFalsa();
    final Completer<RespuestaChatbot> pendiente = Completer<RespuestaChatbot>();
    api.alEnviar = (_, _) => pendiente.future;
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(controller: ctrl, clinica: _clinica),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chatbot-compositor')), 'Hola');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chatbot-enviar')));
    await tester.pump();

    expect(find.text('El asistente está escribiendo...'), findsOneWidget);
    expect(api.enviarLlamadas, 1);

    pendiente.complete(
      const RespuestaChatbot(
        conversacionId: 'conv-1',
        respuesta: 'Respuesta final',
        textoVoz: 'Respuesta final',
        tipo: TipoRespuestaChatbot.texto,
        tarjetas: <TarjetaChatbot>[],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Respuesta final'), findsOneWidget);
    expect(find.text('El asistente está escribiendo...'), findsNothing);
  });

  testWidgets('tarjetas vacías muestran mensajes neutros', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = ApiChatbotFalsa();
    api.respuesta = const RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Sin resultados',
      textoVoz: 'Sin resultados',
      tipo: TipoRespuestaChatbot.datos,
      tarjetas: <TarjetaChatbot>[
        TarjetaServicios(servicios: <ServicioChat>[]),
        TarjetaProfesionales(profesionales: <ProfesionalChat>[]),
        TarjetaCitasPropias(citas: <CitaPropiaChat>[]),
      ],
    );
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatbotPage(controller: ctrl, clinica: _clinica),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quiero agendar una cita'));
    await tester.pumpAndSettle();

    expect(
      find.text('No hay servicios disponibles en esta consulta.'),
      findsOneWidget,
    );
    expect(
      find.text('No hay profesionales disponibles en esta consulta.'),
      findsOneWidget,
    );
    expect(
      find.text('No tienes citas próximas para mostrar con este filtro.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'tarjetas históricas no permiten seleccionar horarios obsoletos',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = ApiChatbotFalsa();
      api.alEnviar = (String mensaje, ModalidadChat modalidad) async {
        if (mensaje.contains('disponibilidad')) {
          return RespuestaChatbot(
            conversacionId: 'conv-1',
            respuesta: 'Horarios',
            textoVoz: 'Horarios',
            tipo: TipoRespuestaChatbot.datos,
            tarjetas: <TarjetaChatbot>[
              TarjetaDisponibilidad(
                oftalmologoId: 5,
                fecha: DateTime(2026, 12, 15),
                intervalos: <IntervaloChat>[
                  const IntervaloChat(
                    horaInicio: '08:00:00',
                    horaFin: '08:30:00',
                  ),
                ],
                profesional: const ProfesionalChat(
                  id: 5,
                  nombre: 'Profesional Ficticio',
                ),
              ),
            ],
          );
        }
        return const RespuestaChatbot(
          conversacionId: 'conv-1',
          respuesta: 'Respuesta posterior',
          textoVoz: 'Respuesta posterior',
          tipo: TipoRespuestaChatbot.texto,
          tarjetas: <TarjetaChatbot>[],
        );
      };
      final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatbotPage(controller: ctrl, clinica: _clinica),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Consultar disponibilidad'));
      await tester.pumpAndSettle();
      expect(find.text('08:00'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('chatbot-compositor')),
        'Otra consulta',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('chatbot-enviar')));
      await tester.pumpAndSettle();

      expect(find.text('Respuesta posterior'), findsOneWidget);
      final int enviosAntes = api.enviarLlamadas;

      await tester.scrollUntilVisible(
        find.text('08:00'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('08:00'));
      await tester.pumpAndSettle();

      expect(api.enviarLlamadas, enviosAntes);
      expect(
        find.textContaining('Esta disponibilidad es de una consulta anterior'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'navegación abre catálogo y listado reales sin duplicar CU38/CU10',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final api = ApiChatbotFalsa();
      api.respuesta = RespuestaChatbot(
        conversacionId: 'conv-1',
        respuesta: 'Puedes revisar el catálogo o tus citas.',
        textoVoz: 'Puedes revisar el catálogo o tus citas.',
        tipo: TipoRespuestaChatbot.datos,
        tarjetas: <TarjetaChatbot>[
          const TarjetaNavegacion(destino: DestinoChat.catalogo),
          TarjetaCitasPropias(
            citas: <CitaPropiaChat>[
              CitaPropiaChat(
                id: 20,
                oftalmologoId: 5,
                fecha: DateTime(2026, 12, 20),
                horaInicio: '10:00:00',
                horaFin: '10:30:00',
                estado: 'PROGRAMADA',
              ),
            ],
            hayMas: true,
          ),
        ],
      );
      final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ChatbotPage(
            controller: ctrl,
            clinica: _clinica,
            agendaService: _agenda(),
            catalogoService: _CatalogoFalso(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quiero agendar una cita'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Abrir'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      expect(find.byType(CatalogoPage), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Ver todas mis citas'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Ver todas mis citas'));
      await tester.pumpAndSettle();
      expect(find.text('Mis citas'), findsOneWidget);
    },
  );

  testWidgets('pantalla estrecha y texto al 200% no desborda', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final api = ApiChatbotFalsa();
    final ctrl = ChatbotController(api: api, leerToken: () async => 'jwt');
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          );
        },
        home: ChatbotPage(controller: ctrl, clinica: _clinica),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Soy tu asistente virtual'), findsOneWidget);
  });
}
