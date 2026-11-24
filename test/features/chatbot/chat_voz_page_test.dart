import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/core/session/sesion_clinica.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chat_voz_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/pages/chat_voz_page.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/widgets/esfera_voz.dart';

import 'soporte_chatbot.dart';

const ClinicaSesion _clinica = ClinicaSesion(
  codigo: 'CLINICA',
  nombre: 'Clínica Ficticia',
);

class _Banco {
  _Banco() {
    api.respuesta = RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Puedo ayudarte con tu cita.',
      textoVoz: 'Puedo ayudarte con tu cita.',
      tipo: TipoRespuestaChatbot.datos,
      tarjetas: <TarjetaChatbot>[TarjetaClinica(nombre: 'Clínica Ficticia')],
    );
    conversacion = ChatbotController(api: api, leerToken: () async => 'jwt');
    voz = ChatVozController(
      conversacion: conversacion,
      reconocimiento: stt,
      sintesis: tts,
      retrasoReintento: Duration.zero,
      separacionTrasTts: Duration.zero,
    );
  }

  final ApiChatbotFalsa api = ApiChatbotFalsa();
  final SttFalso stt = SttFalso();
  final TtsFalso tts = TtsFalso();
  late final ChatbotController conversacion;
  late final ChatVozController voz;

  Future<void> cerrar() async {
    voz.dispose();
    conversacion.dispose();
  }
}

Future<void> _frames(WidgetTester tester, [int veces = 5]) async {
  for (int i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  testWidgets('esfera responde a todos los estados sin excepciones', (
    tester,
  ) async {
    for (final EstadoVoz estado in EstadoVoz.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: EsferaVoz(estado: estado, nivelAudio: 0.4)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expect(tester.takeException(), isNull, reason: '$estado');
    }
  });

  testWidgets('esfera respeta reducción de movimiento', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          );
        },
        home: const Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: EsferaVoz(estado: EstadoVoz.escuchando, nivelAudio: 0.8),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pantalla de voz muestra estados y ciclo de turnos', (
    tester,
  ) async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatVozPage(
          conversacion: banco.conversacion,
          clinica: _clinica,
          vozController: banco.voz,
          pedirConsentimiento: false,
          iniciarAlAbrir: false,
        ),
      ),
    );
    await _frames(tester);

    expect(find.text('Asistente de voz'), findsOneWidget);
    expect(find.text('Clínica Ficticia'), findsOneWidget);
    expect(find.text('Listo para conversar'), findsOneWidget);
    expect(find.text('Volver al chat escrito'), findsOneWidget);
    expect(find.byType(EsferaVoz), findsOneWidget);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await _frames(tester, 8);

    expect(find.text('Te escucho...'), findsOneWidget);
    expect(banco.stt.iniciarLlamadas, 1);

    banco.stt.parcial('Quiero una cita');
    await _frames(tester);
    expect(find.text('Quiero una cita'), findsOneWidget);

    banco.stt.final_('Quiero una cita para mañana');
    await _frames(tester, 12);

    expect(find.text('El asistente está hablando'), findsOneWidget);
    expect(banco.tts.hablarLlamadas, 1);
    expect(find.textContaining('Puedo ayudarte'), findsWidgets);

    banco.tts.terminar();
    await _frames(tester, 10);
    expect(find.text('Te escucho...'), findsOneWidget);
    expect(banco.stt.iniciarLlamadas, 2);
  });

  testWidgets('consentimiento explica privacidad antes de abrir el micrófono', (
    tester,
  ) async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatVozPage(
          conversacion: banco.conversacion,
          clinica: _clinica,
          vozController: banco.voz,
          pedirConsentimiento: true,
          iniciarAlAbrir: true,
        ),
      ),
    );
    await _frames(tester, 8);

    expect(find.text('Conversar por voz'), findsOneWidget);
    expect(find.textContaining('No dictes contraseñas'), findsOneWidget);
    expect(
      find.textContaining(
        'otra autorización antes de usar el proveedor general',
      ),
      findsOneWidget,
    );
    expect(banco.stt.iniciarLlamadas, 0);

    await tester.tap(find.text('Activar voz'));
    await _frames(tester, 10);

    expect(find.text('Te escucho...'), findsOneWidget);
    expect(banco.stt.iniciarLlamadas, 1);
  });

  testWidgets('información privada no se lee y ofrece verla en el chat', (
    tester,
  ) async {
    final banco = _Banco();
    addTearDown(banco.cerrar);
    banco.api.respuesta = RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Tu cita es el 15 de diciembre.',
      textoVoz: 'Tu cita es el 15 de diciembre.',
      tipo: TipoRespuestaChatbot.datos,
      tarjetas: <TarjetaChatbot>[
        TarjetaCitasPropias(
          citas: <CitaPropiaChat>[
            CitaPropiaChat(
              id: 1,
              oftalmologoId: 1,
              fecha: DateTime(2026, 12, 15),
              horaInicio: '09:00:00',
              horaFin: '09:30:00',
              estado: 'PROGRAMADA',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ChatVozPage(
          conversacion: banco.conversacion,
          clinica: _clinica,
          vozController: banco.voz,
          pedirConsentimiento: false,
          iniciarAlAbrir: true,
        ),
      ),
    );
    await _frames(tester, 12);
    expect(banco.voz.estado, EstadoVoz.escuchando);

    banco.stt.final_('Mis citas');
    await _frames(tester, 12);

    expect(banco.tts.hablarLlamadas, 0);
    expect(find.textContaining('información privada'), findsWidgets);
    expect(find.textContaining('Ver respuesta'), findsOneWidget);
  });

  testWidgets('finalizar pide confirmación y no simula llamada', (
    tester,
  ) async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    await tester.pumpWidget(
      MaterialApp(
        home: ChatVozPage(
          conversacion: banco.conversacion,
          clinica: _clinica,
          vozController: banco.voz,
          pedirConsentimiento: false,
          iniciarAlAbrir: false,
        ),
      ),
    );
    await _frames(tester);

    await tester.tap(find.byIcon(Icons.stop_circle_outlined));
    await _frames(tester, 6);

    expect(find.text('¿Finalizar la conversación?'), findsOneWidget);
    expect(find.text('Continuar conversando'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Finalizar'));
    await _frames(tester, 8);

    expect(banco.voz.estado, EstadoVoz.finalizado);
    expect(find.text('Volver al chat escrito'), findsOneWidget);
  });

  testWidgets('pantalla estrecha y texto 200% no desborda', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final banco = _Banco();
    addTearDown(banco.cerrar);

    await tester.pumpWidget(
      MaterialApp(
        builder: (BuildContext context, Widget? child) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          );
        },
        home: ChatVozPage(
          conversacion: banco.conversacion,
          clinica: _clinica,
          vozController: banco.voz,
          pedirConsentimiento: false,
          iniciarAlAbrir: false,
        ),
      ),
    );
    await _frames(tester, 8);

    expect(tester.takeException(), isNull);
    expect(find.text('Asistente de voz'), findsOneWidget);
  });
}
