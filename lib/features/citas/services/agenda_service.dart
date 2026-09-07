import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/agenda_models.dart';

/// Excepción lanzada cuando falla una petición de CU09.
class AgendaException implements Exception {
  const AgendaException(this.message, {this.statusCode});

  /// Mensaje entendible para mostrar al usuario.
  final String message;

  /// Código HTTP cuando el backend respondió (ej. 401, 403, 404, 422, 500).
  final int? statusCode;

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
  Future<http.Response> _get(String ruta, Map<String, String>? query) async {
    final token = await _leerToken();

    if (token == null || token.isEmpty) {
      throw const AgendaException(
        'Tu sesión no es válida. Vuelve a iniciar sesión.',
        statusCode: 401,
      );
    }

    final Uri uri = Uri.parse('${ApiConfig.baseUrl}$ruta')
        .replace(queryParameters: query);

    try {
      return await _client
          .get(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const AgendaException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const AgendaException(
        'No se pudo conectar con el servidor. '
        'Verifica tu conexión e inténtalo de nuevo.',
      );
    } on Exception {
      throw const AgendaException(
        'Ocurrió un error de conexión inesperado. Inténtalo de nuevo.',
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
      case 401:
        return 'Tu sesión expiró. Vuelve a iniciar sesión.';
      case 403:
        return 'No tienes permisos para consultar la disponibilidad.';
      case 404:
        return 'No se encontró el oftalmólogo solicitado.';
      case 422:
        return 'La fecha o los datos enviados no son válidos.';
      case 500:
        return 'Ocurrió un error en el servidor. Inténtalo más tarde.';
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
