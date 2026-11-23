import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
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
  SpeechErrorListener? error;
  int paradas = 0;
  bool detenerCierra = true;
  Completer<void>? paradaPendiente;
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
    error = onError;
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

  void emitir(
    String texto, {
    bool final_ = false,
    int? sesion,
    double confianza = -1,
  }) {
    if (final_ && sesion == null) activo = false;
    resultados[sesion ?? resultados.length - 1](
      SpeechRecognitionResult(<SpeechRecognitionWords>[
        SpeechRecognitionWords(texto, null, confianza),
      ], final_ ? ResultType.finalResult.value : ResultType.partial.value),
    );
  }

  void noMatch() {
    activo = false;
    error?.call(SpeechRecognitionError('error_no_match', true));
  }

  @override
  Future<void> stop() async {
    paradas++;
    if (paradaPendiente != null) await paradaPendiente!.future;
    if (detenerCierra) activo = false;
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
    'un parcial sin confianza ni corroboración solicita repetir, no decide por longitud',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta);
      speech.status('notListening');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
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
    await tester.pump(const Duration(milliseconds: 500));
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

  for (final noMatch in <bool>[false, true]) {
    testWidgets(
      'pregunta parcial estable y confiable se recupera tras cierre (noMatch=$noMatch)',
      (tester) async {
        await voz.activar();
        speech.emitir('qué');
        await tester.pump(const Duration(milliseconds: 300));
        speech.emitir('qué oftalmólogos');
        await tester.pump(const Duration(milliseconds: 300));
        speech.emitir(pregunta, confianza: 0.92);
        if (noMatch) {
          speech.noMatch();
        } else {
          speech.status('notListening');
        }
        await tester.pump(const Duration(seconds: 2));
        expect(api.enviarLlamadas, 0); // Margen adicional para final nativo.
        await tester.pump(const Duration(milliseconds: 500));
        expect(api.enviarLlamadas, 1);
        expect(conversacion.mensajes.first.texto, pregunta);
        expect(voz.estado, EstadoVoz.respondiendo);
        speech.emitir('Final tardío de otra hipótesis', final_: true);
        await tester.pump();
        expect(api.enviarLlamadas, 1);
      },
    );
  }

  testWidgets(
    'sin score, dos hipótesis iguales y estables sí permiten recuperación',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta);
      await tester.pump(const Duration(milliseconds: 600));
      speech.emitir(pregunta);
      speech.status('notListening');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.enviarLlamadas, 1);
    },
  );

  testWidgets(
    'ni repetición ni score alto convierten qué aislado en una consulta',
    (tester) async {
      await voz.activar();
      speech.emitir('qué', confianza: 0.95);
      speech.emitir('qué', confianza: 0.95);
      speech.noMatch();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.enviarLlamadas, 0);
      expect(voz.estado, EstadoVoz.pausado);
    },
  );

  testWidgets(
    'el monitor detecta isListening=false posterior a done sin otro status',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta, confianza: 0.95);
      speech.estado?.call('done');
      await tester.pump(const Duration(seconds: 2));
      expect(api.enviarLlamadas, 0);
      speech.activo = false;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.enviarLlamadas, 1);
    },
  );

  testWidgets('la confianza baja no se compensa con repetición o longitud', (
    tester,
  ) async {
    await voz.activar();
    speech.emitir(horarios, confianza: 0.3);
    speech.emitir(horarios, confianza: 0.3);
    speech.noMatch();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.enviarLlamadas, 0);
    expect(voz.estado, EstadoVoz.pausado);
    expect(voz.aviso, contains('repite'));
  });

  testWidgets(
    'final nativo durante stop tiene prioridad sobre un parcial recuperable',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta, confianza: 0.95);
      speech.status('notListening');
      await tester.pump(const Duration(seconds: 2));
      speech.emitir(horarios, final_: true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.enviarLlamadas, 1);
      expect(conversacion.mensajes.first.texto, horarios);
    },
  );

  testWidgets(
    'done con isListening atascado tiene comprobaciones y termina en pausa',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta, confianza: 0.95);
      speech.estado?.call('done');
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(speech.paradas, greaterThan(0));
      expect(voz.estado, EstadoVoz.pausado);
      expect(api.enviarLlamadas, 0);
    },
  );

  testWidgets(
    'si ni stop confirma cierre no se recupera aunque haya confianza alta',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta, confianza: 0.95);
      speech.status('notListening');
      await tester.pump(const Duration(seconds: 2));
      speech.activo =
          true; // El proveedor contradice la notificación de cierre.
      await tester.pump(const Duration(milliseconds: 500));
      expect(voz.estado, EstadoVoz.pausado);
      expect(api.enviarLlamadas, 0);
    },
  );

  testWidgets('stop que no responde tiene timeout y deja pausa explicada', (
    tester,
  ) async {
    await voz.activar();
    speech.emitir(pregunta, confianza: 0.95);
    speech.status('notListening');
    speech.paradaPendiente = Completer<void>();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    expect(api.enviarLlamadas, 0);
    expect(voz.estado, EstadoVoz.pausado);
    expect(voz.aviso, isNotNull);
    speech.paradaPendiente!.complete();
    await tester.pump();
  });

  testWidgets(
    'sin voz hay un reintento acotado y luego pausa, nunca una consulta vacía',
    (tester) async {
      await voz.activar();
      for (var i = 0; i < 2; i++) {
        speech.status('notListening');
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump();
      }
      expect(api.enviarLlamadas, 0);
      expect(voz.estado, EstadoVoz.pausado);
      expect(speech.resultados, hasLength(2));
    },
  );

  testWidgets(
    'Hola parcial estable puede recuperarse sin exigir varias palabras',
    (tester) async {
      await voz.activar();
      speech.emitir('Hola', confianza: 0.95);
      speech.status('notListening');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.enviarLlamadas, 1);
    },
  );

  testWidgets(
    'tres turnos recuperados con TTS mantienen UUID y no duplican envíos',
    (tester) async {
      await voz.activar();
      for (var i = 0; i < 3; i++) {
        speech.emitir(i == 0 ? pregunta : horarios, confianza: 0.95);
        speech.noMatch();
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 500));
        expect(api.enviarLlamadas, i + 1);
        expect(tts.hablando, isTrue);
        expect(speech.activo, isFalse);
        tts.terminar();
        await tester.pump(const Duration(milliseconds: 450));
        expect(voz.estado, EstadoVoz.escuchando);
      }
      expect(api.crearLlamadas, 1);
      expect(
        api.envios.every(
          (e) => e['conversacion_id'] == 'conv-1' && e['modalidad'] == 'voz',
        ),
        isTrue,
      );
      await voz.pausar();
    },
  );

  for (final accion in <String>['pausa', 'segundo plano', 'finalizar']) {
    testWidgets('recuperación pendiente se invalida al $accion', (
      tester,
    ) async {
      await voz.activar();
      speech.emitir(pregunta, confianza: 0.95);
      speech.status('notListening');
      await tester.pump(const Duration(seconds: 2));
      switch (accion) {
        case 'pausa':
          await voz.pausar();
        case 'segundo plano':
          await voz.suspenderPorCicloDeVida();
          voz.reanudarCicloDeVida();
        case 'finalizar':
          await voz.finalizarConversacion();
      }
      speech.emitir(pregunta, final_: true, sesion: 0);
      await tester.pump(const Duration(seconds: 1));
      expect(api.enviarLlamadas, 0);
      expect(speech.resultados, hasLength(1));
    });
  }

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
