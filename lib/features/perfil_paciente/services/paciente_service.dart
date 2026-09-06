import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/mi_perfil_paciente.dart';

/// Excepción lanzada cuando falla una petición del paciente.
class PacienteException implements Exception {
  const PacienteException(this.message, {this.statusCode});

  /// Mensaje entendible para mostrar al usuario.
  final String message;

  /// Código HTTP cuando el backend respondió (ej. 401, 403, 404).
  final int? statusCode;

  @override
  String toString() => message;
}

/// Servicio del paciente. Mantiene las llamadas HTTP fuera de las páginas.
class PacienteService {
  PacienteService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Tiempo máximo de espera para una respuesta del servidor.
  static const Duration _timeout = Duration(seconds: 20);

  /// Obtiene el perfil REAL del paciente autenticado:
  ///
  /// `GET {ApiConfig.baseUrl}/pacientes/me`
  ///
  /// 1. Lee el JWT con [TokenStorage].
  /// 2. Envía `Authorization: Bearer <token>`.
  /// 3. Convierte la respuesta 200 en [MiPerfilPaciente].
  ///
  /// Lanza [PacienteException] con el `detail` del backend cuando existe.
  Future<MiPerfilPaciente> obtenerMiPerfil() async {
    final token = await TokenStorage().getToken();

    if (token == null || token.isEmpty) {
      throw const PacienteException(
        'Tu sesión no es válida. Vuelve a iniciar sesión.',
        statusCode: 401,
      );
    }

    http.Response response;

    try {
      response = await _client
          .get(
            Uri.parse('${ApiConfig.baseUrl}/pacientes/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/json',
            },
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const PacienteException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const PacienteException(
        'No se pudo conectar con el servidor. '
        'Verifica tu conexión e inténtalo de nuevo.',
      );
    } on Exception {
      throw const PacienteException(
        'Ocurrió un error de conexión inesperado. Inténtalo de nuevo.',
      );
    }

    if (response.statusCode == 200) {
      try {
        final Object? body = jsonDecode(response.body);

        if (body is! Map<String, dynamic>) {
          throw const FormatException('Cuerpo de respuesta inesperado');
        }

        return MiPerfilPaciente.fromJson(body);
      } on FormatException {
        throw const PacienteException(
          'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
        );
      } on TypeError {
        throw const PacienteException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw PacienteException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Actualiza la información personal del paciente autenticado:
  ///
  /// `PUT {ApiConfig.baseUrl}/pacientes/me`
  ///
  /// Envía únicamente los campos permitidos y el JWT en la cabecera.
  /// Devuelve el perfil actualizado si la respuesta es 200.
  Future<MiPerfilPaciente> actualizarPerfilPropio(
    ActualizarPerfilRequest request,
  ) async {
    final token = await TokenStorage().getToken();

    if (token == null || token.isEmpty) {
      throw const PacienteException(
        'Tu sesión no es válida. Vuelve a iniciar sesión.',
        statusCode: 401,
      );
    }

    http.Response response;

    try {
      response = await _client
          .put(
            Uri.parse('${ApiConfig.baseUrl}/pacientes/me'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const PacienteException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const PacienteException(
        'No se pudo conectar con el servidor. '
        'Verifica tu conexión e inténtalo de nuevo.',
      );
    } on Exception {
      throw const PacienteException(
        'Ocurrió un error de conexión inesperado. Inténtalo de nuevo.',
      );
    }

    if (response.statusCode == 200) {
      try {
        final Object? body = jsonDecode(response.body);

        if (body is! Map<String, dynamic>) {
          throw const FormatException('Cuerpo de respuesta inesperado');
        }

        return MiPerfilPaciente.fromJson(body);
      } on FormatException {
        throw const PacienteException(
          'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
        );
      } on TypeError {
        throw const PacienteException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw PacienteException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
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
        return 'No tienes permisos para ver este perfil.';
      case 404:
        return 'No se encontró el perfil del paciente.';
      default:
        return 'No se pudo cargar tu perfil '
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
}
