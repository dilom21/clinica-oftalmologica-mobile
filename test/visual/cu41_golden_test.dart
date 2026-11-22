import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/core/session/sesion_clinica.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chat_voz_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/pages/chat_voz_page.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/pages/chatbot_page.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/models/agenda_models.dart';
import 'package:clinica_oftalmologica_mobile/features/citas/models/cita_models.dart';
import 'package:clinica_oftalmologica_mobile/features/home/pages/inicio_page.dart';

import '../features/chatbot/soporte_chatbot.dart';

/// Capturas de widgets reales para evidencias visuales del CU41.
///
/// No se ejecutan en la suite normal. Para regenerarlas:
///
///   flutter test --update-goldens --dart-define=CU41_GOLDEN=true \
///     test/visual/cu41_golden_test.dart
///
/// Los PNG resultantes viven en `test/visual/goldens/` y no sustituyen una
/// validación en dispositivo físico.
const bool _generar = bool.fromEnvironment('CU41_GOLDEN');

const ClinicaSesion _clinica = ClinicaSesion(
  codigo: 'CLINICA',
  nombre: 'Clínica Ficticia',
);

bool _fuenteCargada = false;

Future<void> _cargarFuente() async {
  final String? envRoot = Platform.environment['FLUTTER_ROOT'];
  final Directory? flutterRoot = envRoot != null ? Directory(envRoot) : null;
  final String? fontsPath = flutterRoot == null
      ? null
      : '${flutterRoot.path}${Platform.pathSeparator}bin'
            '${Platform.pathSeparator}cache${Platform.pathSeparator}artifacts'
            '${Platform.pathSeparator}material_fonts';

  // Iconografía real de Material: el entorno de pruebas no la carga solo.
  if (fontsPath != null) {
    final File iconos = File(
      '$fontsPath${Platform.pathSeparator}materialicons-regular.otf',
    );
    if (iconos.existsSync()) {
      try {
        final Uint8List bytes = await iconos.readAsBytes();
        final FontLoader loader = FontLoader('MaterialIcons')
          ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
        await loader.load();
      } catch (_) {
        // Sin fuente de iconos se conserva la fuente de pruebas.
      }
    }

    // Tipografía Roboto incluida con Flutter, equivalente a la de la app.
    final FontLoader roboto = FontLoader('Roboto');
    bool alguna = false;
    for (final String nombre in <String>[
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
    ]) {
      final File archivo = File('$fontsPath${Platform.pathSeparator}$nombre');
      if (!archivo.existsSync()) continue;
      try {
        final Uint8List bytes = await archivo.readAsBytes();
        roboto.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
        alguna = true;
      } catch (_) {
        // Se intenta la siguiente variante.
      }
    }
    if (alguna) {
      await roboto.load();
      _fuenteCargada = true;
      return;
    }
  }

  const List<String> candidatos = <String>[
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
  ];
  for (final String ruta in candidatos) {
    final File archivo = File(ruta);
    if (!archivo.existsSync()) continue;
    try {
      final Uint8List bytes = await archivo.readAsBytes();
      final FontLoader loader = FontLoader('Roboto')
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      _fuenteCargada = true;
      return;
    } catch (_) {
      // Sin fuente del sistema: se usa la fuente de pruebas.
    }
  }
}

ThemeData _tema() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: _fuenteCargada ? 'Roboto' : null,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1976D2)),
  );
}

RespuestaChatbot _respuestaConversacion() {
  return RespuestaChatbot(
    conversacionId: 'conv-1',
    respuesta:
        'Encontré estos horarios para el profesional ficticio. Puedes elegir '
        'uno y prepararé una propuesta que deberás confirmar.',
    textoVoz:
        'Encontré estos horarios para el profesional ficticio. Puedes elegir '
        'uno y prepararé una propuesta que deberás confirmar.',
    tipo: TipoRespuestaChatbot.datos,
    tarjetas: <TarjetaChatbot>[
      TarjetaDisponibilidad(
        oftalmologoId: 5,
        fecha: DateTime(2026, 12, 15),
        intervalos: <IntervaloChat>[
          const IntervaloChat(horaInicio: '08:00:00', horaFin: '08:30:00'),
          const IntervaloChat(horaInicio: '08:30:00', horaFin: '09:00:00'),
          const IntervaloChat(horaInicio: '09:00:00', horaFin: '09:30:00'),
          const IntervaloChat(horaInicio: '10:00:00', horaFin: '10:30:00'),
        ],
        profesional: const ProfesionalChat(
          id: 5,
          nombre: 'Profesional Ficticio',
          especialidad: 'Oftalmología general',
        ),
        franja: FranjaChat.manana,
      ),
      TarjetaPropuestaCita(
        oftalmologoId: 5,
        fecha: DateTime(2026, 12, 15),
        horaInicio: '09:00:00',
        horaFin: '09:30:00',
        profesional: const ProfesionalChat(
          id: 5,
          nombre: 'Profesional Ficticio',
          especialidad: 'Oftalmología general',
        ),
      ),
    ],
  );
}

AgendaFalsa _agendaConCita() {
  final AgendaFalsa agenda = AgendaFalsa(
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
      intervalosDisponibles: const <IntervaloHorario>[],
    ),
  );
  agenda.citas = <Cita>[
    Cita(
      id: 1,
      pacienteId: 7,
      oftalmologoId: 5,
      fecha: DateTime(2026, 11, 25),
      horaInicio: '09:00:00',
      horaFin: '09:30:00',
      estado: citaProgramada,
      motivo: 'Control visual',
    ),
  ];
  return agenda;
}

Widget _app(Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: _tema(),
    builder: (BuildContext context, Widget? child) {
      return MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
        child: child!,
      );
    },
    home: home,
  );
}

void _tamano(WidgetTester tester, Size tamano) {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    if (_generar) await _cargarFuente();
  });

  testWidgets('01 Inicio con acceso al asistente', (WidgetTester tester) async {
    _tamano(tester, const Size(390, 1000));
    await tester.pumpWidget(
      _app(
        InicioPage(
          clinica: _clinica,
          pacienteService: PacienteFalso(),
          agendaService: _agendaConCita(),
          onAbrirChatbot: () {},
          onAbrirChatVoz: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/cu41_01_inicio.png'),
    );
  }, skip: !_generar);

  testWidgets('02 Chat inicial', (WidgetTester tester) async {
    _tamano(tester, const Size(390, 844));
    final ChatbotController ctrl = ChatbotController(
      api: ApiChatbotFalsa(),
      leerToken: () async => 'jwt',
    );
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      _app(ChatbotPage(controller: ctrl, clinica: _clinica)),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/cu41_02_chat_inicial.png'),
    );
  }, skip: !_generar);

  testWidgets('03 Conversación con tarjetas', (WidgetTester tester) async {
    _tamano(tester, const Size(390, 1200));
    final ApiChatbotFalsa api = ApiChatbotFalsa()
      ..respuesta = _respuestaConversacion();
    final ChatbotController ctrl = ChatbotController(
      api: api,
      leerToken: () async => 'jwt',
    );
    addTearDown(ctrl.dispose);
    await ctrl.enviar('Quiero una cita para la próxima semana.');
    api.respuesta = const RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Puedo ayudarte con otra consulta.',
      textoVoz: 'Puedo ayudarte con otra consulta.',
      tipo: TipoRespuestaChatbot.texto,
      tarjetas: <TarjetaChatbot>[],
    );

    await tester.pumpWidget(
      _app(
        ChatbotPage(
          controller: ctrl,
          clinica: _clinica,
          agendaService: _agendaConCita(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/cu41_03_conversacion.png'),
    );
  }, skip: !_generar);

  testWidgets('04 Asistente de voz', (WidgetTester tester) async {
    _tamano(tester, const Size(390, 844));
    final ApiChatbotFalsa api = ApiChatbotFalsa();
    final SttFalso stt = SttFalso();
    final TtsFalso tts = TtsFalso();
    final ChatbotController conversacion = ChatbotController(
      api: api,
      leerToken: () async => 'jwt',
    );
    final ChatVozController voz = ChatVozController(
      conversacion: conversacion,
      reconocimiento: stt,
      sintesis: tts,
      retrasoReintento: Duration.zero,
    );
    addTearDown(() {
      voz.dispose();
      conversacion.dispose();
    });

    await tester.pumpWidget(
      _app(
        ChatVozPage(
          conversacion: conversacion,
          clinica: _clinica,
          vozController: voz,
          pedirConsentimiento: false,
          iniciarAlAbrir: false,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await voz.activar();
    stt.parcial('Quiero agendar una cita para mañana.');
    await tester.pump(const Duration(milliseconds: 600));

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/cu41_04_voz.png'),
    );
  }, skip: !_generar);
}
