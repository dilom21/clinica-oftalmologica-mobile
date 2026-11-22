import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:clinica_oftalmologica_mobile/features/chatbot/controllers/chatbot_controller.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/chatbot_service.dart';

import 'soporte_chatbot.dart';

ChatbotController _controlador(
  ApiChatbotFalsa api, {
  String? Function()? token,
  DateTime Function()? ahora,
  Future<void> Function()? alSesionInvalida,
}) {
  return ChatbotController(
    api: api,
    leerToken: () async => token?.call() ?? 'jwt',
    ahora: ahora,
    alSesionInvalida: alSesionInvalida,
  );
}

void main() {
  test('texto y voz comparten UUID e historial', () async {
    final api = ApiChatbotFalsa();
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    final MensajeChat? uno = await ctrl.enviar('Hola');
    final MensajeChat? dos = await ctrl.enviar(
      'Quiero una cita',
      modalidad: ModalidadChat.voz,
    );

    expect(uno, isNotNull);
    expect(dos, isNotNull);
    expect(api.crearLlamadas, 1);
    expect(api.enviarLlamadas, 2);
    expect(api.envios[0]['conversacion_id'], 'conv-1');
    expect(api.envios[1]['conversacion_id'], 'conv-1');
    expect(api.envios[0]['modalidad'], 'texto');
    expect(api.envios[1]['modalidad'], 'voz');
    expect(ctrl.conversacionId, 'conv-1');
    expect(
      ctrl.mensajes.where((m) => m.rol == RolMensajeChat.paciente).length,
      2,
    );
    expect(
      ctrl.mensajes.where((m) => m.rol == RolMensajeChat.asistente).length,
      2,
    );
  });

  test('no permite solicitudes simultáneas ni duplica mensajes', () async {
    final api = ApiChatbotFalsa();
    final Completer<RespuestaChatbot> pendiente = Completer<RespuestaChatbot>();
    api.alEnviar = (_, _) => pendiente.future;
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    final Future<MensajeChat?> primera = ctrl.enviar('Primero');
    await Future<void>.delayed(Duration.zero);
    final MensajeChat? segunda = await ctrl.enviar('Segundo');

    expect(segunda, isNull);
    expect(api.enviarLlamadas, 1);
    expect(
      ctrl.mensajes.where((m) => m.rol == RolMensajeChat.paciente).length,
      1,
    );

    api.respuesta = const RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Listo',
      textoVoz: 'Listo',
      tipo: TipoRespuestaChatbot.texto,
      tarjetas: <TarjetaChatbot>[],
    );
    pendiente.complete(api.respuesta);
    await primera;
    expect(ctrl.mensajes.last.texto, 'Listo');
  });

  test(
    'error 503 permite reintento explícito sin duplicar el mensaje',
    () async {
      final api = ApiChatbotFalsa();
      api.errorEnviar = const ChatbotException(
        'Servicio no disponible',
        statusCode: 503,
      );
      final ctrl = _controlador(api);
      addTearDown(ctrl.dispose);

      await ctrl.enviar('Quiero ayuda');
      expect(ctrl.mensajes.last.esError, isTrue);
      expect(ctrl.puedeReintentar, isTrue);
      expect(ctrl.errorGeneral, 'Servicio no disponible');
      expect(
        ctrl.mensajes.where((m) => m.rol == RolMensajeChat.paciente).length,
        1,
      );

      api.errorEnviar = null;
      final MensajeChat? reintento = await ctrl.reintentarUltimo();
      expect(reintento, isNotNull);
      expect(api.enviarLlamadas, 2);
      expect(
        ctrl.mensajes.where((m) => m.rol == RolMensajeChat.paciente).length,
        1,
        reason: 'el reintento no agrega otra burbuja del paciente',
      );
      expect(ctrl.mensajes.any((m) => m.esError), isFalse);
    },
  );

  test('un timeout incierto no ofrece reintento automático', () async {
    final api = ApiChatbotFalsa();
    api.errorEnviar = const ChatbotException(
      'No sabemos si se procesó',
      resultadoIncierto: true,
    );
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    await ctrl.enviar('Mensaje incierto');
    expect(ctrl.mensajes.last.esError, isTrue);
    expect(ctrl.mensajes.last.textoReintentable, isNull);
    expect(ctrl.puedeReintentar, isFalse);
  });

  test('una respuesta inválida tras enviar no ofrece reintento', () async {
    final api = ApiChatbotFalsa();
    api.errorEnviar = const ChatbotException(
      'La respuesta no es válida',
      respuestaInvalida: true,
    );
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    await ctrl.enviar('Mensaje enviado');
    expect(ctrl.mensajes.last.esError, isTrue);
    expect(ctrl.puedeReintentar, isFalse);
  });

  test(
    '404 descarta el UUID y el siguiente envío crea otra conversación',
    () async {
      final api = ApiChatbotFalsa();
      api.errorEnviar = const ChatbotException(
        'Conversación no disponible',
        statusCode: 404,
      );
      final ctrl = _controlador(api);
      addTearDown(ctrl.dispose);

      await ctrl.enviar('Hola');
      expect(ctrl.conversacionId, isNull);
      expect(
        ctrl.mensajes,
        isNotEmpty,
        reason: 'conserva el historial visible',
      );

      api.errorEnviar = null;
      api.conversacionId = 'conv-2';
      api.respuesta = const RespuestaChatbot(
        conversacionId: 'conv-2',
        respuesta: 'Nueva conversación',
        textoVoz: 'Nueva conversación',
        tipo: TipoRespuestaChatbot.texto,
        tarjetas: <TarjetaChatbot>[],
      );
      await ctrl.enviar('Otra vez');
      expect(api.crearLlamadas, 2);
      expect(ctrl.conversacionId, 'conv-2');
    },
  );

  test(
    '401 limpia la conversación e invoca el cierre de sesión existente',
    () async {
      final api = ApiChatbotFalsa();
      api.errorEnviar = const ChatbotException(
        'Sesión expirada',
        statusCode: 401,
      );
      var cierres = 0;
      final ctrl = _controlador(api, alSesionInvalida: () async => cierres++);
      addTearDown(ctrl.dispose);

      await ctrl.enviar('Hola');
      await Future<void>.delayed(Duration.zero);

      expect(cierres, 1);
      expect(ctrl.mensajes, isEmpty);
      expect(ctrl.conversacionId, isNull);
      expect(ctrl.tieneConversacion, isFalse);
    },
  );

  test('nueva conversación finaliza la anterior y limpia todo', () async {
    final api = ApiChatbotFalsa();
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    await ctrl.enviar('Hola');
    expect(ctrl.mensajes, isNotEmpty);

    await ctrl.nuevaConversacion();

    expect(ctrl.mensajes, isEmpty);
    expect(ctrl.conversacionId, isNull);
    expect(api.idsBorrados, <String>['conv-1']);

    api.conversacionId = 'conv-2';
    await ctrl.enviar('Nueva');
    expect(api.crearLlamadas, 2);
    expect(ctrl.conversacionId, 'conv-2');
  });

  test('finalizar usa DELETE y deja el estado vacío', () async {
    final api = ApiChatbotFalsa();
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    await ctrl.enviar('Hola');
    await ctrl.finalizar();

    expect(api.borrarLlamadas, 1);
    expect(api.idsBorrados.single, 'conv-1');
    expect(ctrl.mensajes, isEmpty);
    expect(ctrl.conversacionId, isNull);
  });

  test('cierre de sesión no llama al backend y borra el contexto', () async {
    final api = ApiChatbotFalsa();
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    await ctrl.enviar('Hola');
    ctrl.cerrarSesion();

    expect(ctrl.mensajes, isEmpty);
    expect(ctrl.conversacionId, isNull);
    expect(api.borrarLlamadas, 0);
  });

  test('expiración perezosa limpia UUID e historial', () async {
    DateTime ahora = DateTime(2026, 11, 21, 9);
    final api = ApiChatbotFalsa()..expiraEnSegundos = 60;
    final ctrl = _controlador(api, ahora: () => ahora);
    addTearDown(ctrl.dispose);

    await ctrl.enviar('Hola');
    expect(ctrl.minutosRestantes, 1);

    ahora = ahora.add(const Duration(seconds: 61));
    expect(ctrl.verificarExpiracion(), isTrue);
    expect(ctrl.mensajes, isEmpty);
    expect(ctrl.conversacionId, isNull);
    expect(ctrl.aviso, contains('expiró'));

    await ctrl.enviar('Después');
    expect(api.crearLlamadas, 2);
    expect(ctrl.aviso, isNull);
  });

  test('respuesta tardía de una conversación anterior se descarta', () async {
    final api = ApiChatbotFalsa();
    final Completer<RespuestaChatbot> pendiente = Completer<RespuestaChatbot>();
    api.alEnviar = (_, _) => pendiente.future;
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    final Future<MensajeChat?> envio = ctrl.enviar('Hola');
    await Future<void>.delayed(Duration.zero);
    await ctrl.nuevaConversacion();

    pendiente.complete(
      const RespuestaChatbot(
        conversacionId: 'conv-1',
        respuesta: 'Respuesta vieja',
        textoVoz: 'Respuesta vieja',
        tipo: TipoRespuestaChatbot.texto,
        tarjetas: <TarjetaChatbot>[],
      ),
    );

    expect(await envio, isNull);
    expect(ctrl.mensajes, isEmpty);
    expect(ctrl.mensajes.any((m) => m.texto == 'Respuesta vieja'), isFalse);
  });

  test('cambio de JWT descarta respuesta y contexto anterior', () async {
    String token = 'ALPHA';
    final api = ApiChatbotFalsa();
    api.alEnviar = (_, _) async {
      token = 'BETA';
      return const RespuestaChatbot(
        conversacionId: 'conv-1',
        respuesta: 'De ALPHA',
        textoVoz: 'De ALPHA',
        tipo: TipoRespuestaChatbot.texto,
        tarjetas: <TarjetaChatbot>[],
      );
    };
    final ctrl = _controlador(api, token: () => token);
    addTearDown(ctrl.dispose);

    final MensajeChat? resultado = await ctrl.enviar('Hola');
    expect(resultado, isNull);
    expect(ctrl.mensajes, isEmpty);
    expect(ctrl.conversacionId, isNull);
  });

  test('mensaje mayor al límite no llega a la API', () async {
    final api = ApiChatbotFalsa();
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    final MensajeChat? resultado = await ctrl.enviar('a' * 1001);
    expect(resultado, isNull);
    expect(api.enviarLlamadas, 0);
    expect(api.crearLlamadas, 0);
    expect(ctrl.errorGeneral, contains('1000'));
  });

  test('invalidar tarjetas agrega aviso local y bloquea propuestas', () async {
    final api = ApiChatbotFalsa();
    api.respuesta = RespuestaChatbot(
      conversacionId: 'conv-1',
      respuesta: 'Propuesta',
      textoVoz: 'Propuesta',
      tipo: TipoRespuestaChatbot.datos,
      tarjetas: <TarjetaChatbot>[
        TarjetaPropuestaCita(
          oftalmologoId: 1,
          fecha: DateTime(2026, 12, 15),
          horaInicio: '09:00:00',
          horaFin: '09:30:00',
        ),
      ],
    );
    final ctrl = _controlador(api);
    addTearDown(ctrl.dispose);

    await ctrl.enviar('Cita');
    ctrl.invalidarTarjetas(evento: 'La cita cambió.');
    expect(ctrl.tarjetasInvalidas, isTrue);
    expect(ctrl.mensajes.last.rol, RolMensajeChat.sistema);
    expect(ctrl.mensajes.last.texto, 'La cita cambió.');
  });
}
