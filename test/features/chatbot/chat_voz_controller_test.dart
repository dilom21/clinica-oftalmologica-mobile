import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chat_voz_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/voz/reconocimiento_voz.dart';

import 'soporte_chatbot.dart';

class _Banco {
  _Banco({
    EstadoPermisoVoz permiso = EstadoPermisoVoz.concedido,
    bool iniciarStt = true,
    int maxSilencios = 2,
    int maxErrores = 2,
    Duration separacionTrasTts = Duration.zero,
  }) {
    api.respuesta = const RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Respuesta pública',
      textoVoz: 'Respuesta pública hablada',
      tipo: TipoRespuestaChatbot.datos,
      tarjetas: <TarjetaChatbot>[],
    );
    stt
      ..permiso = permiso
      ..iniciarOk = iniciarStt
      ..consultarTts = () => tts.hablando;
    tts.consultarStt = () => stt.escuchando;
    conversacion = ChatbotController(api: api, leerToken: () async => 'jwt');
    voz = ChatVozController(
      conversacion: conversacion,
      reconocimiento: stt,
      sintesis: tts,
      maxSilencios: maxSilencios,
      maxErrores: maxErrores,
      retrasoReintento: Duration.zero,
      separacionTrasTts: separacionTrasTts,
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

/// Deja correr las microtareas encadenadas de la máquina de estados.
Future<void> _flush() async {
  for (int i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('permiso denegado deshabilita la voz y permite texto', () async {
    final banco = _Banco(permiso: EstadoPermisoVoz.denegado);
    addTearDown(banco.cerrar);

    await banco.voz.activar();

    expect(banco.voz.estado, EstadoVoz.noDisponible);
    expect(banco.voz.mensajeError, contains('permiso'));
    expect(banco.stt.iniciarLlamadas, 0);
  });

  test(
    'recupera la activación si el permiso se concede en el siguiente intento',
    () async {
      final banco = _Banco(permiso: EstadoPermisoVoz.denegado);
      addTearDown(banco.cerrar);

      await banco.voz.activar();
      expect(banco.voz.estado, EstadoVoz.noDisponible);
      banco.stt.permiso = EstadoPermisoVoz.concedido;

      await banco.voz.reanudar();

      expect(banco.voz.estado, EstadoVoz.escuchando);
      expect(banco.stt.iniciarLlamadas, 1);
    },
  );

  test('sin reconocimiento local no abre el micrófono', () async {
    final banco = _Banco(permiso: EstadoPermisoVoz.noDisponible);
    addTearDown(banco.cerrar);

    await banco.voz.activar();

    expect(banco.voz.estado, EstadoVoz.noDisponible);
    expect(banco.voz.mensajeError, contains('local'));
    expect(banco.stt.iniciarLlamadas, 0);
  });

  test(
    'variante local agotada pasa a noDisponible sin reintento remoto',
    () async {
      final banco = _Banco();
      addTearDown(banco.cerrar);

      await banco.voz.activar();
      banco.stt.error('error_idioma_local_no_disponible');
      await _flush();

      expect(banco.voz.estado, EstadoVoz.noDisponible);
      expect(banco.voz.mensajeError, contains('Por privacidad'));
      expect(banco.api.enviarLlamadas, 0);
      expect(banco.stt.iniciarLlamadas, 1);
    },
  );

  test('activación doble no crea dos sesiones de micrófono', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    final Future<void> primera = banco.voz.activar();
    final Future<void> segunda = banco.voz.activar();
    await Future.wait(<Future<void>>[primera, segunda]);

    expect(banco.stt.iniciarLlamadas, 1);
    expect(banco.voz.estado, EstadoVoz.escuchando);
  });

  test('un fallo transitorio de STT reintenta antes de rendirse', () async {
    final banco = _Banco(iniciarStt: false, maxErrores: 2);
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    await _flush();

    expect(banco.stt.iniciarLlamadas, 2);
    expect(banco.voz.estado, EstadoVoz.error);
    expect(banco.voz.mensajeError, isNotNull);
  });

  test('fallo al iniciar STT no genera bucles infinitos', () async {
    final banco = _Banco(iniciarStt: false, maxErrores: 1);
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    await _flush();

    expect(banco.voz.estado, EstadoVoz.error);
    expect(banco.voz.mensajeError, isNotNull);
    expect(banco.api.enviarLlamadas, 0);
  });

  test(
    'texto y voz comparten UUID; parcial no envía y final envía una vez',
    () async {
      final banco = _Banco();
      addTearDown(banco.cerrar);

      await banco.conversacion.enviar('Mensaje escrito');
      await banco.voz.activar();
      expect(banco.voz.estado, EstadoVoz.escuchando);

      banco.stt.parcial('Quiero una');
      banco.stt.parcial('Quiero una cita');
      await _flush();
      expect(banco.api.enviarLlamadas, 1, reason: 'el parcial no envía');

      banco.stt.final_('Quiero una cita para mañana');
      await _flush();

      expect(banco.api.enviarLlamadas, 2);
      expect(banco.api.crearLlamadas, 1, reason: 'mismo UUID para texto y voz');
      expect(banco.api.envios.last['conversacion_id'], 'conv-1');
      expect(banco.api.envios.last['modalidad'], 'voz');
      expect(banco.voz.estado, EstadoVoz.respondiendo);
    },
  );

  test(
    'STT se detiene antes de TTS y TTS termina antes de reactivar STT',
    () async {
      final banco = _Banco();
      addTearDown(banco.cerrar);

      await banco.voz.activar();
      banco.stt.final_('Hola');
      await _flush();

      expect(banco.stt.escuchando, isFalse);
      expect(banco.tts.sttEscuchandoAlHablar, isFalse);
      expect(banco.tts.hablarLlamadas, 1);
      expect(banco.tts.textos.single, 'Respuesta pública hablada');
      expect(banco.voz.estado, EstadoVoz.respondiendo);

      banco.tts.terminar();
      await _flush();

      expect(banco.voz.estado, EstadoVoz.escuchando);
      expect(banco.stt.iniciarLlamadas, 2);
      expect(banco.stt.ttsHablandoAlIniciar, isFalse);
      expect(banco.tts.hablando, isFalse);
    },
  );

  test('un resultado final duplicado no duplica la solicitud', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    banco.stt.final_('Hola');
    banco.stt.final_('Hola');
    await _flush();

    expect(banco.api.enviarLlamadas, 1);
  });

  test('pausa manual detiene audio y no reactiva sola', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    banco.stt.final_('Hola');
    await _flush();
    expect(banco.voz.estado, EstadoVoz.respondiendo);

    await banco.voz.pausar();
    await _flush();

    expect(banco.voz.estado, EstadoVoz.pausado);
    expect(banco.stt.cancelarLlamadas, greaterThan(0));
    expect(banco.tts.detenerLlamadas, greaterThan(0));
    expect(banco.stt.iniciarLlamadas, 1);
  });

  test('silencio reiterado termina en pausa sin bucle', () async {
    final banco = _Banco(maxSilencios: 2);
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    banco.stt.silencio();
    await _flush();
    expect(banco.voz.estado, EstadoVoz.escuchando);
    expect(banco.stt.iniciarLlamadas, 2);

    banco.stt.silencio();
    await _flush();
    expect(banco.voz.estado, EstadoVoz.pausado);
    expect(banco.stt.iniciarLlamadas, 2);
  });

  test('error de reconocimiento queda en estado recuperable', () async {
    final banco = _Banco(maxErrores: 1);
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    banco.stt.error('network');
    await _flush();

    expect(banco.voz.estado, EstadoVoz.error);
    expect(banco.voz.mensajeError, isNotNull);
    expect(banco.stt.iniciarLlamadas, 1);
  });

  test('error de síntesis no intenta TTS en bucle', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    banco.stt.final_('Hola');
    await _flush();
    expect(banco.voz.estado, EstadoVoz.respondiendo);

    banco.tts.fallar();
    await _flush();

    expect(banco.voz.estado, EstadoVoz.pausado);
    expect(banco.voz.aviso, contains('voz del dispositivo'));
    expect(banco.tts.hablarLlamadas, 1);
    expect(banco.stt.iniciarLlamadas, 1);
  });

  test('segundo plano suspende y no reactiva el micrófono al volver', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    await banco.voz.suspenderPorCicloDeVida();
    await _flush();

    expect(banco.voz.estado, EstadoVoz.pausado);
    expect(banco.stt.cancelarLlamadas, greaterThan(0));
    expect(banco.voz.aviso, contains('primer plano'));

    banco.voz.reanudarCicloDeVida();
    await _flush();
    expect(banco.voz.estado, EstadoVoz.pausado);
    expect(banco.stt.iniciarLlamadas, 1);
  });

  test('ocultar pantalla detiene audio', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    banco.stt.final_('Hola');
    await _flush();
    await banco.voz.alOcultarPantalla();
    await _flush();

    expect(banco.voz.estado, EstadoVoz.pausado);
    expect(banco.tts.hablando, isFalse);
    expect(banco.stt.escuchando, isFalse);
  });

  test('cerrar sesión durante la respuesta detiene audio y contexto', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    await banco.voz.activar();
    banco.stt.final_('Hola');
    await _flush();
    expect(banco.voz.estado, EstadoVoz.respondiendo);

    banco.conversacion.cerrarSesion();
    await _flush();

    expect(banco.voz.estado, EstadoVoz.pausado);
    expect(banco.tts.hablando, isFalse);
    expect(banco.conversacion.mensajes, isEmpty);
    expect(banco.stt.iniciarLlamadas, 1);
  });

  test('información privada no se reproduce automáticamente', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);
    banco.api.respuesta = RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Tus citas próximas',
      textoVoz: 'Tus citas próximas',
      tipo: TipoRespuestaChatbot.datos,
      tarjetas: <TarjetaChatbot>[
        TarjetaCitasPropias(
          citas: <CitaPropiaChat>[
            CitaPropiaChat(
              id: 1,
              oftalmologoId: 1,
              fecha: DateTime(2026, 12, 15),
              horaInicio: '10:00:00',
              horaFin: '10:30:00',
              estado: 'PROGRAMADA',
            ),
          ],
        ),
      ],
    );

    await banco.voz.activar();
    banco.stt.final_('Mis citas');
    await _flush();

    expect(banco.voz.estado, EstadoVoz.pausado);
    expect(banco.tts.hablarLlamadas, 0);
    expect(banco.voz.aviso, contains('privada'));
    expect(banco.voz.respuestaPrivada, isTrue);
  });

  test('información privada se lee solo con motor local verificado', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);
    banco.tts.localVerificado = true;
    banco.api.respuesta = RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Tu cita próxima',
      textoVoz: 'Tu cita próxima',
      tipo: TipoRespuestaChatbot.datos,
      tarjetas: <TarjetaChatbot>[
        TarjetaCitasPropias(
          citas: <CitaPropiaChat>[
            CitaPropiaChat(
              id: 1,
              oftalmologoId: 1,
              fecha: DateTime(2026, 12, 15),
              horaInicio: '10:00:00',
              horaFin: '10:30:00',
              estado: 'PROGRAMADA',
            ),
          ],
        ),
      ],
    );

    await banco.voz.activar();
    banco.stt.final_('Mis citas');
    await _flush();

    expect(banco.voz.estado, EstadoVoz.respondiendo);
    expect(banco.tts.hablarLlamadas, 1);
    expect(banco.tts.textos.single, 'Tu cita próxima');
  });

  test(
    'detener respuesta vuelve a escuchar y conserva la conversación',
    () async {
      final banco = _Banco();
      addTearDown(banco.cerrar);

      await banco.voz.activar();
      banco.stt.final_('Hola');
      await _flush();
      expect(banco.voz.estado, EstadoVoz.respondiendo);

      await banco.voz.detenerRespuesta();
      await _flush();

      expect(banco.tts.hablando, isFalse);
      expect(banco.voz.estado, EstadoVoz.escuchando);
      expect(banco.stt.iniciarLlamadas, 2);
      expect(banco.conversacion.mensajes, isNotEmpty);
    },
  );

  test(
    'salir conserva la conversación; finalizar la borra con DELETE',
    () async {
      final banco = _Banco();
      addTearDown(banco.cerrar);

      await banco.conversacion.enviar('Hola');
      await banco.voz.activar();
      await banco.voz.salir();

      expect(banco.voz.estado, EstadoVoz.inactivo);
      expect(banco.conversacion.mensajes, isNotEmpty);
      expect(banco.api.borrarLlamadas, 0);

      await banco.voz.finalizarConversacion();
      expect(banco.voz.estado, EstadoVoz.finalizado);
      expect(banco.conversacion.mensajes, isEmpty);
      expect(banco.api.borrarLlamadas, 1);
    },
  );

  test('reproducción manual de un mensaje privado se bloquea', () async {
    final banco = _Banco();
    addTearDown(banco.cerrar);

    final mensaje = MensajeChat(
      id: 'm1',
      rol: RolMensajeChat.asistente,
      texto: 'Cita privada',
      hora: DateTime(2026, 11, 21),
      tarjetas: <TarjetaChatbot>[
        TarjetaCitasPropias(
          citas: <CitaPropiaChat>[
            CitaPropiaChat(
              id: 1,
              oftalmologoId: 1,
              fecha: DateTime(2026, 12, 15),
              horaInicio: '10:00:00',
              horaFin: '10:30:00',
              estado: 'PROGRAMADA',
            ),
          ],
        ),
      ],
    );

    await banco.voz.reproducirMensaje(mensaje);
    await _flush();

    expect(banco.tts.hablarLlamadas, 0);
    expect(banco.voz.aviso, contains('privada'));
  });
}
