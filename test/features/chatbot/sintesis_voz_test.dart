import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chat_voz_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/voz/sintesis_voz.dart';

import 'soporte_chatbot.dart';

/// Usa el adaptador real y la entrada de eventos Dart de flutter_tts, no
/// TtsFalso. Solo las operaciones nativas están simuladas, sin emitir audio.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  late FlutterTts plugin;
  late FlutterTtsSintesis tts;
  late SttFalso stt;
  late ChatbotController conversacion;
  late ChatVozController voz;
  late List<String> llamadas;
  Completer<Object?>? paradaPendiente;
  Completer<void>? solicitudParada;
  Completer<Object?>? idiomaPendiente;
  bool fallarParada = false;

  setUp(() {
    llamadas = <String>[];
    paradaPendiente = null;
    solicitudParada = null;
    idiomaPendiente = null;
    fallarParada = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          llamadas.add(call.method); // Nunca registrar call.arguments.
          switch (call.method) {
            case 'isLanguageAvailable':
              if (idiomaPendiente != null) return await idiomaPendiente!.future;
              return true;
            case 'isLanguageInstalled':
              return false;
            case 'stop':
              if (fallarParada) throw PlatformException(code: 'stop_failed');
              if (paradaPendiente != null) {
                solicitudParada?.complete();
                return await paradaPendiente!.future;
              }
              return 1;
            default:
              return 1;
          }
        });
    plugin = FlutterTts();
    tts = FlutterTtsSintesis(
      tts: plugin,
      limiteReproduccion: const Duration(seconds: 1),
    );
    stt = SttFalso()..consultarTts = () => tts.hablando;
    final api = ApiChatbotFalsa()
      ..respuesta = const RespuestaChatbot(
        conversacionId: 'conv-1',
        respuesta: 'Respuesta administrativa de prueba',
        textoVoz: 'Respuesta administrativa de prueba',
        tipo: TipoRespuestaChatbot.texto,
        tarjetas: <TarjetaChatbot>[],
      );
    conversacion = ChatbotController(api: api, leerToken: () async => 'test');
    voz = ChatVozController(
      conversacion: conversacion,
      reconocimiento: stt,
      sintesis: tts,
      retrasoReintento: Duration.zero,
      separacionTrasTts: Duration.zero,
    );
  });

  tearDown(() async {
    paradaPendiente = null;
    fallarParada = false;
    await tts.liberar();
    voz.dispose();
    conversacion.dispose();
    await Future<void>.delayed(Duration.zero);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> evento(String metodo) =>
      plugin.platformCallHandler(MethodCall(metodo, true));

  Future<void> flush() async {
    for (var i = 0; i < 15; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> responder() async {
    await voz.activar();
    stt.final_('Consulta administrativa de prueba');
    await flush();
    await evento('speak.onStart');
    expect(voz.estado, EstadoVoz.respondiendo);
    expect(stt.escuchando, isFalse);
    expect(tts.hablando, isTrue);
  }

  test(
    'regresión: onComplete real llega al controlador y reabre STT una vez',
    () async {
      await responder();
      // speak ya devolvió 1, pero eso solo es aceptación, no finalización.
      expect(stt.iniciarLlamadas, 1);
      await voz.escucharRespuesta();
      expect(llamadas.where((m) => m == 'speak'), hasLength(1));

      await evento('speak.onComplete');
      await evento('speak.onComplete');
      await flush();
      expect(voz.estado, EstadoVoz.escuchando);
      expect(stt.iniciarLlamadas, 2);
      expect(stt.ttsHablandoAlIniciar, isFalse);
      expect(tts.hablando, isFalse);

      // Segundo turno, misma conversación y sin intervención manual.
      stt.final_('Otra consulta administrativa');
      await flush();
      await evento('speak.onComplete');
      await flush();
      expect(voz.estado, EstadoVoz.escuchando);
      expect(stt.iniciarLlamadas, 3);
      expect(conversacion.conversacionId, 'conv-1');
    },
  );

  for (final accion in <String>[
    'pausar',
    'segundo plano',
    'salir',
    'finalizar',
  ]) {
    test('fin tardío tras $accion no reactiva el micrófono', () async {
      await responder();
      switch (accion) {
        case 'pausar':
          await voz.pausar();
        case 'segundo plano':
          await voz.suspenderPorCicloDeVida();
          voz.reanudarCicloDeVida();
        case 'salir':
          await voz.salir();
        case 'finalizar':
          await voz.finalizarConversacion();
      }
      await evento('speak.onComplete');
      await evento('speak.onStart');
      await flush();
      expect(voz.estado, isNot(EstadoVoz.respondiendo));
      expect(stt.iniciarLlamadas, 1);
      expect(tts.hablando, isFalse);
    });
  }

  for (final terminal in <String>['speak.onCancel', 'speak.onError']) {
    test('$terminal detiene audio y pausa sin reinicio automático', () async {
      await responder();
      final anteriores = llamadas.where((m) => m == 'stop').length;
      await evento(terminal);
      await evento('speak.onComplete');
      await flush();
      expect(voz.estado, EstadoVoz.pausado);
      expect(stt.iniciarLlamadas, 1);
      expect(tts.hablando, isFalse);
      expect(llamadas.where((m) => m == 'stop').length, anteriores + 1);
    });
  }

  test(
    'callback ausente: stop confirmado y pausa, nunca onFin artificial',
    () async {
      await responder();
      paradaPendiente = Completer<Object?>();
      solicitudParada = Completer<void>();
      await solicitudParada!.future.timeout(const Duration(seconds: 5));
      expect(voz.estado, EstadoVoz.respondiendo);
      expect(tts.hablando, isTrue);
      expect(stt.iniciarLlamadas, 1);
      paradaPendiente!.complete(1);
      await flush();
      paradaPendiente = null;
      solicitudParada = null;
      expect(voz.estado, EstadoVoz.pausado);
      expect(tts.hablando, isFalse);
      expect(stt.iniciarLlamadas, 1);
    },
  );

  test('si stop falla, continuar no puede abrir el micrófono', () async {
    await responder();
    fallarParada = true;
    await evento('speak.onError');
    await flush();
    expect(voz.estado, EstadoVoz.pausado);
    expect(tts.hablando, isTrue);
    await voz.reanudar();
    expect(voz.estado, EstadoVoz.pausado);
    expect(stt.iniciarLlamadas, 1);
  });

  test('texto vacío finaliza sin enviar speak ni dejar audio activo', () async {
    var fines = 0;
    await tts.hablar(
      '  ',
      onInicio: () {},
      onFin: () => fines++,
      onError: (_) => fail('No debe fallar'),
    );
    expect(fines, 1);
    expect(tts.hablando, isFalse);
    expect(llamadas, isNot(contains('speak')));
  });

  test(
    'cancelar durante inicialización no inicia reproducción tardía',
    () async {
      idiomaPendiente = Completer<Object?>();
      final pendiente = tts.hablar(
        'Prueba',
        onInicio: () => fail('Inicio tardío'),
        onFin: () => fail('Fin tardío'),
        onError: (_) => fail('Error tardío'),
      );
      await flush();
      await tts.detener();
      idiomaPendiente!.complete(true);
      await pendiente;
      expect(llamadas, isNot(contains('speak')));
      expect(tts.hablando, isFalse);
    },
  );

  test('respuesta vacía pausa el controlador sin iniciar TTS', () async {
    await voz.reproducirMensaje(
      MensajeChat(
        id: 'empty',
        rol: RolMensajeChat.asistente,
        texto: '',
        hora: DateTime(2026),
      ),
    );
    expect(voz.estado, EstadoVoz.pausado);
    expect(llamadas, isNot(contains('speak')));
    expect(stt.iniciarLlamadas, 0);
  });
}
