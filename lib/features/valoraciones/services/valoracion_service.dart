import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/api_config.dart';
import '../../../core/storage/token_storage.dart';
import '../models/valoracion_models.dart';

/// Excepción controlada para errores del módulo CU40 — Valoraciones.
class ValoracionException implements Exception {
  const ValoracionException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Servicio HTTP de CU40 — Registrar y Actualizar valoración de la clínica.
///
/// Usa exclusivamente el JWT almacenado en [TokenStorage]; nunca envía
/// `paciente_id` ni `empresa_id` porque el backend los resuelve del token
/// dentro de la base de datos del tenant correspondiente.
class ValoracionService {
  ValoracionService({
    http.Client? client,
    Future<String?> Function()? leerToken,
  }) : _client = client ?? http.Client(),
       _leerToken = leerToken ?? (() => TokenStorage().getToken());

  final http.Client _client;
  final Future<String?> Function() _leerToken;

  static const Duration _timeout = Duration(seconds: 20);

  /// Obtiene pendientes, atenciones y valoraciones registradas del paciente.
  ///
  /// `GET {ApiConfig.baseUrl}/seguridad/valoraciones/resumen`
  Future<ResumenValoracionesPaciente> obtenerResumen() async {
    final response = await _get('/seguridad/valoraciones/resumen');

    if (response.statusCode == 200) {
      final body = _objeto(response);
      try {
        return ResumenValoracionesPaciente.fromJson(body);
      } on TypeError {
        throw const ValoracionException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      } on FormatException {
        throw const ValoracionException(
          'La respuesta del servidor no tiene el formato esperado.',
        );
      }
    }

    throw ValoracionException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Lista los avisos post-atención pendientes por valorar.
  ///
  /// `GET {ApiConfig.baseUrl}/seguridad/valoraciones/pendientes`
  Future<List<NotificacionValoracion>> listarPendientes() async {
    final response = await _get('/seguridad/valoraciones/pendientes');

    if (response.statusCode == 200) {
      return _lista(response, NotificacionValoracion.fromJson);
    }

    throw ValoracionException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Marca como leído un aviso de valoración en el backend.
  ///
  /// `PATCH {ApiConfig.baseUrl}/seguridad/valoraciones/notificaciones/{id}/leer`
  Future<NotificacionValoracion> marcarNotificacionLeida(
    int notificacionId,
  ) async {
    final response = await _patch(
      '/seguridad/valoraciones/notificaciones/$notificacionId/leer',
    );

    if (response.statusCode == 200) {
      return NotificacionValoracion.fromJson(_objeto(response));
    }

    throw ValoracionException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Registra una nueva valoración para una atención médica finalizada.
  ///
  /// `POST {ApiConfig.baseUrl}/seguridad/valoraciones`
  Future<ValoracionClinica> registrarValoracion({
    required int consultaClinicaId,
    required int puntuacion,
    String? comentario,
  }) async {
    final comentarioLimpio = comentario?.trim();
    final response = await _post('/seguridad/valoraciones', <String, dynamic>{
      'consulta_clinica_id': consultaClinicaId,
      'puntuacion': puntuacion,
      'comentario': (comentarioLimpio == null || comentarioLimpio.isEmpty)
          ? null
          : comentarioLimpio,
    });

    if (response.statusCode == 201 || response.statusCode == 200) {
      return _decodificarValoracion(response);
    }

    throw ValoracionException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  /// Actualiza una valoración ya existente sin generar registros duplicados.
  ///
  /// `PUT {ApiConfig.baseUrl}/seguridad/valoraciones/{valoracionId}`
  Future<ValoracionClinica> actualizarValoracion({
    required int valoracionId,
    required int puntuacion,
    String? comentario,
  }) async {
    final comentarioLimpio = comentario?.trim();
    final response = await _put(
      '/seguridad/valoraciones/$valoracionId',
      <String, dynamic>{
        'puntuacion': puntuacion,
        'comentario': (comentarioLimpio == null || comentarioLimpio.isEmpty)
            ? null
            : comentarioLimpio,
      },
    );

    if (response.statusCode == 200) {
      return _decodificarValoracion(response);
    }

    throw ValoracionException(
      _mensajeError(response),
      statusCode: response.statusCode,
    );
  }

  ValoracionClinica _decodificarValoracion(http.Response response) {
    final body = _objeto(response);
    try {
      return ValoracionClinica.fromJson(body);
    } on TypeError {
      throw const ValoracionException(
        'La respuesta del servidor no tiene el formato esperado.',
      );
    } on FormatException {
      throw const ValoracionException(
        'La respuesta del servidor no tiene el formato esperado.',
      );
    }
  }

  Future<http.Response> _get(String ruta) async {
    final token = await _token();
    final uri = Uri.parse('${ApiConfig.baseUrl}$ruta');
    return _ejecutar(
      () => _client
          .get(uri, headers: _headers(token))
          .timeout(_timeout),
    );
  }

  Future<http.Response> _post(String ruta, Map<String, dynamic> cuerpo) async {
    final token = await _token();
    final uri = Uri.parse('${ApiConfig.baseUrl}$ruta');
    return _ejecutar(
      () => _client
          .post(
            uri,
            headers: _headers(token, json: true),
            body: jsonEncode(cuerpo),
          )
          .timeout(_timeout),
    );
  }

  Future<http.Response> _put(String ruta, Map<String, dynamic> cuerpo) async {
    final token = await _token();
    final uri = Uri.parse('${ApiConfig.baseUrl}$ruta');
    return _ejecutar(
      () => _client
          .put(
            uri,
            headers: _headers(token, json: true),
            body: jsonEncode(cuerpo),
          )
          .timeout(_timeout),
    );
  }

  Future<http.Response> _patch(String ruta) async {
    final token = await _token();
    final uri = Uri.parse('${ApiConfig.baseUrl}$ruta');
    return _ejecutar(
      () => _client
          .patch(uri, headers: _headers(token))
          .timeout(_timeout),
    );
  }

  Future<http.Response> _ejecutar(Future<http.Response> Function() fn) async {
    try {
      return await fn();
    } on TimeoutException {
      throw const ValoracionException(
        'El servidor tardó demasiado en responder. Inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const ValoracionException(
        'No se pudo conectar con el servidor. '
        'Verifica tu conexión e inténtalo de nuevo.',
      );
    } on Exception {
      throw const ValoracionException(
        'Ocurrió un error de conexión inesperado. Inténtalo de nuevo.',
      );
    }
  }

  Future<String> _token() async {
    final token = await _leerToken();
    if (token == null || token.isEmpty) {
      throw const ValoracionException(
        'Tu sesión no es válida. Vuelve a iniciar sesión.',
        statusCode: 401,
      );
    }
    return token;
  }

  Map<String, String> _headers(String token, {bool json = false}) => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
    if (json) 'Content-Type': 'application/json',
  };

  Map<String, dynamic> _objeto(http.Response response) {
    try {
      final Object? body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        return body;
      }
    } on FormatException {
      // Se maneja abajo.
    }
    throw const ValoracionException(
      'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
    );
  }

  List<T> _lista<T>(
    http.Response response,
    T Function(Map<String, dynamic>) mapear,
  ) {
    try {
      final Object? body = jsonDecode(response.body);
      if (body is! List) {
        throw const FormatException('Cuerpo inesperado');
      }
      return [
        for (final item in body)
          if (item is Map<String, dynamic>) mapear(item),
      ];
    } on FormatException {
      throw const ValoracionException(
        'El servidor devolvió una respuesta inesperada. Inténtalo de nuevo.',
      );
    } on TypeError {
      throw const ValoracionException(
        'La respuesta del servidor no tiene el formato esperado.',
      );
    }
  }

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
            return mensajes.map(_limpiarValidacion).join('\n');
          }
        }
      }
    } on FormatException {
      // Se usa el mensaje por código HTTP.
    }

    switch (response.statusCode) {
      case 401:
        return 'Tu sesión expiró. Vuelve a iniciar sesión.';
      case 403:
        return 'Solo los pacientes autenticados pueden registrar o actualizar valoraciones.';
      case 404:
        return 'No se encontró la atención o valoración solicitada.';
      case 409:
        return 'Ya registraste una valoración para esta atención. Puedes actualizarla.';
      case 422:
        return 'Verifica la puntuación seleccionada y el comentario ingresado.';
      default:
        return 'No se pudo completar la operación '
            '(código ${response.statusCode}). Inténtalo de nuevo.';
    }
  }

  String _limpiarValidacion(String mensaje) {
    const prefijo = 'Value error, ';
    if (mensaje.startsWith(prefijo)) {
      return mensaje.substring(prefijo.length);
    }
    return mensaje;
  }
}
