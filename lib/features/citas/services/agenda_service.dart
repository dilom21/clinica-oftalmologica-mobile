import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/agenda_models.dart';
import '../models/cita_models.dart';

/// Excepción lanzada cuando falla una petición de agenda o de citas.
class AgendaException implements Exception {
  const AgendaException(
    this.message, {
    this.statusCode,
    this.resultadoIncierto = false,
  });

  /// Mensaje entendible para mostrar al usuario.
  final String message;

  /// Código HTTP cuando el backend respondió (ej. 401, 403, 404, 409, 422).
  final int? statusCode;

  /// `true` cuando una escritura (POST/PUT/PATCH) se quedó sin respuesta por
  /// timeout o corte de red: el resultado es INCIERTO.
  ///
  /// La interfaz NO debe reintentar automáticamente en ese caso, porque la
  /// cita pudo haberse registrado en el servidor.
  final bool resultadoIncierto;

  @override
  String toString() => message;
}


/// Servicio de CU09 - Consultar agenda y disponibilidad médica.
///
/// Consume únicamente (orientado al Paciente):
/// - `GET /agenda-citas/oftalmologos`
/// - `GET /agenda-citas/disponibilidad`
///
/// NO consume `/agenda-citas/oftalmologos/{id}/agenda`: el Paciente no debe
/// ver la agenda interna de un oftalmólogo ni citas de otros pacientes.
class AgendaService {
  AgendaService({http.Client? client, Future<String?> Function()? leerToken})
    : _client = client ?? http.Client(),
      _leerToken = leerToken ?? (() => TokenStorage().getToken());

  final http.Client _client;

  /// Fuente del JWT (por defecto [TokenStorage], inyectable en pruebas).
  final Future<String?> Function() _leerToken;

  /// Tiempo máximo de espera para una respuesta del servidor.
  static const Duration _timeout = Duration(seconds: 20);

  /// Lista los oftalmólogos activos para consultar disponibilidad.
  ///
  /// `GET {ApiConfig.baseUrl}/agenda-citas/oftalmologos`
  Future<List<OftalmologoAgenda>> listarOftalmologos() async {
    final http.Response response = await _get(
      '/agenda-citas/oftalmologos',
      null,
    );

    if (response.statusCode == 200) {
      try {
        final Object? body = jsonDecode(response.body);

        if (body is! List) {
          throw const FormatException('Cuerpo de respuesta inesperado');
        }

        return [
          for (final item in body)
            if (item is Map<String, dynamic>) OftalmologoAgenda.fromJson(item),
        ];
      } on FormatException {
        throw const AgendaException(
          'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
        );
      } on TypeError {
        throw const AgendaException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw AgendaException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Consulta la disponibilidad real de un oftalmólogo en una fecha.
  ///
  /// `GET {ApiConfig.baseUrl}/agenda-citas/disponibilidad`
  /// con query params `oftalmologo_id` y `fecha` (`YYYY-MM-DD`).
  Future<DisponibilidadRespuesta> obtenerDisponibilidad({
    required int oftalmologoId,
    required DateTime fecha,
  }) async {
    final http.Response response = await _get(
      '/agenda-citas/disponibilidad',
      <String, String>{
        'oftalmologo_id': '$oftalmologoId',
        'fecha': _fechaIso(fecha),
      },
    );

    if (response.statusCode == 200) {
      try {
        final Object? body = jsonDecode(response.body);

        if (body is! Map<String, dynamic>) {
          throw const FormatException('Cuerpo de respuesta inesperado');
        }

        return DisponibilidadRespuesta.fromJson(body);
      } on FormatException {
        throw const AgendaException(
          'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
        );
      } on TypeError {
        throw const AgendaException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw AgendaException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// GET autenticado con JWT Bearer contra [ruta] + [query].
  Future<http.Response> _get(String ruta, Map<String, String>? query) {
    return _enviar('GET', ruta, query: query);
  }

  /// Petición autenticada con JWT Bearer (GET/POST/PUT/PATCH).
  ///
  /// [escritura] marca las operaciones que modifican datos: si vencen por
  /// timeout, la excepción se marca con `resultadoIncierto = true` para que la
  /// interfaz NO reintente sola (la cita pudo haberse registrado).
  Future<http.Response> _enviar(
    String metodo,
    String ruta, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool escritura = false,
  }) async {
    final token = await _leerToken();

    if (token == null || token.isEmpty) {
      throw const AgendaException(
        'Tu sesión no es válida. Vuelve a iniciar sesión.',
        statusCode: 401,
      );
    }

    final Uri uri = Uri.parse('${ApiConfig.baseUrl}$ruta')
        .replace(queryParameters: query);

    final Map<String, String> headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };

    final String? cuerpo = body == null ? null : jsonEncode(body);

    try {
      final Future<http.Response> peticion;
      switch (metodo) {
        case 'POST':
          peticion = _client.post(uri, headers: headers, body: cuerpo);
        case 'PUT':
          peticion = _client.put(uri, headers: headers, body: cuerpo);
        case 'PATCH':
          peticion = _client.patch(uri, headers: headers, body: cuerpo);
        default:
          peticion = _client.get(uri, headers: headers);
      }

      return await peticion.timeout(_timeout);
    } on TimeoutException {
      throw AgendaException(
        escritura
            ? 'El servidor tardó demasiado en responder. No sabemos si la '
                'operación quedó registrada: verifícala antes de reintentar.'
            : 'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
        resultadoIncierto: escritura,
      );
    } on http.ClientException {
      throw AgendaException(
        escritura
            ? 'Se interrumpió la conexión y no sabemos si la operación quedó '
                'registrada. Verifícala antes de reintentar.'
            : 'No se pudo conectar con el servidor. '
                'Verifica tu conexión e inténtalo de nuevo.',
        resultadoIncierto: escritura,
      );
    } on Exception {
      throw AgendaException(
        escritura
            ? 'Ocurrió un error de conexión y no sabemos si la operación quedó '
                'registrada. Verifícala antes de reintentar.'
            : 'Ocurrió un error de conexión inesperado. Inténtalo de nuevo.',
        resultadoIncierto: escritura,
      );
    }
  }

  // -------------------------------------------------------------------
  // CU10 - Agendamiento y gestión de citas del paciente
  // -------------------------------------------------------------------

  /// Lista las citas del paciente autenticado.
  ///
  /// `GET {ApiConfig.baseUrl}/agenda-citas/citas`
  ///
  /// NO se envía `paciente_id`: el backend restringe la consulta a las citas
  /// del paciente del JWT, así la app no puede pedir datos de otra persona.
  Future<List<Cita>> listarCitas({String? estado}) async {
    final String? filtro = estado?.trim();

    final http.Response response = await _get(
      '/agenda-citas/citas',
      filtro == null || filtro.isEmpty
          ? null
          : <String, String>{'estado': filtro},
    );

    if (response.statusCode == 200) {
      try {
        final Object? body = jsonDecode(response.body);

        if (body is! List) {
          throw const FormatException('Cuerpo de respuesta inesperado');
        }

        return <Cita>[
          for (final item in body)
            if (item is Map<String, dynamic>) Cita.fromJson(item),
        ];
      } on FormatException {
        throw const AgendaException(
          'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
        );
      } on TypeError {
        throw const AgendaException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw AgendaException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Obtiene el detalle real de una cita del paciente autenticado.
  ///
  /// `GET {ApiConfig.baseUrl}/agenda-citas/citas/{cita_id}`
  Future<Cita> obtenerCita(int citaId) async {
    final http.Response response = await _get(
      '/agenda-citas/citas/$citaId',
      null,
    );

    if (response.statusCode == 200) {
      return _citaDesdeRespuesta(response);
    }

    throw AgendaException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Registra una cita real del paciente (`canal = MOVIL` lo asigna FastAPI).
  ///
  /// `POST {ApiConfig.baseUrl}/agenda-citas/citas` -> 201 + `CitaResponse`
  ///
  /// La hora de fin NO se envía: el backend la calcula con
  /// `DURACION_CITA_MINUTOS`.
  Future<Cita> crearCita(CitaCreate cita) async {
    final http.Response response = await _enviar(
      'POST',
      '/agenda-citas/citas',
      body: cita.toJson(),
      escritura: true,
    );

    if (response.statusCode == 201) {
      return _citaDesdeRespuesta(response);
    }

    throw AgendaException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Reprograma una cita propia.
  ///
  /// `PUT {ApiConfig.baseUrl}/agenda-citas/citas/{cita_id}` -> 200
  Future<Cita> reprogramarCita(int citaId, CitaUpdate cambios) async {
    final http.Response response = await _enviar(
      'PUT',
      '/agenda-citas/citas/$citaId',
      body: cambios.toJson(),
      escritura: true,
    );

    if (response.statusCode == 200) {
      return _citaDesdeRespuesta(response);
    }

    throw AgendaException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Cambia el estado de una cita propia (el paciente solo usa `CANCELADA`).
  ///
  /// `PATCH {ApiConfig.baseUrl}/agenda-citas/citas/{cita_id}/estado` -> 200
  Future<Cita> cambiarEstadoCita(int citaId, String estado) async {
    final http.Response response = await _enviar(
      'PATCH',
      '/agenda-citas/citas/$citaId/estado',
      body: <String, dynamic>{'estado': estado},
      escritura: true,
    );

    if (response.statusCode == 200) {
      return _citaDesdeRespuesta(response);
    }

    throw AgendaException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Convierte una respuesta 200/201 en [Cita].
  Cita _citaDesdeRespuesta(http.Response response) {
    try {
      final Object? body = jsonDecode(response.body);

      if (body is! Map<String, dynamic>) {
        throw const FormatException('Cuerpo de respuesta inesperado');
      }

      return Cita.fromJson(body);
    } on FormatException {
      throw const AgendaException(
        'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
      );
    } on TypeError {
      throw const AgendaException(
        'La respuesta del servidor no tiene el formato esperado.',
      );
    }
  }

  /// Convierte el error HTTP de FastAPI en un mensaje entendible,
  /// prefiriendo siempre el campo `detail`.
  String _mensajeError(http.Response response) {

    try {
      final Object? body = jsonDecode(response.body);

      if (body is Map<String, dynamic> && body['detail'] != null) {
        final Object? detail = body['detail'];

        if (detail is String && detail.trim().isNotEmpty) {
          return detail.trim();
        }

        // Errores de validación 422 de FastAPI llegan como lista de objetos.
        if (detail is List && detail.isNotEmpty) {
          final mensajes = <String>[
            for (final item in detail)
              if (item is Map<String, dynamic> && item['msg'] is String)
                item['msg'] as String,
          ];

          if (mensajes.isNotEmpty) {
            return mensajes.map(_limpiarMensajeValidacion).join('\n');
          }
        }
      }
    } on FormatException {
      // El cuerpo no es JSON: se usa el mensaje genérico de abajo.
    }

    switch (response.statusCode) {
      case 400:
        return 'Los datos enviados no son válidos. Revisa la información.';
      case 401:
        return 'Tu sesión expiró. Vuelve a iniciar sesión.';
      case 403:
        return 'No tienes permisos para realizar esta operación.';
      case 404:
        return 'No se encontró la información solicitada.';
      case 409:
        return 'Este horario acaba de ser ocupado. Selecciona otro disponible.';
      case 422:
        return 'La fecha o los datos enviados no son válidos.';
      case 500:
        return 'Ocurrió un error en el servidor. Inténtalo más tarde.';
      case 503:
        return 'El servicio no está disponible en este momento. '
            'Inténtalo más tarde.';
      default:
        return 'No se pudo completar la solicitud '
            '(código ${response.statusCode}). Inténtalo de nuevo.';
    }
  }

  /// Quita el prefijo "Value error, " de los mensajes de validación.
  String _limpiarMensajeValidacion(String mensaje) {
    const prefijo = 'Value error, ';
    if (mensaje.startsWith(prefijo)) {
      return mensaje.substring(prefijo.length);
    }
    return mensaje;
  }

  /// Formatea una fecha como `YYYY-MM-DD`.
  static String _fechaIso(DateTime fecha) {
    final mes = fecha.month.toString().padLeft(2, '0');
    final dia = fecha.day.toString().padLeft(2, '0');
    return '${fecha.year}-$mes-$dia';
  }
}
