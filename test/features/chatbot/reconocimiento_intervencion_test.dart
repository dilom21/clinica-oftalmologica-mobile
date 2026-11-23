import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chat_voz_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/voz/reconocimiento_voz.dart';

import 'soporte_chatbot.dart';

/// Simula eventos del motor sin micrófono. El adaptador y el controlador son
/// reales; permite conservar callbacks por sesión para probar eventos tardíos.
class _Speech extends SpeechToText {
  _Speech() : super.withMethodChannel();
  bool disponible = false;
  bool activo = false;
  Duration? timeoutFinal;
  SpeechStatusListener? estado;
  final resultados = <SpeechResultListener>[];
  final opciones = <SpeechListenOptions>[];

  @override
  bool get isAvailable => disponible;
  @override
  bool get isListening => activo;
  @override
  Future<bool> get hasPermission async => true;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    debugLogging = false,
    Duration finalTimeout = SpeechToText.defaultFinalTimeout,
    List<SpeechConfigOption>? options,
  }) async {
    timeoutFinal = finalTimeout;
    estado = onStatus;
    disponible = true;
    return true;
  }

  @override
  Future<void> listen({
    SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    SpeechSoundLevelChange? onSoundLevelChange,
    cancelOnError = false,
    partialResults = true,
    onDevice = false,
    ListenMode listenMode = ListenMode.confirmation,
    sampleRate = 0,
    SpeechListenOptions? listenOptions,
  }) async {
    resultados.add(onResult!);
    opciones.add(listenOptions!);
    status('listening');
  }

  void status(String valor) {
    activo = valor == 'listening';
    estado?.call(valor);
  }

  void emitir(String texto, {bool final_ = false, int? sesion}) {
    if (final_ && sesion == null) activo = false;
    resultados[sesion ?? resultados.length - 1](
      SpeechRecognitionResult(<SpeechRecognitionWords>[
        SpeechRecognitionWords(texto, null, -1),
      ], final_ ? ResultType.finalResult.value : ResultType.partial.value),
    );
  }

  @override
  Future<void> stop() async {
    activo = false;
  }

  @override
  Future<void> cancel() async {
    activo = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const canal = MethodChannel('clinica_oftalmologica_mobile/cu41_voice');
  late _Speech speech;
  late SpeechToTextReconocimiento stt;
  late TtsFalso tts;
  late ApiChatbotFalsa api;
  late ChatbotController conversacion;
  late ChatVozController voz;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          canal,
          (_) async => <String, Object>{
            'sdk': 31,
            'onDeviceAvailable': false,
            'generalAvailable': true,
            'visibleServices': 2,
            'defaultServicePresent': true,
          },
        );
    speech = _Speech();
    stt = SpeechToTextReconocimiento(
      speech: speech,
      solicitarConsentimientoGeneral: () async => true,
    );
    tts = TtsFalso()..consultarStt = () => stt.escuchando;
    api = ApiChatbotFalsa()
      ..respuesta = const RespuestaChatbot(
        conversacionId: 'conv-1',
        respuesta: 'Respuesta de prueba',
        textoVoz: 'Respuesta de prueba',
        tipo: TipoRespuestaChatbot.texto,
        tarjetas: <TarjetaChatbot>[],
      );
    conversacion = ChatbotController(api: api, leerToken: () async => 'test');
    voz = ChatVozController(
      conversacion: conversacion,
      reconocimiento: stt,
      sintesis: tts,
      retrasoReintento: Duration.zero,
      separacionTrasTts: const Duration(milliseconds: 450),
    );
  });

  tearDown(() async {
    await voz.salir();
    voz.dispose();
    conversacion.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(canal, null);
  });

  const pregunta = '¿Qué oftalmólogos atienden en esta clínica?';
  const horarios =
      '¿Qué horarios tiene Salet Ejemplo para el 26 de noviembre de 2026?';

  testWidgets(
    'parcial qué, pausa breve y pregunta completa: un solo envío final',
    (tester) async {
      await voz.activar();
      expect(speech.timeoutFinal, Duration.zero);
      expect(speech.opciones.single.pauseFor, const Duration(seconds: 4));
      expect(speech.opciones.single.listenFor, const Duration(seconds: 45));
      expect(speech.opciones.single.onDevice, isFalse);
      speech.emitir('qué');
      await tester.pump(const Duration(milliseconds: 700));
      expect(api.enviarLlamadas, 0);
      speech.emitir('qué oftalmólogos');
      await tester.pump(const Duration(milliseconds: 800));
      speech.emitir(pregunta);
      expect(api.enviarLlamadas, 0);
      speech.emitir(pregunta, final_: true);
      speech.emitir(pregunta, final_: true);
      await tester.pump();
      expect(api.enviarLlamadas, 1);
      expect(conversacion.mensajes.first.texto, pregunta);
      expect(voz.estado, EstadoVoz.respondiendo);
    },
  );

  testWidgets('done antes del final no envía el parcial a los 250 ms', (
    tester,
  ) async {
    await voz.activar();
    speech.emitir('qué');
    speech.status('done');
    await tester.pump(const Duration(milliseconds: 600));
    expect(api.enviarLlamadas, 0);
    speech.emitir(pregunta, final_: true);
    await tester.pump();
    expect(api.enviarLlamadas, 1);
    expect(conversacion.mensajes.first.texto, pregunta);
  });

  testWidgets(
    'frase con nombre y fecha conserva todos los parciales sin enviar',
    (tester) async {
      await voz.activar();
      for (final parcial in <String>[
        'qué horarios',
        'qué horarios tiene Salet Ejemplo',
        'qué horarios tiene Salet Ejemplo para el 26 de noviembre',
        horarios,
      ]) {
        speech.emitir(parcial);
        await tester.pump(const Duration(milliseconds: 600));
        expect(api.enviarLlamadas, 0);
      }
      speech.emitir(horarios, final_: true);
      await tester.pump();
      expect(conversacion.mensajes.first.texto, horarios);
      expect(api.enviarLlamadas, 1);
    },
  );

  testWidgets(
    'sin final tras cierre no promueve ni siquiera un parcial largo',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta);
      speech.status('notListening');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(api.enviarLlamadas, 0);
      expect(voz.estado, EstadoVoz.pausado);
      expect(voz.aviso, contains('No se envió'));
      expect(speech.resultados, hasLength(1));
      speech.emitir(pregunta, final_: true);
      await tester.pump();
      expect(api.enviarLlamadas, 0);
    },
  );

  testWidgets('un cierre espurio con escucha activa no envía un parcial', (
    tester,
  ) async {
    await voz.activar();
    speech.emitir('qué');
    speech.estado?.call('done'); // Motor continúa escuchando.
    await tester.pump(const Duration(seconds: 3));
    expect(api.enviarLlamadas, 0);
    expect(voz.estado, EstadoVoz.escuchando);
    speech.emitir(pregunta, final_: true);
    await tester.pump();
    expect(api.enviarLlamadas, 1);
  });

  testWidgets('timeout de escucha no inventa un final ni reinicia en bucle', (
    tester,
  ) async {
    await voz.activar();
    speech.emitir('qué');
    await tester.pump(const Duration(seconds: 47));
    await tester.pump();
    expect(voz.estado, EstadoVoz.pausado);
    expect(api.enviarLlamadas, 0);
    expect(speech.resultados, hasLength(1));
  });

  testWidgets('final nativo qué aislado permite repetir sin enviarlo', (
    tester,
  ) async {
    await voz.activar();
    speech.emitir('qué', final_: true);
    await tester.pump();
    expect(voz.estado, EstadoVoz.pausado);
    expect(api.enviarLlamadas, 0);
    await voz.reanudar();
    speech.emitir(pregunta, final_: true);
    await tester.pump();
    expect(api.enviarLlamadas, 1);
  });

  testWidgets('Hola final legítimo de una palabra sí se envía', (tester) async {
    await voz.activar();
    speech.emitir('Hola', final_: true);
    await tester.pump();
    expect(api.enviarLlamadas, 1);
  });

  testWidgets(
    'TTS y su margen de salida preceden a un segundo turno con el mismo UUID',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta, final_: true);
      await tester.pump();
      expect(speech.resultados, hasLength(1));
      expect(tts.hablando, isTrue);
      tts.terminar();
      await tester.pump(const Duration(milliseconds: 449));
      expect(speech.resultados, hasLength(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(speech.resultados, hasLength(2));
      expect(voz.estado, EstadoVoz.escuchando);
      speech.emitir('Final tardío', final_: true, sesion: 0);
      await tester.pump();
      expect(api.enviarLlamadas, 1);
      speech.emitir(horarios, final_: true);
      await tester.pump();
      expect(api.enviarLlamadas, 2);
      expect(api.crearLlamadas, 1);
      expect(api.envios.last['modalidad'], 'voz');
      expect(api.envios.last['conversacion_id'], 'conv-1');
      expect(tts.sttEscuchandoAlHablar, isFalse);
    },
  );

  for (final segundoPlano in <bool>[false, true]) {
    testWidgets(
      'pausa durante separación TTS no abre otro turno ($segundoPlano)',
      (tester) async {
        await voz.activar();
        speech.emitir(pregunta, final_: true);
        await tester.pump();
        tts.terminar();
        await tester.pump(const Duration(milliseconds: 200));
        if (segundoPlano) {
          await voz.suspenderPorCicloDeVida();
          voz.reanudarCicloDeVida();
        } else {
          await voz.pausar();
        }
        await tester.pump(const Duration(seconds: 1));
        expect(speech.resultados, hasLength(1));
        expect(voz.estado, EstadoVoz.pausado);
      },
    );

    testWidgets(
      'pausa manual/segundo plano descarta el parcial y el final tardío ($segundoPlano)',
      (tester) async {
        await voz.activar();
        speech.emitir('qué');
        if (segundoPlano) {
          await voz.suspenderPorCicloDeVida();
          voz.reanudarCicloDeVida();
        } else {
          await voz.pausar();
        }
        speech.emitir(pregunta, final_: true, sesion: 0);
        await tester.pump(const Duration(seconds: 3));
        expect(api.enviarLlamadas, 0);
        expect(voz.estado, EstadoVoz.pausado);
        await voz.reanudar();
        speech.emitir(pregunta, final_: true, sesion: 0);
        expect(api.enviarLlamadas, 0);
        await voz.pausar();
      },
    );
  }
}
