import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chat_voz_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/pages/chat_voz_page.dart';
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
  int inicializaciones = 0;
  Completer<void>? inicializacionPendiente;
  Completer<void>? inicioPendiente;
  Completer<void>? cancelacionPendiente;
  bool cancelacionFalla = false;
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
    inicializaciones++;
    // Semántica REAL 7.5.0: initialize no sustituye listeners tras el éxito.
    if (disponible) return true;
    if (inicializacionPendiente != null) {
      await inicializacionPendiente!.future;
    }
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
    if (inicioPendiente != null) await inicioPendiente!.future;
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
    if (cancelacionPendiente != null) await cancelacionPendiente!.future;
    if (cancelacionFalla) throw StateError('native_cancel_failed');
    status('notListening');
    status('done');
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

  const incompleta = 'qué horarios tiene Salem ejemplo para el 26';
  Future<void> reproducirRedmi(WidgetTester tester) async {
    if (voz.estado != EstadoVoz.escuchando) await voz.activar();
    // 16:50:34–37: hipótesis sucesivas, no corroboración de la última ni score.
    for (final parcial in <String>[
      'qué',
      'qué horarios',
      'qué horarios tiene',
      'qué horarios tiene Salem',
      'qué horarios tiene Salem ejemplo',
      incompleta,
    ]) {
      speech.emitir(parcial);
      await tester.pump(const Duration(milliseconds: 600));
    }
    await tester.pump(const Duration(milliseconds: 3400)); // 16:50:41
    speech.status('notListening');
    speech.status('done');
    await tester.pump(const Duration(seconds: 2)); // 16:50:43, sin final
    await tester.pump(const Duration(milliseconds: 500)); // margen de stop
    await tester.pump();
  }

  testWidgets(
    'Redmi: revisar/editar no envía; confirmar conserva UUID y evita duplicados',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta, final_: true);
      await tester.pump();
      tts.terminar();
      await tester.pump(const Duration(milliseconds: 450));
      await reproducirRedmi(tester);
      expect(voz.estado, EstadoVoz.revisandoTranscripcion);
      expect(voz.transcripcionPendiente, incompleta);
      expect(voz.puedeConfirmarTranscripcion, isTrue);
      expect(api.enviarLlamadas, 1);
      expect(speech.activo, isFalse);
      final revision = voz.revisionTranscripcion;
      speech.emitir('resultado tardío', final_: true, sesion: 1);
      final envio = voz.confirmarTranscripcion(horarios, revision: revision);
      final duplicado = voz.confirmarTranscripcion(
        incompleta,
        revision: revision,
      );
      await envio;
      await duplicado;
      await tester.pump();
      expect(api.enviarLlamadas, 2);
      expect(api.crearLlamadas, 1);
      expect(
        conversacion.mensajes
            .where((m) => m.rol == RolMensajeChat.paciente)
            .last
            .texto,
        horarios,
      );
      expect(api.envios.last['conversacion_id'], 'conv-1');
      expect(api.envios.last['modalidad'], 'voz');
      expect(tts.sttEscuchandoAlHablar, isFalse);
      tts.terminar();
      await tester.pump(const Duration(milliseconds: 450));
      expect(voz.estado, EstadoVoz.escuchando);
      await voz.pausar();
    },
  );

  testWidgets(
    'confirmar sin editar envía exactamente lo autorizado, sin completar datos',
    (tester) async {
      await reproducirRedmi(tester);
      final revision = voz.revisionTranscripcion;
      await voz.confirmarTranscripcion('   ', revision: revision);
      expect(api.enviarLlamadas, 0);
      expect(voz.estado, EstadoVoz.revisandoTranscripcion);
      await voz.confirmarTranscripcion(incompleta, revision: revision);
      await tester.pump();
      expect(api.enviarLlamadas, 1);
      expect(conversacion.mensajes.first.texto, incompleta);
    },
  );

  testWidgets(
    'repetir invalida editor y resultados antiguos sin abrir capturas paralelas',
    (tester) async {
      await reproducirRedmi(tester);
      final revision = voz.revisionTranscripcion;
      final repetir = voz.repetirIntervencion(revision: revision);
      final duplicado = voz.repetirIntervencion(revision: revision);
      await repetir;
      await duplicado;
      expect(voz.estado, EstadoVoz.escuchando);
      expect(speech.resultados, hasLength(2));
      speech.emitir('callback anterior', final_: true, sesion: 0);
      await voz.confirmarTranscripcion(incompleta, revision: revision);
      expect(api.enviarLlamadas, 0);
      await reproducirRedmi(tester);
      expect(voz.estado, EstadoVoz.revisandoTranscripcion);
      await voz.confirmarTranscripcion(incompleta, revision: revision);
      expect(api.enviarLlamadas, 0); // Tampoco aprueba el siguiente editor.
      await voz.confirmarTranscripcion(
        horarios,
        revision: voz.revisionTranscripcion,
      );
      await tester.pump();
      expect(api.enviarLlamadas, 1);
    },
  );

  for (final accion in [
    'pausa',
    'segundo plano',
    'finalizar',
    'salir',
    'cambiar',
  ]) {
    testWidgets('revisión/edición se invalida al $accion', (tester) async {
      await reproducirRedmi(tester);
      final revision = voz.revisionTranscripcion;
      switch (accion) {
        case 'pausa':
          await voz.pausar();
        case 'segundo plano':
          await voz.suspenderPorCicloDeVida();
          voz.reanudarCicloDeVida();
        case 'finalizar':
          await voz.finalizarConversacion();
        case 'salir':
          await voz.salir();
        case 'cambiar':
          await conversacion.nuevaConversacion();
      }
      await voz.confirmarTranscripcion(horarios, revision: revision);
      await voz.repetirIntervencion(revision: revision);
      speech.emitir(horarios, final_: true, sesion: 0);
      await tester.pump();
      expect(api.enviarLlamadas, 0);
      expect(voz.transcripcionPendiente, isNull);
      expect(speech.resultados, hasLength(1));
      expect(speech.activo, isFalse);
    });
  }

  testWidgets(
    'cancel pendiente bloquea confirmar/repetir y pausa invalida su continuación',
    (tester) async {
      speech.cancelacionPendiente = Completer<void>();
      await reproducirRedmi(tester);
      final revision = voz.revisionTranscripcion;
      expect(voz.puedeConfirmarTranscripcion, isFalse);
      await voz.confirmarTranscripcion(horarios, revision: revision);
      await voz.repetirIntervencion(revision: revision);
      final pausa = voz.pausar();
      speech.cancelacionPendiente!.complete();
      await pausa;
      await tester.pump();
      expect(voz.estado, EstadoVoz.pausado);
      expect(api.enviarLlamadas, 0);
      expect(speech.resultados, hasLength(1));
    },
  );

  testWidgets('pausa entre confirmar y cierre impide el envío', (tester) async {
    await reproducirRedmi(tester);
    final revision = voz.revisionTranscripcion;
    final envio = voz.confirmarTranscripcion(horarios, revision: revision);
    final pausa = voz.pausar();
    await envio;
    await pausa;
    await tester.pump();
    expect(api.enviarLlamadas, 0);
  });

  testWidgets(
    'fallo nativo de cancel no habilita confirmar aunque ya no haya propietario',
    (tester) async {
      speech.cancelacionFalla = true;
      await reproducirRedmi(tester);
      expect(voz.puedeConfirmarTranscripcion, isFalse);
      expect(voz.estado, EstadoVoz.pausado);
      expect(stt.cierreConfirmado, isFalse);
      await voz.confirmarTranscripcion(
        horarios,
        revision: voz.revisionTranscripcion,
      );
      expect(api.enviarLlamadas, 0);
      speech.cancelacionFalla = false;
    },
  );

  testWidgets(
    'diagnóstico de recuperación usa bandas y evidencia, nunca transcripción',
    (tester) async {
      final trazas = <String>[];
      final anterior = debugPrint;
      debugPrint = (String? mensaje, {int? wrapWidth}) {
        if (mensaje != null) trazas.add(mensaje);
      };
      try {
        await reproducirRedmi(tester);
        final rechazo = trazas.singleWhere(
          (m) => m.contains('recovery rejected'),
        );
        expect(rechazo, contains('stable=true'));
        expect(rechazo, contains('corroborated=false'));
        expect(rechazo, contains('confidenceAvailable=false'));
        expect(rechazo, contains('confidenceBand=unavailable'));
        expect(rechazo, contains('closureConfirmed=true'));
        expect(trazas.join(), isNot(contains('Salem')));
        expect(trazas.join(), isNot(contains('para el 26')));
        expect(trazas.join(), isNot(contains(incompleta)));
      } finally {
        debugPrint = anterior;
      }
    },
  );

  testWidgets(
    'confirmar no detiene la captura de otra pantalla ni envía con STT activo',
    (tester) async {
      await reproducirRedmi(tester);
      final otra = SpeechToTextReconocimiento(
        speech: speech,
        solicitarConsentimientoGeneral: () async => true,
      );
      expect(
        await otra.iniciar(
          onParcial: (_) {},
          onFinal: (_) {},
          onError: (_) {},
          onSilencio: () {},
        ),
        isTrue,
      );
      await voz.confirmarTranscripcion(
        horarios,
        revision: voz.revisionTranscripcion,
      );
      expect(api.enviarLlamadas, 0);
      expect(speech.activo, isTrue);
      expect(speech.resultados, hasLength(2));
      await otra.liberar();
    },
  );

  for (final accion in ['enviar', 'repetir']) {
    testWidgets('editor en pantalla permite editar, bloquear vacío y $accion', (
      tester,
    ) async {
      if (accion == 'repetir') {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(accion == 'repetir' ? 2 : 1),
            ),
            child: child!,
          ),
          home: ChatVozPage(
            conversacion: conversacion,
            vozController: voz,
            pedirConsentimiento: false,
            iniciarAlAbrir: false,
          ),
        ),
      );
      await tester.pump();
      await reproducirRedmi(tester);
      final campo = find.byKey(const ValueKey('revision-transcripcion'));
      expect(campo, findsOneWidget);
      expect(tester.widget<TextField>(campo).controller!.text, incompleta);
      final revision = voz.revisionTranscripcion;
      await tester.ensureVisible(campo);
      await tester.enterText(campo, '  ');
      await tester.pump();
      final boton = find.widgetWithText(FilledButton, 'Confirmar y enviar');
      expect(tester.widget<FilledButton>(boton).onPressed, isNull);
      await tester.enterText(campo, horarios);
      await tester.pump();
      speech.emitir('final antiguo', final_: true, sesion: 0);
      await tester.pump();
      expect(tester.widget<TextField>(campo).controller!.text, horarios);
      expect(api.enviarLlamadas, 0);
      expect(speech.activo, isFalse);
      final accionUi = find.text(
        accion == 'enviar' ? 'Confirmar y enviar' : 'Repetir intervención',
      );
      await tester.ensureVisible(accionUi);
      await tester.tap(accionUi);
      await tester.pump();
      expect(api.enviarLlamadas, accion == 'enviar' ? 1 : 0);
      expect(
        voz.estado,
        accion == 'enviar' ? EstadoVoz.respondiendo : EstadoVoz.escuchando,
      );
      speech.emitir('tardío', final_: true, sesion: 0);
      await voz.confirmarTranscripcion(incompleta, revision: revision);
      await tester.pump();
      expect(api.enviarLlamadas, accion == 'enviar' ? 1 : 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'regresión: 21 pantallas nuevas reciben los listeners fijados del plugin',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta, final_: true);
      await tester.pump();
      expect(api.enviarLlamadas, 1);
      await voz.salir();
      final primerEstado = speech.estado;
      final primerError = speech.error;
      for (var i = 0; i < 20; i++) {
        var finales = 0;
        var errores = 0;
        final nuevo = SpeechToTextReconocimiento(
          speech: speech,
          solicitarConsentimientoGeneral: () async => true,
        );
        expect(
          await nuevo.iniciar(
            onParcial: (_) {},
            onFinal: (_) => finales++,
            onError: (_) => errores++,
            onSilencio: () {},
          ),
          isTrue,
        );
        expect(identical(speech.estado, primerEstado), isTrue);
        expect(identical(speech.error, primerError), isTrue);
        speech.emitir(pregunta);
        speech.emitir(pregunta);
        speech.status('notListening');
        speech.status('done');
        // Callback de resultados de la primera pantalla no pertenece a esta.
        speech.emitir('resultado antiguo', final_: true, sesion: 0);
        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(milliseconds: 500));
        expect(finales, 1, reason: 'pantalla ${i + 2}');
        expect(api.enviarLlamadas, 1);
        await nuevo.detener();
        expect(
          await nuevo.iniciar(
            onParcial: (_) {},
            onFinal: (_) => finales++,
            onError: (_) => errores++,
            onSilencio: () {},
          ),
          isTrue,
        );
        speech.error?.call(SpeechRecognitionError('error_audio', true));
        expect(errores, 1);
        await nuevo.liberar();
      }
      expect(speech.inicializaciones, 1);
    },
  );

  testWidgets('una segunda pantalla no roba la captura ni puede detenerla', (
    tester,
  ) async {
    await voz.activar();
    final segunda = SpeechToTextReconocimiento(speech: speech);
    String? error;
    expect(
      await segunda.iniciar(
        onParcial: (_) {},
        onFinal: (_) {},
        onError: (e) => error = e,
        onSilencio: () {},
      ),
      isFalse,
    );
    expect(error, 'reconocimiento_ocupado');
    await segunda.liberar();
    expect(speech.activo, isTrue);
    speech.emitir(pregunta, final_: true);
    await tester.pump();
    expect(api.enviarLlamadas, 1);
  });

  testWidgets(
    'reabrir espera cancel pendiente; liberar antiguo no toca nuevo',
    (tester) async {
      await voz.activar();
      speech.cancelacionPendiente = Completer<void>();
      final salida = stt.liberar();
      final nueva = SpeechToTextReconocimiento(
        speech: speech,
        solicitarConsentimientoGeneral: () async => true,
      );
      var finales = 0;
      final inicio = nueva.iniciar(
        onParcial: (_) {},
        onFinal: (_) => finales++,
        onError: (_) {},
        onSilencio: () {},
      );
      await tester.pump();
      expect(speech.resultados, hasLength(1));
      speech.cancelacionPendiente!.complete();
      await salida;
      expect(await inicio, isTrue);
      await stt.liberar();
      expect(speech.activo, isTrue);
      speech.status('done');
      speech.emitir(pregunta, final_: true);
      await tester.pump();
      expect(finales, 1);
      await nueva.liberar();
    },
  );

  for (final accion in ['pausa', 'finalizar', 'segundo plano']) {
    testWidgets('$accion durante listen pendiente no deja micrófono abierto', (
      tester,
    ) async {
      speech.inicioPendiente = Completer<void>();
      final activacion = voz.activar();
      await tester.pump();
      final cierre = switch (accion) {
        'pausa' => voz.pausar(),
        'finalizar' => voz.finalizarConversacion(),
        _ => voz.suspenderPorCicloDeVida(),
      };
      speech.inicioPendiente!.complete();
      await activacion;
      await cierre;
      speech.emitir(pregunta, final_: true, sesion: 0);
      voz.reanudarCicloDeVida();
      await tester.pump();
      expect(speech.activo, isFalse);
      expect(api.enviarLlamadas, 0);
      expect(speech.resultados, hasLength(1));
    });
  }

  testWidgets('consentimiento pendiente de pantalla destruida no sobrevive', (
    tester,
  ) async {
    final permiso = Completer<bool>();
    final antigua = SpeechToTextReconocimiento(
      speech: speech,
      solicitarConsentimientoGeneral: () => permiso.future,
    );
    final inicio = antigua.iniciar(
      onParcial: (_) {},
      onFinal: (_) {},
      onError: (_) => fail('callback destruido'),
      onSilencio: () {},
    );
    await tester.pump();
    await antigua.liberar();
    permiso.complete(true);
    expect(await inicio, isFalse);
    expect(antigua.solicitarConsentimientoGeneral, isNull);
    var solicitudes = 0;
    final nueva = SpeechToTextReconocimiento(
      speech: speech,
      solicitarConsentimientoGeneral: () async {
        solicitudes++;
        return false;
      },
    );
    expect(
      await nueva.iniciar(
        onParcial: (_) {},
        onFinal: (_) {},
        onError: (_) {},
        onSilencio: () {},
      ),
      isFalse,
    );
    expect(solicitudes, 1);
    expect(speech.resultados, isEmpty);
    await nueva.liberar();
  });

  for (final accion in ['pausa', 'finalizar', 'segundo plano']) {
    testWidgets(
      '$accion durante initialize no continúa la activación antigua',
      (tester) async {
        speech.inicializacionPendiente = Completer<void>();
        final activacion = voz.activar();
        await tester.pump();
        switch (accion) {
          case 'pausa':
            await voz.pausar();
          case 'finalizar':
            await voz.finalizarConversacion();
          default:
            await voz.suspenderPorCicloDeVida();
            voz.reanudarCicloDeVida();
        }
        speech.inicializacionPendiente!.complete();
        await activacion;
        expect(speech.resultados, isEmpty);
        expect(api.enviarLlamadas, 0);
      },
    );
  }

  testWidgets(
    'stop antiguo pendiente termina antes de escuchar en otra pantalla',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta, confianza: 0.95);
      speech.status('notListening');
      speech.paradaPendiente = Completer<void>();
      await tester.pump(const Duration(seconds: 2));
      final cierre = stt.liberar();
      final nueva = SpeechToTextReconocimiento(
        speech: speech,
        solicitarConsentimientoGeneral: () async => true,
      );
      final inicio = nueva.iniciar(
        onParcial: (_) {},
        onFinal: (_) {},
        onError: (_) {},
        onSilencio: () {},
      );
      await tester.pump();
      expect(speech.resultados, hasLength(1));
      speech.paradaPendiente!.complete();
      await cierre;
      expect(await inicio, isTrue);
      await tester.pump(const Duration(milliseconds: 500));
      expect(speech.activo, isTrue);
      expect(api.enviarLlamadas, 0);
      await nueva.liberar();
    },
  );

  testWidgets(
    'cancelar revoca el consentimiento incluso en el mismo adaptador',
    (tester) async {
      var solicitudes = 0;
      stt.solicitarConsentimientoGeneral = () async {
        solicitudes++;
        return true;
      };
      await voz.activar();
      expect(solicitudes, 1);
      await voz.pausar();
      await voz.reanudar();
      expect(solicitudes, 2);
      await voz.salir();
    },
  );

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
    'un parcial sin confianza ni corroboración ofrece revisión, no decide por longitud',
    (tester) async {
      await voz.activar();
      speech.emitir(pregunta);
      speech.status('notListening');
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      expect(api.enviarLlamadas, 0);
      expect(voz.estado, EstadoVoz.revisandoTranscripcion);
      expect(voz.textoSubtitulo, contains('No se envió'));
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
    expect(voz.estado, EstadoVoz.revisandoTranscripcion);
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
        expect(voz.transcripcionPendiente, isNull);
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
      expect(voz.estado, EstadoVoz.revisandoTranscripcion);
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
    expect(voz.estado, EstadoVoz.revisandoTranscripcion);
    expect(voz.textoSubtitulo, contains('repite'));
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
    'done con isListening atascado tiene comprobaciones y termina en revisión',
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
      expect(voz.estado, EstadoVoz.revisandoTranscripcion);
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
      expect(voz.estado, EstadoVoz.revisandoTranscripcion);
      expect(api.enviarLlamadas, 0);
    },
  );

  testWidgets('stop que no responde deja revisión bloqueada hasta el cierre', (
    tester,
  ) async {
    await voz.activar();
    speech.emitir(pregunta, confianza: 0.95);
    speech.status('notListening');
    speech.paradaPendiente = Completer<void>();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 3));
    expect(api.enviarLlamadas, 0);
    expect(voz.estado, EstadoVoz.revisandoTranscripcion);
    expect(voz.puedeConfirmarTranscripcion, isFalse);
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
        expect(voz.transcripcionPendiente, isNull);
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
