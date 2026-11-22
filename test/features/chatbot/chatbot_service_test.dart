import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:clinica_oftalmologica_mobile/features/chatbot/models/chatbot_models.dart';
import 'package:clinica_oftalmologica_mobile/features/chatbot/services/chatbot_service.dart';

http.Response _json(Object body, int status, {Map<String, String>? headers}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: <String, String>{'content-type': 'application/json', ...?headers},
  );
}

void main() {
  test('crear conversación usa URL, JWT y body vacío', () async {
    late http.Request capturada;
    final service = ChatbotService(
      leerToken: () async => 'jwt-tenant',
      client: MockClient((http.Request request) async {
        capturada = request;
        return _json(<String, dynamic>{
          'conversacion_id': 'conv-1',
          'expira_en_segundos': 1800,
        }, 201);
      }),
    );

    final ConversacionChatbot conversacion = await service.crearConversacion();

    expect(conversacion.id, 'conv-1');
    expect(conversacion.expiraEnSegundos, 1800);
    expect(capturada.url.path, '/notificaciones-chatbot/conversaciones');
    expect(capturada.method, 'POST');
    expect(capturada.headers['Authorization'], 'Bearer jwt-tenant');
    expect(capturada.headers['Content-Type'], 'application/json');
    expect(capturada.body, '{}');
  });

  test(
    'enviar mensaje de texto: body exacto y sin datos de identidad',
    () async {
      late http.Request capturada;
      final service = ChatbotService(
        leerToken: () async => 'jwt-tenant',
        client: MockClient((http.Request request) async {
          capturada = request;
          return _json(<String, dynamic>{
            'conversacion_id': 'conv-1',
            'respuesta': 'Hola',
            'texto_voz': 'Hola',
            'tipo': 'texto',
            'tarjetas': <Object>[],
          }, 200);
        }),
      );

      final RespuestaChatbot respuesta = await service.enviarMensaje(
        conversacionId: 'conv-1',
        mensaje: '  Hola  ',
        modalidad: ModalidadChat.texto,
      );

      expect(respuesta.respuesta, 'Hola');
      expect(
        capturada.url.path,
        '/notificaciones-chatbot/conversaciones/conv-1/mensajes',
      );
      final Map<String, dynamic> body =
          jsonDecode(capturada.body) as Map<String, dynamic>;
      expect(body, <String, dynamic>{'mensaje': 'Hola', 'modalidad': 'texto'});
      expect(body.containsKey('empresa_id'), isFalse);
      expect(body.containsKey('tenant_id'), isFalse);
      expect(body.containsKey('paciente_id'), isFalse);
      expect(body.containsKey('historial'), isFalse);
    },
  );

  test('enviar mensaje de voz usa modalidad voz', () async {
    late http.Request capturada;
    final service = ChatbotService(
      leerToken: () async => 'jwt',
      client: MockClient((http.Request request) async {
        capturada = request;
        return _json(<String, dynamic>{
          'conversacion_id': 'conv-1',
          'respuesta': 'Respuesta',
          'texto_voz': 'Respuesta hablada',
          'tipo': 'texto',
          'tarjetas': <Object>[],
        }, 200);
      }),
    );

    final RespuestaChatbot respuesta = await service.enviarMensaje(
      conversacionId: 'conv-1',
      mensaje: 'Quiero una cita',
      modalidad: ModalidadChat.voz,
    );

    expect(respuesta.textoVoz, 'Respuesta hablada');
    final Map<String, dynamic> body =
        jsonDecode(capturada.body) as Map<String, dynamic>;
    expect(body['modalidad'], 'voz');
  });

  test('finalizar conversación acepta 204 sin cuerpo', () async {
    late http.Request capturada;
    final service = ChatbotService(
      leerToken: () async => 'jwt',
      client: MockClient((http.Request request) async {
        capturada = request;
        return http.Response('', 204);
      }),
    );

    await service.finalizarConversacion('conv-1');

    expect(capturada.method, 'DELETE');
    expect(capturada.url.path, '/notificaciones-chatbot/conversaciones/conv-1');
  });

  test('sin JWT no consulta la red', () async {
    var llamadas = 0;
    final service = ChatbotService(
      leerToken: () async => null,
      client: MockClient((_) async {
        llamadas++;
        return http.Response('', 200);
      }),
    );

    await expectLater(
      service.crearConversacion(),
      throwsA(
        isA<ChatbotException>().having((e) => e.statusCode, 'status', 401),
      ),
    );
    expect(llamadas, 0);
  });

  test('respuesta 200 inválida no se interpreta', () async {
    final service = ChatbotService(
      leerToken: () async => 'jwt',
      client: MockClient((_) async => http.Response('html', 200)),
    );

    await expectLater(
      service.enviarMensaje(
        conversacionId: 'conv-1',
        mensaje: 'Hola',
        modalidad: ModalidadChat.texto,
      ),
      throwsA(
        isA<ChatbotException>().having(
          (e) => e.respuestaInvalida,
          'respuestaInvalida',
          isTrue,
        ),
      ),
    );
  });

  test('conversación sin id se rechaza', () async {
    final service = ChatbotService(
      leerToken: () async => 'jwt',
      client: MockClient(
        (_) async => _json(<String, dynamic>{
          'conversacion_id': '',
          'expira_en_segundos': 1800,
        }, 201),
      ),
    );
    await expectLater(
      service.crearConversacion(),
      throwsA(isA<ChatbotException>()),
    );
  });

  for (final int status in <int>[401, 403, 404, 409, 413, 422, 502, 503, 504]) {
    test('error HTTP $status se traduce y no reintenta', () async {
      var llamadas = 0;
      final service = ChatbotService(
        leerToken: () async => 'jwt',
        client: MockClient((_) async {
          llamadas++;
          return _json(<String, dynamic>{'detail': 'detalle seguro'}, status);
        }),
      );

      await expectLater(
        service.enviarMensaje(
          conversacionId: 'conv-1',
          mensaje: 'Hola',
          modalidad: ModalidadChat.texto,
        ),
        throwsA(
          isA<ChatbotException>().having((e) => e.statusCode, 'status', status),
        ),
      );
      expect(llamadas, 1, reason: 'no debe reintentar automáticamente');
    });
  }

  test('429 respeta Retry-After', () async {
    final service = ChatbotService(
      leerToken: () async => 'jwt',
      client: MockClient(
        (_) async => _json(
          <String, dynamic>{'detail': 'límite'},
          429,
          headers: <String, String>{'retry-after': '60'},
        ),
      ),
    );

    await expectLater(
      service.enviarMensaje(
        conversacionId: 'conv-1',
        mensaje: 'Hola',
        modalidad: ModalidadChat.texto,
      ),
      throwsA(
        isA<ChatbotException>()
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 60),
            )
            .having((e) => e.message, 'mensaje', contains('60 segundos')),
      ),
    );
  });

  test('timeout se marca como resultado incierto', () async {
    final Completer<http.Response> pendiente = Completer<http.Response>();
    final service = ChatbotService(
      leerToken: () async => 'jwt',
      timeoutMensaje: const Duration(milliseconds: 15),
      client: MockClient((_) => pendiente.future),
    );

    await expectLater(
      service.enviarMensaje(
        conversacionId: 'conv-1',
        mensaje: 'Hola',
        modalidad: ModalidadChat.texto,
      ),
      throwsA(
        isA<ChatbotException>()
            .having((e) => e.resultadoIncierto, 'incierto', isTrue)
            .having((e) => e.statusCode, 'status', isNull),
      ),
    );
  });

  test('cambio de JWT durante la solicitud descarta la respuesta', () async {
    String token = 'ALPHA';
    final service = ChatbotService(
      leerToken: () async => token,
      client: MockClient((_) async {
        token = 'BETA';
        return _json(<String, dynamic>{
          'conversacion_id': 'conv-1',
          'respuesta': 'Respuesta de ALPHA',
          'texto_voz': 'Respuesta de ALPHA',
          'tipo': 'texto',
          'tarjetas': <Object>[],
        }, 200);
      }),
    );

    await expectLater(
      service.enviarMensaje(
        conversacionId: 'conv-1',
        mensaje: 'Hola',
        modalidad: ModalidadChat.texto,
      ),
      throwsA(
        isA<ChatbotException>().having(
          (e) => e.sesionCambiada,
          'sesionCambiada',
          isTrue,
        ),
      ),
    );
  });

  test('mensaje vacío no envía red', () async {
    var llamadas = 0;
    final service = ChatbotService(
      leerToken: () async => 'jwt',
      client: MockClient((_) async {
        llamadas++;
        return http.Response('', 200);
      }),
    );
    await expectLater(
      service.enviarMensaje(
        conversacionId: 'conv-1',
        mensaje: '   ',
        modalidad: ModalidadChat.texto,
      ),
      throwsA(isA<ChatbotException>()),
    );
    expect(llamadas, 0);
  });
}
