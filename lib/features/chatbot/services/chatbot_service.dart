import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/chatbot_models.dart';

/// Error de una petición al chatbot con información suficiente para que la
/// interfaz aplique el tratamiento correcto (401/403/404/409/429/red/timeout).
class ChatbotException implements Exception {
  const ChatbotException(
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.sesionCambiada = false,
    this.resultadoIncierto = false,
    this.respuestaInvalida = false,
  });

  /// Mensaje entendible para mostrar al paciente.
  final String message;

  /// Código HTTP cuando el backend respondió.
  final int? statusCode;

  /// `Retry-After` del backend, cuando existe (por ejemplo en 429).
  final Duration? retryAfter;

  /// El JWT cambió mientras la petición estaba en curso. La respuesta
  /// pertenece a una sesión anterior y debe descartarse.
  final bool sesionCambiada;

  /// La escritura venció por timeout/corte: el servidor pudo haberla
  /// procesado. No se reintenta automáticamente.
  final bool resultadoIncierto;

  /// El cuerpo 200 no corresponde al contrato esperado.
  final bool respuestaInvalida;

  @override
  String toString() => message;
}

/// Contrato HTTP del chatbot. Permite inyectar un cliente simulado en pruebas
/// sin dispositivos ni red real.
abstract class ChatbotApi {
  Future<ConversacionChatbot> crearConversacion();

  Future<RespuestaChatbot> enviarMensaje({
    required String conversacionId,
    required String mensaje,
    required ModalidadChat modalidad,
  });

  Future<void> finalizarConversacion(String conversacionId);
}

/// Servicio real contra FastAPI (`/notificaciones-chatbot/conversaciones`).
///
/// - Reutiliza [ApiConfig.baseUrl] (configurable con `--dart-define=API_URL`).
/// - Lee el JWT tenant de [TokenStorage] en cada petición.
/// - Nunca envía `empresa_id`, `tenant_id`, `paciente_id` ni historial.
/// - No reintenta automáticamente ninguna solicitud.
class ChatbotService implements ChatbotApi {
  ChatbotService({
    http.Client? client,
    Future<String?> Function()? leerToken,
    Duration? timeoutMensaje,
    Duration? timeoutCorto,
  }) : _client = client ?? http.Client(),
       _propio = client == null,
       _leerToken = leerToken ?? (() => TokenStorage().getToken()),
       timeoutMensaje = timeoutMensaje ?? const Duration(seconds: 65),
       timeoutCorto = timeoutCorto ?? const Duration(seconds: 15);

  final http.Client _client;
  final bool _propio;
  final Future<String?> Function() _leerToken;

  /// El backend tiene un timeout total configurable de 60 s por defecto.
  /// La app espera algo más para no abandonar una solicitud válida.
  final Duration timeoutMensaje;

  /// Crear/finalizar conversación no ejecutan IA: un timeout breve es
  /// suficiente.
  final Duration timeoutCorto;

  static const String _rutaBase = '/notificaciones-chatbot/conversaciones';

  void dispose() {
    if (_propio) _client.close();
  }

  @override
  Future<ConversacionChatbot> crearConversacion() async {
    final String jwt = await _tokenActual();
    final http.Response response = await _enviar(
      'POST',
      _rutaBase,
      jwt: jwt,
      body: const <String, dynamic>{},
      timeout: timeoutCorto,
    );
    await _verificarMismaSesion(jwt);

    if (response.statusCode == 201) {
      final Map<String, dynamic> json = _mapa(
        response,
        mensajeInvalido:
            'El asistente devolvió una conversación no válida. '
            'Inténtalo de nuevo.',
      );
      final ConversacionChatbot conversacion = ConversacionChatbot.fromJson(
        json,
      );
      if (conversacion.id.isEmpty) {
        throw const ChatbotException(
          'El asistente devolvió una conversación no válida. '
          'Inténtalo de nuevo.',
          respuestaInvalida: true,
        );
      }
      return conversacion;
    }

    throw _errorHttp(response);
  }

  @override
  Future<RespuestaChatbot> enviarMensaje({
    required String conversacionId,
    required String mensaje,
    required ModalidadChat modalidad,
  }) async {
    final String limpio = mensaje.trim();
    if (limpio.isEmpty) {
      throw const ChatbotException(
        'Escribe un mensaje antes de enviarlo.',
        statusCode: 422,
      );
    }

    final String jwt = await _tokenActual();
    final http.Response response = await _enviar(
      'POST',
      '$_rutaBase/${Uri.encodeComponent(conversacionId)}/mensajes',
      jwt: jwt,
      body: <String, dynamic>{
        'mensaje': limpio,
        'modalidad': modalidad.valorApi,
      },
      timeout: timeoutMensaje,
    );
    await _verificarMismaSesion(jwt);

    if (response.statusCode == 200) {
      final Map<String, dynamic> json = _mapa(
        response,
        mensajeInvalido:
            'El asistente envió una respuesta no válida. '
            'Puedes intentarlo de nuevo.',
      );
      final RespuestaChatbot respuesta = RespuestaChatbot.fromJson(json);
      if (respuesta.respuesta.isEmpty) {
        throw const ChatbotException(
          'El asistente envió una respuesta vacía. Inténtalo de nuevo.',
          respuestaInvalida: true,
        );
      }
      return respuesta;
    }

    throw _errorHttp(response);
  }

  @override
  Future<void> finalizarConversacion(String conversacionId) async {
    final String jwt = await _tokenActual();
    final http.Response response = await _enviar(
      'DELETE',
      '$_rutaBase/${Uri.encodeComponent(conversacionId)}',
      jwt: jwt,
      timeout: timeoutCorto,
    );
    await _verificarMismaSesion(jwt);

    if (response.statusCode == 204) return;
    throw _errorHttp(response);
  }

  // -------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------

  Future<String> _tokenActual() async {
    final String? token = await _leerToken();
    if (token == null || token.trim().isEmpty) {
      throw const ChatbotException(
        'Tu sesión no es válida. Vuelve a iniciar sesión.',
        statusCode: 401,
      );
    }
    return token;
  }

  /// Descarta una respuesta emitida para un JWT anterior.
  ///
  /// Solo se compara el valor en memoria mientras dura la petición; el token
  /// nunca se registra ni se persiste aquí.
  Future<void> _verificarMismaSesion(String jwtEnviado) async {
    final String? actual = await _leerToken();
    if (actual != jwtEnviado) {
      throw const ChatbotException(
        'La sesión cambió mientras el asistente respondía. '
        'Vuelve a iniciar la conversación.',
        sesionCambiada: true,
      );
    }
  }

  Future<http.Response> _enviar(
    String metodo,
    String ruta, {
    required String jwt,
    Map<String, dynamic>? body,
    required Duration timeout,
  }) async {
    final Uri uri = Uri.parse('${ApiConfig.baseUrl}$ruta');
    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer $jwt',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final String? cuerpo = body == null ? null : jsonEncode(body);

    try {
      final Future<http.Response> peticion;
      switch (metodo) {
        case 'POST':
          peticion = _client.post(uri, headers: headers, body: cuerpo);
        case 'DELETE':
          peticion = _client.delete(uri, headers: headers);
        default:
          peticion = _client.get(uri, headers: headers);
      }
      return await peticion.timeout(timeout);
    } on TimeoutException {
      throw ChatbotException(
        'El asistente está tardando más de lo habitual. No sabemos si el '
        'servidor alcanzó a procesar tu mensaje; revísalo antes de volver a '
        'enviarlo.',
        resultadoIncierto: true,
      );
    } on http.ClientException {
      throw const ChatbotException(
        'No pudimos conectar con el asistente. Verifica tu conexión e '
        'inténtalo de nuevo.',
        resultadoIncierto: true,
      );
    } on ChatbotException {
      rethrow;
    } on Exception {
      throw const ChatbotException(
        'Ocurrió un error de conexión. Inténtalo de nuevo.',
        resultadoIncierto: true,
      );
    }
  }

  Map<String, dynamic> _mapa(
    http.Response response, {
    required String mensajeInvalido,
  }) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Cae al error controlado.
    }
    throw ChatbotException(mensajeInvalido, respuestaInvalida: true);
  }

  /// Traduce el error HTTP del backend a un mensaje comprensible.
  ChatbotException _errorHttp(http.Response response) {
    final String? detalle = _detail(response);
    final Duration? retryAfter = _retryAfter(response);

    final String mensaje = switch (response.statusCode) {
      401 => 'Tu sesión expiró. Vuelve a iniciar sesión.',
      403 =>
        detalle ??
            'No tienes autorización para usar el asistente con esta cuenta.',
      404 =>
        detalle ??
            'La conversación ya no está disponible. Puedes iniciar una nueva.',
      409 =>
        detalle ??
            'El asistente está procesando otra respuesta. Espera un momento.',
      413 => 'El mensaje es demasiado extenso. Acórtalo e inténtalo de nuevo.',
      422 =>
        detalle ??
            'No pudimos interpretar la solicitud. Revisa el mensaje e '
                'inténtalo de nuevo.',
      429 =>
        retryAfter == null
            ? 'Alcanzaste el límite temporal del asistente. Espera un momento '
                  'antes de continuar.'
            : 'Alcanzaste el límite temporal del asistente. Espera '
                  '${retryAfter.inSeconds} segundos antes de continuar.',
      502 =>
        'El asistente no pudo preparar una respuesta válida. '
            'Inténtalo de nuevo.',
      503 =>
        'El asistente no está disponible en este momento. '
            'Puedes seguir usando el resto de la aplicación.',
      504 =>
        'El asistente tardó demasiado en responder. '
            'Inténtalo de nuevo en un momento.',
      _ =>
        detalle ??
            'No se pudo completar la solicitud al asistente '
                '(código ${response.statusCode}).',
    };

    return ChatbotException(
      mensaje,
      statusCode: response.statusCode,
      retryAfter: retryAfter,
    );
  }

  String? _detail(http.Response response) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final Object? detail = decoded['detail'];
      if (detail is String && detail.trim().isNotEmpty) {
        return detail.trim();
      }
      if (detail is List && detail.isNotEmpty) {
        final List<String> mensajes = <String>[
          for (final Object? item in detail)
            if (item is Map<String, dynamic> && item['msg'] is String)
              (item['msg'] as String).trim(),
        ]..removeWhere((String texto) => texto.isEmpty);
        if (mensajes.isNotEmpty) return mensajes.join('\n');
      }
    } on FormatException {
      // Sin JSON: se usa el mensaje por código.
    }
    return null;
  }

  Duration? _retryAfter(http.Response response) {
    final String? valor = response.headers['retry-after'];
    if (valor == null) return null;
    final int? segundos = int.tryParse(valor.trim());
    if (segundos == null || segundos <= 0) return null;
    return Duration(seconds: segundos);
  }
}
